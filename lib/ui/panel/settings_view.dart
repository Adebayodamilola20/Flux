import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import '../../models/app_settings.dart';
import '../../models/rail_placement.dart';
import '../../services/auth/oauth_registry.dart';
import '../../services/native/native_bridge.dart';
import '../../services/settings_service.dart';
import '../../services/shell_controller.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
import '../widgets/provider_glyph.dart';
import '../widgets/settings_controls.dart';
import 'panel_chrome.dart';

/// Preferences.
///
/// Grouped by what the user is thinking about — where the widget lives, how it
/// behaves, what it looks like, and what it is connected to — rather than by
/// which subsystem owns each value.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    final settingsService = context.watch<SettingsService>();
    final settings = settingsService.settings;

    Future<void> update(AppSettings next) => settingsService.update(next);

    return PanelChrome(
      title: 'Settings',
      onClose: shell.showRail,
      child: ListView(
        physics: const ClampingScrollPhysics(),
        children: [
          _RailSection(
            settings: settings,
            screens: shell.screens,
            onUpdate: update,
            onReloadScreens: shell.reloadScreens,
          ),
          const SizedBox(height: 20),
          _GeneralSection(settings: settings, onUpdate: update),
          const SizedBox(height: 20),
          _AppearanceSection(settings: settings, onUpdate: update),
          const SizedBox(height: 20),
          const _ProvidersSection(),
          const SizedBox(height: 20),
          const _SignInSetupSection(),
          const SizedBox(height: 20),
          _LocalTrackingSection(settings: settings, onUpdate: update),
        ],
      ),
    );
  }
}

class _RailSection extends StatelessWidget {
  const _RailSection({
    required this.settings,
    required this.screens,
    required this.onUpdate,
    required this.onReloadScreens,
  });

  final AppSettings settings;
  final List<NativeScreen> screens;
  final Future<void> Function(AppSettings) onUpdate;
  final Future<void> Function() onReloadScreens;

  @override
  Widget build(BuildContext context) {
    // A remembered display that is currently disconnected must not be shown as
    // the selection — the rail is not on it.
    final knownIds = screens.map((s) => s.id).toSet();
    final selectedScreen =
        knownIds.contains(settings.screenId) ? settings.screenId : null;

    return SettingsSection(
      title: 'Rail',
      children: [
        SettingsRow(
          label: 'Show the rail',
          description: 'Hide it to leave only the menu-bar item.',
          control: SettingsSwitch(
            value: settings.railVisible,
            onChanged: (v) => onUpdate(settings.copyWith(railVisible: v)),
          ),
        ),
        SettingsRow(
          label: 'Screen edge',
          control: SettingsDropdown<RailEdge>(
            value: settings.railEdge,
            items: RailEdge.values,
            labelBuilder: (e) => e.label,
            onChanged: (v) =>
                v == null ? null : onUpdate(settings.copyWith(railEdge: v)),
          ),
        ),
        SettingsRow(
          label: 'Vertical position',
          description: 'Where the rail sits along that edge.',
          control: SizedBox(
            width: 140,
            child: Slider(
              value: settings.railOffset.clamped(),
              min: 0.05,
              max: 0.95,
              onChanged: (v) =>
                  onUpdate(settings.copyWith(railOffset: RailOffset(v))),
            ),
          ),
        ),
        SettingsRow(
          label: 'Expansion',
          description: settings.railExpansion.detail,
          control: SettingsDropdown<RailExpansion>(
            value: settings.railExpansion,
            items: RailExpansion.values,
            labelBuilder: (e) => e.label,
            onChanged: (v) => v == null
                ? null
                : onUpdate(settings.copyWith(railExpansion: v)),
          ),
        ),
        SettingsRow(
          label: 'Monitor',
          description: screens.length < 2
              ? 'Only one display is connected.'
              : 'Which display the rail appears on.',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsDropdown<String?>(
                value: selectedScreen,
                items: [null, ...screens.map((s) => s.id)],
                labelBuilder: (id) {
                  if (id == null) return 'Main display';
                  final match = screens.where((s) => s.id == id).firstOrNull;
                  return match?.name ?? 'Display $id';
                },
                onChanged: (v) => onUpdate(
                  v == null
                      ? settings.copyWith(clearScreenId: true)
                      : settings.copyWith(screenId: v),
                ),
              ),
              const SizedBox(width: 6),
              PillButton(label: 'Rescan', onPressed: onReloadScreens),
            ],
          ),
        ),
      ],
    );
  }
}

