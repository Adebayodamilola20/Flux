import 'package:ai_usage_monitor/models/rail_placement.dart';
import 'package:ai_usage_monitor/providers/provider_registry.dart';
import 'package:ai_usage_monitor/services/history_service.dart';
import 'package:ai_usage_monitor/services/settings_service.dart';
import 'package:ai_usage_monitor/services/shell_controller.dart';
import 'package:ai_usage_monitor/services/usage_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_native_bridge.dart';
import '../support/fake_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge native;
  late SharedPreferences preferences;
  late SettingsService settings;
  late FakeProvider provider;
  late UsageController usage;
  late ShellController shell;

  Future<void> boot({Map<String, Object> prefs = const {}}) async {
    native = FakeNativeBridge();
    SharedPreferences.setMockInitialValues(prefs);
    preferences = await SharedPreferences.getInstance();

    settings = SettingsService(preferences: preferences, native: native);
    await settings.load();

    provider = FakeProvider(id: 'claude', displayName: 'Claude');
    usage = UsageController(
      registry: ProviderRegistry([
        provider,
        FakeProvider(id: 'chatgpt', displayName: 'Codex'),
        FakeProvider(id: 'opencode', displayName: 'OpenCode'),
      ]),
      settingsService: settings,
      historyService: HistoryService(preferences: preferences),
      native: native,
    );

    shell = ShellController(
      native: native,
      settingsService: settings,
      usageController: usage,
    );
  }

  tearDown(() {
    shell.dispose();
    usage.dispose();
    native.dispose();
  });

  group('startup surface', () {
    test('opens the onboarding panel on a first run', () async {
      await boot();
      await shell.start();

      expect(shell.surface, ShellSurface.onboarding);
      expect(native.isPanelVisible, isTrue);
      expect(native.panelSizes.last, ShellController.onboardingSize);
    });

    test('goes straight to the rail once onboarding is done', () async {
      await boot(
        prefs: {'flutter.app_settings_v1': '{"onboardingComplete":true}'},
      );
      await shell.start();

      expect(shell.surface, ShellSurface.rail);
      expect(native.isRailVisible, isTrue);
    });

    test('still opens onboarding until it has been completed', () async {
      await boot();
      provider.seedConnected();
      await usage.start();
      await shell.start();

      expect(shell.surface, ShellSurface.onboarding);
      expect(native.isPanelVisible, isTrue);
    });

    test('reads its geometry from the native layer', () async {
      await boot();
      await shell.start();

      expect(shell.metrics.slots, 3);
      expect(shell.metrics.collapsedWidth, 46);
    });

    test('loads the display list for the monitor picker', () async {
      await boot();
      await shell.start();

      expect(shell.screens, isNotEmpty);
      expect(shell.screens.first.isPrimary, isTrue);
    });
  });

  group('placement', () {
    test('pushes edge, offset, and monitor down to the window', () async {
      await boot(
        prefs: {
          'flutter.app_settings_v1':
              '{"onboardingComplete":true,"railEdge":"left","railOffset":0.25}',
        },
      );
      await shell.start();

      final placement = native.placements.last;
      expect(placement.edge, 'left');
      expect(placement.offset, 0.25);
    });

    test('reapplies placement when the user moves the rail', () async {
      await boot(
        prefs: {'flutter.app_settings_v1': '{"onboardingComplete":true}'},
      );
      await shell.start();
      final before = native.placements.length;

      await settings.update(
        settings.settings.copyWith(railEdge: RailEdge.left),
      );
      await Future<void>.delayed(Duration.zero);

      expect(native.placements.length, greaterThan(before));
      expect(native.placements.last.edge, 'left');
    });

    test('ignores preference changes that do not move the rail', () async {
      await boot(
        prefs: {'flutter.app_settings_v1': '{"onboardingComplete":true}'},
      );
      await shell.start();
      final before = native.placements.length;

      await settings.update(settings.settings.copyWith(recordHistory: false));
      await Future<void>.delayed(Duration.zero);

      // Editing an unrelated preference must not make the widget jump.
      expect(native.placements.length, before);
    });
  });

  group('expansion', () {
    test('follows the pointer state reported by the native layer', () async {
      await boot(
        prefs: {'flutter.app_settings_v1': '{"onboardingComplete":true}'},
      );
      await shell.start();

      expect(shell.isExpanded, isFalse);
      native.onExpansionChanged!(true);
      expect(shell.isExpanded, isTrue);
      native.onExpansionChanged!(false);
      expect(shell.isExpanded, isFalse);
    });

    test('stays expanded when the user pinned it open', () async {
      await boot(
        prefs: {
          'flutter.app_settings_v1':
              '{"onboardingComplete":true,"railExpansion":"alwaysExpanded"}',
        },
      );
      await shell.start();

      expect(shell.isExpanded, isTrue);
      native.onExpansionChanged!(false);
      expect(shell.isExpanded, isTrue);
    });
  });

  group('surfaces', () {
    test('opening settings switches the window to a panel', () async {
      await boot(
        prefs: {'flutter.app_settings_v1': '{"onboardingComplete":true}'},
      );
      await shell.start();

      await shell.openPanel(ShellSurface.settings);

      expect(shell.surface, ShellSurface.settings);
      expect(native.panelSizes.last, ShellController.settingsSize);
    });

    test('opening a provider detail remembers which provider', () async {
      await boot(
        prefs: {'flutter.app_settings_v1': '{"onboardingComplete":true}'},
      );
      await shell.start();

      await shell.openPanel(ShellSurface.providerDetail, providerId: 'claude');

      expect(shell.detailProviderId, 'claude');
    });

    test('returning to the rail hides the panel', () async {
      await boot(
        prefs: {'flutter.app_settings_v1': '{"onboardingComplete":true}'},
      );
      await shell.start();
      await shell.openPanel(ShellSurface.settings);

      await shell.showRail();

      expect(shell.surface, ShellSurface.rail);
      expect(native.isPanelVisible, isFalse);
      expect(native.isRailVisible, isTrue);
      expect(shell.detailProviderId, isNull);
    });

    test('connecting one app opens that app alone', () async {
      await boot();
      await shell.start();

      await shell.openPanel(ShellSurface.connectProvider, providerId: 'claude');

      // Not a grid of every provider: the user has already said which one.
      expect(shell.surface, ShellSurface.connectProvider);
      expect(shell.detailProviderId, 'claude');
      expect(native.panelSizes.last, ShellController.connectSize);
    });
  });

  group('menu bar fallback', () {
    test('toggling rail visibility hides and shows the window', () async {
      await boot(
        prefs: {'flutter.app_settings_v1': '{"onboardingComplete":true}'},
      );
      await shell.start();
      expect(native.isRailVisible, isTrue);

      await shell.toggleRailVisibility();
      expect(settings.settings.railVisible, isFalse);
      expect(native.isRailVisible, isFalse);

      await shell.toggleRailVisibility();
      expect(native.isRailVisible, isTrue);
    });
  });

  group('measurements', () {
    test('survive a re-read that fails', () async {
      // What was on screen: after a native read failed, the rail drew itself
      // from the built-in fallback — small rings, the settings control over
      // the last label — inside a window still sized for the real display.
      await boot();
      await shell.start();
      expect(shell.metrics.windowHeight, 358);

      native.failingMethods.add('rail.metrics');
      await shell.reloadMetrics();

      expect(shell.metrics.windowHeight, 358);
    });

    test('are read again when the window says so', () async {
      await boot();
      await shell.start();

      var notified = 0;
      shell.addListener(() => notified++);
      await shell.reloadMetrics();

      expect(notified, 1);
    });
  });
}
