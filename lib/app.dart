import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/provider_registry.dart';
import 'services/auth/oauth_registry.dart';
import 'services/history_service.dart';
import 'services/native/native_bridge.dart';
import 'services/settings_service.dart';
import 'services/shell_controller.dart';
import 'services/update_checker.dart';
import 'services/usage_controller.dart';
import 'ui/panel/provider_detail_view.dart';
import 'ui/panel/provider_connect_view.dart';
import 'ui/panel/onboarding_view.dart';
import 'ui/panel/settings_view.dart';
import 'ui/panel/slot_picker_view.dart';
import 'ui/rail/rail_shell.dart';
import 'ui/theme/app_theme.dart';

/// Root widget. Publishes the app's services and renders whichever surface the
/// window is currently being used for.
///
/// The window is transparent — every surface draws its own card — so the
/// scaffold background is cleared in the theme.
class AiUsageMonitorApp extends StatelessWidget {
  const AiUsageMonitorApp({
    super.key,
    required this.native,
    required this.registry,
    required this.settingsService,
    required this.historyService,
    required this.usageController,
    required this.shellController,
    required this.oauthRegistry,
    required this.updateChecker,
  });

  final NativeBridge native;
  final ProviderRegistry registry;
  final SettingsService settingsService;
  final HistoryService historyService;
  final UsageController usageController;
  final ShellController shellController;
  final OAuthRegistry oauthRegistry;
  final UpdateChecker updateChecker;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<NativeBridge>.value(value: native),
        Provider<ProviderRegistry>.value(value: registry),
        Provider<HistoryService>.value(value: historyService),
        Provider<OAuthRegistry>.value(value: oauthRegistry),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<UsageController>.value(value: usageController),
        ChangeNotifierProvider<ShellController>.value(value: shellController),
        ChangeNotifierProvider<UpdateChecker>.value(value: updateChecker),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) => MaterialApp(
          title: 'DevNotch',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.of(Brightness.light),
          darkTheme: AppTheme.of(Brightness.dark),
          themeMode: settings.settings.themeMode,
          home: const _TransparentHost(child: _SurfaceRouter()),
        ),
      ),
    );
  }
}

/// Chooses the surface for the window's current purpose.
class _SurfaceRouter extends StatelessWidget {
  const _SurfaceRouter();

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();

    return switch (shell.surface) {
      ShellSurface.rail => const RailShell(),
      ShellSurface.connectProvider => ProviderConnectView(
        providerId:
            shell.detailProviderId ?? context.read<ProviderRegistry>().all.first.id,
      ),
      ShellSurface.settings => const SettingsView(),
      ShellSurface.onboarding => const OnboardingView(),
      ShellSurface.slotPicker => const SlotPickerView(),
      ShellSurface.providerDetail => ProviderDetailView(
          // The router only reaches this surface via `openPanel`, which always
          // supplies the id; the fallback keeps a malformed state from
          // crashing rather than showing the wrong provider.
          providerId:
              shell.detailProviderId ?? context.read<ProviderRegistry>().primary.id,
        ),
    };
  }
}

class _TransparentHost extends StatelessWidget {
  const _TransparentHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DefaultTextStyle(
        style: TextStyle(color: context.palette.textPrimary),
        child: child,
      ),
    );
  }
}
