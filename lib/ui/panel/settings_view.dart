import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import '../../models/app_settings.dart';
import '../../models/rail_placement.dart';
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
