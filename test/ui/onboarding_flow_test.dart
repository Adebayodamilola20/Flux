import 'package:ai_usage_monitor/providers/provider_registry.dart';
import 'package:ai_usage_monitor/services/history_service.dart';
import 'package:ai_usage_monitor/services/settings_service.dart';
import 'package:ai_usage_monitor/services/shell_controller.dart';
import 'package:ai_usage_monitor/services/usage_controller.dart';
import 'package:ai_usage_monitor/ui/panel/onboarding_view.dart';
import 'package:ai_usage_monitor/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_native_bridge.dart';
import '../support/fake_provider.dart';

/// The first run, pressed through the way a new user would.
///
/// Intro → Next → the three slots and their plus marks → Next → Settings,
/// and the intro never comes back.
void main() {
  late FakeNativeBridge native;
  late SettingsService settings;
  late UsageController usage;
  late ShellController shell;

  setUp(() async {
    native = FakeNativeBridge();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    settings = SettingsService(preferences: preferences, native: native);
    await settings.load();
    usage = UsageController(
      registry: ProviderRegistry([
        FakeProvider(id: 'claude', displayName: 'Claude'),
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
  });

  var disposed = false;
  void disposeControllers() {
    if (disposed) return;
    disposed = true;
    shell.dispose();
    usage.dispose();
  }

  tearDown(() {
    disposeControllers();
    disposed = false;
    native.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(ShellController.onboardingSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<UsageController>.value(value: usage),
          ChangeNotifierProvider<ShellController>.value(value: shell),
        ],
        child: MaterialApp(
          theme: AppTheme.of(Brightness.dark),
          home: const Scaffold(body: OnboardingView()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a new user is shown what it is, then the slots, then Settings',
      (tester) async {
    expect(settings.settings.onboardingComplete, isFalse);
    expect(settings.settings.slots, everyElement(isNull));

    await pump(tester);

    // The intro: the name and one button.
    expect(find.text('Dev'), findsOneWidget);
    expect(find.text('Notch'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // The slots page: three positions, two of them showing the plus to click.
    expect(find.text('Three slots. Fill them yourself.'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNWidgets(2));
    expect(find.text('62%'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Done: Settings is what opens, and the intro is marked as seen.
    expect(shell.surface, ShellSurface.settings);
    expect(settings.settings.onboardingComplete, isTrue);
    expect(settings.settings.slots, everyElement(isNull),
        reason: 'nothing was put on the rail on the user\'s behalf');

    // Opening Settings starts the shell's own timers; the widget test binding
    // wants them gone before the tree is torn down.
    disposeControllers();
    await tester.pump();
  });
}