class _GeneralSection extends StatelessWidget {
  const _GeneralSection({required this.settings, required this.onUpdate});

  final AppSettings settings;
  final Future<void> Function(AppSettings) onUpdate;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'General',
      children: [
        SettingsRow(
          label: 'Launch at login',
          control: SettingsSwitch(
            value: settings.launchAtLogin,
            onChanged: (v) => onUpdate(settings.copyWith(launchAtLogin: v)),
          ),
        ),
        SettingsRow(
          label: 'Refresh every',
          control: SettingsDropdown<Duration>(
            value: settings.refreshInterval,
            items: AppSettings.refreshIntervalOptions,
            labelBuilder: Format.interval,
            onChanged: (v) => v == null
                ? null
                : onUpdate(settings.copyWith(refreshInterval: v)),
          ),
        ),
        SettingsRow(
          label: 'Keep usage history',
          description: 'Stored on this Mac only.',
          control: SettingsSwitch(
            value: settings.recordHistory,
            onChanged: (v) => onUpdate(settings.copyWith(recordHistory: v)),
          ),
        ),
        SettingsRow(
          label: 'Menu-bar icon',
          description: 'A fallback control when the rail is hidden.',
          control: SettingsSwitch(
            value: settings.showMenuBarIcon,
            onChanged: (v) => onUpdate(settings.copyWith(showMenuBarIcon: v)),
          ),
        ),
        SettingsRow(
          label: 'Percentage in the menu bar',
          control: SettingsSwitch(
            value: settings.showMenuBarPercent,
            onChanged: (v) =>
                onUpdate(settings.copyWith(showMenuBarPercent: v)),
          ),
        ),
      ],
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.settings, required this.onUpdate});

  final AppSettings settings;
  final Future<void> Function(AppSettings) onUpdate;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Appearance',
      children: [
        SettingsRow(
          label: 'Theme',
          control: SettingsDropdown<ThemeMode>(
            value: settings.themeMode,
            items: ThemeMode.values,
            labelBuilder: (m) => switch (m) {
              ThemeMode.system => 'Match system',
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
            },
            onChanged: (v) =>
                v == null ? null : onUpdate(settings.copyWith(themeMode: v)),
          ),
        ),
      ],
    );
  }
}

class _ProvidersSection extends StatelessWidget {
  const _ProvidersSection();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final usage = context.watch<UsageController>();
    final shell = context.read<ShellController>();

