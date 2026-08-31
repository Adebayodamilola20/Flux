import 'package:ai_usage_monitor/models/rail_placement.dart';
import 'package:ai_usage_monitor/services/native/native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeBridge against a fake macOS layer', () {
    late FakeNativeBridge native;

    setUp(() => native = FakeNativeBridge());
    tearDown(() => native.dispose());

    test('encodes menu bar updates over the channel', () async {
      await native.updateMenuBar(
        showIcon: true,
        showPercent: true,
        percent: 52,
      );

      expect(native.menuBarUpdates, hasLength(1));
      expect(native.menuBarUpdates.single.percent, 52);
      expect(native.menuBarUpdates.single.isError, isFalse);
    });

    test('carries a null percentage through as unknown', () async {
      await native.updateMenuBar(
        showIcon: true,
        showPercent: true,
        percent: null,
        isError: true,
      );

      expect(native.menuBarUpdates.single.percent, isNull);
      expect(native.menuBarUpdates.single.isError, isTrue);
    });

    test('reads rail geometry from the native layer', () async {
      final metrics = await native.railMetrics();

      expect(metrics.slots, 3);
      expect(metrics.expandedWidth, 280);
      // Derived, not sent: one slot height per slot, plus padding at both ends.
      expect(metrics.collapsedHeight, 3 * 58 + 16 * 2);
    });

    test('falls back to declared geometry when native says nothing', () async {
      final bridge = NativeBridge(
        channel: const MethodChannel('com.aiusagemonitor/absent'),
      );
      expect(await bridge.railMetrics(), same(RailMetrics.fallback));
    });

    test('encodes rail placement', () async {
      await native.configureRail(
        edge: RailEdge.left,
        offset: 0.25,
        screenId: 'display-2',
      );

      expect(native.placements.single.edge, 'left');
      expect(native.placements.single.offset, 0.25);
      expect(native.placements.single.screenId, 'display-2');
    });

    test('shows and hides the rail and the panel', () async {
      await native.showRail(pinnedOpen: false);
      expect(native.isRailVisible, isTrue);

      await native.showPanel(size: const Size(760, 600));
      expect(native.panelSizes.single, const Size(760, 600));

      await native.hidePanel();
      expect(native.isPanelVisible, isFalse);

      await native.hideRail();
      expect(native.isRailVisible, isFalse);
    });

    test('decodes the display list', () async {
      native.screens = [
        {'id': '1', 'name': 'Built-in', 'isPrimary': true},
        {'id': '2', 'name': 'Studio Display', 'isPrimary': false},
        {'name': 'no id'}, // malformed
      ];

      final screens = await native.listScreens();
      expect(screens.map((s) => s.id), ['1', '2']);
      expect(screens.first.isPrimary, isTrue);
    });

    test('opens a URL and reports refusal honestly', () async {
      expect(await native.openUrl(Uri.parse('https://example.com/a')), isTrue);
      expect(native.openedUrls, ['https://example.com/a']);

      native.allowUrlOpen = false;
      expect(await native.openUrl(Uri.parse('https://example.com/b')), isFalse);
      expect(native.openedUrls, hasLength(1));
    });

    test('round-trips a secret and removes it with a null value', () async {
      expect(await native.readSecret('key'), isNull);

      expect(await native.writeSecret('key', 'value'), isTrue);
      expect(await native.readSecret('key'), 'value');

      expect(await native.writeSecret('key', null), isTrue);
      expect(await native.readSecret('key'), isNull);
    });

    test('mirrors login item state', () async {
      expect(await native.isLaunchAtLoginEnabled(), isFalse);
      expect(await native.setLaunchAtLogin(true), isTrue);
      expect(await native.isLaunchAtLoginEnabled(), isTrue);
    });

    test('reports the real outcome when macOS refuses registration', () async {
      native.allowLoginItemChanges = false;
      expect(await native.setLaunchAtLogin(true), isFalse);
      expect(await native.isLaunchAtLoginEnabled(), isFalse);
    });

    test('decodes process matches', () async {
      native.processes = [
        {
          'pid': 1234,
          'name': 'claude',
          'host': 'Terminal',
          'startedAt': 1750000000.0,
        },
      ];

      final found = await native.findProcesses(['claude']);
      expect(found, hasLength(1));
      expect(found.single.pid, 1234);
      expect(found.single.host, 'Terminal');
      expect(found.single.startedAt, isNotNull);
    });

    test('filters out malformed process entries', () async {
      native.processes = [
        {'name': 'claude'}, // no pid
        {'pid': 7, 'name': 'claude'},
      ];
      final found = await native.findProcesses(['claude']);
      expect(found, hasLength(1));
      expect(found.single.pid, 7);
    });

    test('returns an empty list when nothing matches', () async {
      native.processes = [
        {'pid': 1, 'name': 'something-else'},
      ];
      expect(await native.findProcesses(['claude']), isEmpty);
    });

    test('routes native callbacks to their handlers', () async {
      final expansions = <bool>[];
      var refresh = 0;
      var settings = 0;
      var toggle = 0;
      String? mode;
      Uri? callback;

      native.onExpansionChanged = expansions.add;
      native.onRefreshRequested = () => refresh++;
      native.onSettingsRequested = () => settings++;
      native.onRailToggleRequested = () => toggle++;
      native.onModeChanged = (value) => mode = value;
      native.onAuthCallback = (value) => callback = value;

      Future<void> send(String method, [Object? args]) {
        return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              native.channelName,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall(method, args),
              ),
              (_) {},
            );
      }

      await send('rail.expansionChanged', {'expanded': true});
      await send('rail.expansionChanged', {'expanded': false});
      await send('refreshRequested');
      await send('settingsRequested');
      await send('railToggleRequested');
      await send('window.modeChanged', {'mode': 'panel'});
      await send('auth.callback', {'url': 'aiusagemonitor://done?code=abc'});

      expect(expansions, [true, false]);
      expect([refresh, settings, toggle], [1, 1, 1]);
      expect(mode, 'panel');
      expect(callback?.scheme, 'aiusagemonitor');
    });
  });

  group('without a native layer', () {
    test('degrades quietly so tests and headless runs still work', () async {
      final bridge = NativeBridge(
        channel: const MethodChannel('com.aiusagemonitor/absent'),
      );

      // No handler is registered, so every call raises MissingPluginException
      // internally; none of it should surface to the caller.
      await bridge.updateMenuBar(showIcon: true, showPercent: true);
      expect(await bridge.readSecret('key'), isNull);
      expect(await bridge.isLaunchAtLoginEnabled(), isFalse);
      expect(await bridge.findProcesses(['claude']), isEmpty);
    });
  });
}
