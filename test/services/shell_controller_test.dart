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
        FakeProvider(id: 'gemini', displayName: 'Gemini'),
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
    test('shows the connect screen on a first run', () async {
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

    test('goes to the rail when a provider is already connected', () async {
      await boot();
      provider.seedConnected();
      await usage.start();
      await shell.start();

      // Onboarding was never completed, but there is something to show, so the
      // connect screen would be a wall in front of a working product.
      expect(shell.surface, ShellSurface.rail);
    });

    test('reads its geometry from the native layer', () async {
      await boot();
      await shell.start();

      expect(shell.metrics.slots, 3);
      expect(shell.metrics.collapsedWidth, 52);
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

    test('finishing onboarding records it so it is not shown again', () async {
      await boot();
      await shell.start();
      expect(settings.settings.onboardingComplete, isFalse);

      await shell.finishOnboarding();

      expect(settings.settings.onboardingComplete, isTrue);
      expect(shell.surface, ShellSurface.rail);
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
}