    return SettingsSection(
      title: 'Providers',
      children: [
        for (final state in usage.states)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                ProviderGlyph(
                  providerId: state.id,
                  color: Color(state.descriptor.accent),
                  size: 13,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.displayName,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        state.connection.status.detail,
                        style: TextStyle(
                          fontSize: 10,
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                PillButton(
                  label: 'Manage',
                  onPressed: () => shell.openPanel(ShellSurface.onboarding),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Budgets used to turn locally counted tokens into a percentage.
class _LocalTrackingSection extends StatefulWidget {
  const _LocalTrackingSection({required this.settings, required this.onUpdate});

  final AppSettings settings;
  final Future<void> Function(AppSettings) onUpdate;

  @override
  State<_LocalTrackingSection> createState() => _LocalTrackingSectionState();
}

class _LocalTrackingSectionState extends State<_LocalTrackingSection> {
  late final TextEditingController _session = TextEditingController(
    text: widget.settings.sessionTokenBudget.toString(),
  );
  late final TextEditingController _weekly = TextEditingController(
    text: widget.settings.weeklyTokenBudget.toString(),
  );

  @override
  void dispose() {
    _session.dispose();
    _weekly.dispose();
    super.dispose();
  }

  void _commit() {
    final session = int.tryParse(_session.text.trim());
    final weekly = int.tryParse(_weekly.text.trim());
    widget.onUpdate(widget.settings.copyWith(
      sessionTokenBudget: session != null && session > 0 ? session : null,
      weeklyTokenBudget: weekly != null && weekly > 0 ? weekly : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SettingsSection(
      title: 'Local tracking',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Providers do not publish plan limits as token counts, so locally '
            'tracked percentages are measured against these budgets. They are '
            'starting points, not official figures — adjust them to match what '
            'your plan actually gives you.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: palette.textTertiary,
            ),
          ),
        ),
        SettingsRow(
          label: 'Session budget',
          description: 'Tokens per rolling 5-hour window.',
          control: SettingsTextField(
            controller: _session,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _commit(),
          ),
        ),
        SettingsRow(
          label: 'Weekly budget',
          description: 'Tokens per rolling 7 days.',
          control: SettingsTextField(
            controller: _weekly,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _commit(),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: PillButton(label: 'Apply budgets', onPressed: _commit),
        ),
      ],
    );
  }
}


/// Where the OAuth client for each browser-sign-in provider is registered.
///
/// OAuth has no way for an unregistered client to authenticate, and a client id
/// baked into a shipped binary is one revocation away from breaking every
/// install — so the id is configuration, entered here once by whoever publishes
/// the app. Until it is present, Connect says so rather than opening a browser
/// onto a provider error page.
class _SignInSetupSection extends StatefulWidget {
  const _SignInSetupSection();

  @override
  State<_SignInSetupSection> createState() => _SignInSetupSectionState();
}

class _SignInSetupSectionState extends State<_SignInSetupSection> {
  final Map<String, TextEditingController> _controllers = {};

  /// Outcome of the last import, shown under the row that triggered it.
  String? _importMessage;
  bool _importFailed = false;

  /// Imports the JSON file Google hands you when you create the client.
  Future<void> _import(
    String providerId,
    OAuthRegistry registry,
    NativeBridge native,
  ) async {
    final path = await native.pickFile(
      title: 'Choose your Google OAuth client JSON',
      extensions: const ['json'],
    );
    if (path == null) return;

    String contents;
    try {
      contents = await File(path).readAsString();
    } on FileSystemException {
      if (!mounted) return;
      setState(() {
        _importFailed = true;
        _importMessage = 'That file could not be read.';
      });
      return;
    }

    final clientId = await registry.importGoogleClientFile(
      contents,
      providerId,
    );
    if (!mounted) return;

    setState(() {
      _importFailed = clientId == null;
      _importMessage = clientId == null
          ? OAuthRegistry.importRejectionReason(contents)
          : 'Imported. Sign-in is ready.';
      if (clientId != null) {
        _controllers[providerId]?.text = clientId;
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String id, String current) {
    return _controllers.putIfAbsent(
      id,
      () => TextEditingController(text: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final registry = context.read<OAuthRegistry>();
    final native = context.read<NativeBridge>();
    final usage = context.watch<UsageController>();

    final oauthSlots =
        usage.states.where((s) => registry.supports(s.id)).toList();
    if (oauthSlots.isEmpty) return const SizedBox.shrink();

    return SettingsSection(
      title: 'Sign-in setup',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Browser sign-in needs an OAuth client registered with the '
            'provider. Create one as a Desktop app, then import the JSON file '
            'you download — or paste the client ID directly.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: palette.textTertiary,
            ),
          ),
        ),
        if (_importMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _importMessage!,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: _importFailed
                    ? palette.accentCritical
                    : palette.accentPositive,
              ),
            ),
          ),
        for (final slot in oauthSlots)
          SettingsRow(
            label: '${slot.displayName} client ID',
            description: registry.isConfigured(slot.id)
                ? 'Configured.'
                : 'Not set, so Connect is disabled for ${slot.displayName}.',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingsTextField(
                  controller: _controllerFor(
                    slot.id,
                    registry.configFor(slot.id)?.clientId ?? '',
                  ),
                  hintText: 'apps.googleusercontent.com',
                  width: 180,
                  onSubmitted: (value) async {
                    await registry.setClient(slot.id, clientId: value);
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(width: 6),
                PillButton(
                  label: 'Import JSON…',
                  emphasised: !registry.isConfigured(slot.id),
                  onPressed: () => _import(slot.id, registry, native),
                ),
                const SizedBox(width: 6),
                if (OAuthRegistry.registrationUrl(slot.id) case final url?)
                  PillButton(
                    label: 'Get one',
                    onPressed: () => native.openUrl(Uri.parse(url)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
