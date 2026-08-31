
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import '../../models/app_settings.dart';
import '../../models/rail_placement.dart';
import '../../providers/provider_registry.dart';
import '../../services/native/native_bridge.dart';
import '../../services/settings_service.dart';
import '../../services/shell_controller.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
import '../widgets/provider_glyph.dart';
import '../widgets/settings_controls.dart';
import 'panel_chrome.dart';

/// Preferences, as a sidebar and a page.
///
/// The sidebar lists General, then one row per app, then About. Per-app rather
/// than one long scroll because the questions are genuinely different: how the
/// widget behaves is a question about the widget, while what Claude reads and
/// whether it is on the rail are questions about Claude. Mixing them produced a
/// page where the answer to "why is Gemini empty" sat four sections below a
/// dropdown about screen edges.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  /// Which sidebar row is selected. `null` for General, the About sentinel for
  /// About, otherwise a provider id.
  static const String _general = '__general__';
  static const String _about = '__about__';

  String _page = _general;

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    final usage = context.watch<UsageController>();
    final settingsService = context.watch<SettingsService>();
    final settings = settingsService.settings;

    Future<void> update(AppSettings next) => settingsService.update(next);

    final providers = [
      for (final state in usage.states)
        if (state.descriptor.isImplemented) state,
    ];

    // A page for a provider that has gone away would render nothing at all.
    final selected = _page == _general || _page == _about
        ? _page
        : (providers.any((p) => p.id == _page) ? _page : _general);

    return PanelChrome(
      title: 'Settings',
      onClose: shell.showRail,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 152,
            child: _Sidebar(
              selected: selected,
              providers: providers,
              generalId: _general,
              aboutId: _about,
              onSelect: (id) => setState(() => _page = id),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: switch (selected) {
              _about => const _AboutPage(),
              _general => _GeneralPage(
                  settings: settings,
                  screens: shell.screens,
                  onUpdate: update,
                  onReloadScreens: shell.reloadScreens,
                ),
              final id => _ProviderPage(
                  key: ValueKey(id),
                  providerId: id,
                  settings: settings,
                  onUpdate: update,
                ),
            },
          ),
        ],
      ),
    );
  }
}

/// The list on the left.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.providers,
    required this.generalId,
    required this.aboutId,
    required this.onSelect,
  });

  final String selected;
  final List<ProviderState> providers;
  final String generalId;
  final String aboutId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: palette.surfaceRaised.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          _SidebarRow(
            label: 'General',
            icon: Icons.tune_rounded,
            selected: selected == generalId,
            onTap: () => onSelect(generalId),
          ),
          const SizedBox(height: 10),
          for (final state in providers)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _SidebarRow(
                label: state.displayName,
                providerId: state.id,
                accent: Color(state.descriptor.accent),
                selected: selected == state.id,
                onTap: () => onSelect(state.id),
              ),
            ),
          const Spacer(),
          _SidebarRow(
            label: 'About',
            icon: Icons.info_outline_rounded,
            selected: selected == aboutId,
            onTap: () => onSelect(aboutId),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: PillButton(
              label: 'Quit app',
              onPressed: () => context.read<NativeBridge>().quit(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarRow extends StatefulWidget {
  const _SidebarRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.providerId,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// One of these two is used for the leading mark: an icon for the fixed
  /// rows, the provider's own glyph for an app.
  final IconData? icon;
  final String? providerId;
  final Color? accent;

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = widget.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMetrics.fadeAnimation,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? palette.surfaceRaised
                : (_hovered
                    ? palette.surfaceRaised.withValues(alpha: 0.6)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Center(
                  child: widget.providerId != null
                      ? ProviderGlyph(
                          providerId: widget.providerId!,
                          color: widget.accent ?? palette.textSecondary,
                          size: 13,
                        )
                      : Icon(
                          widget.icon,
                          size: 14,
                          color: active
                              ? palette.textPrimary
                              : palette.textTertiary,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color:
                        active ? palette.textPrimary : palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything that is about the widget rather than about an app.
class _GeneralPage extends StatelessWidget {
  const _GeneralPage({
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
    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        _RailSection(
          settings: settings,
          screens: screens,
          onUpdate: onUpdate,
          onReloadScreens: onReloadScreens,
        ),
        const SizedBox(height: 20),
        _GeneralSection(settings: settings, onUpdate: onUpdate),
        const SizedBox(height: 20),
        _AppearanceSection(settings: settings, onUpdate: onUpdate),
      ],
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
class _ProviderPage extends StatelessWidget {
  const _ProviderPage({
    super.key,
    required this.providerId,
    required this.settings,
    required this.onUpdate,
  });

  final String providerId;
  final AppSettings settings;
  final Future<void> Function(AppSettings) onUpdate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final usage = context.watch<UsageController>();
    final shell = context.read<ShellController>();
    final state = usage.stateFor(providerId);
    final descriptor = state.descriptor;
    final accent = Color(descriptor.accent);
    final slot = usage.slotIndexOf(providerId);
    final provider = context.read<ProviderRegistry>().byId(providerId);

    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                child: ProviderGlyph(
                  providerId: providerId,
                  color: accent,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    descriptor.displayName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.connection.accountLabel ?? state.status.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: palette.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SettingsSection(
          title: 'On the rail',
          children: [
            SettingsRow(
              label: slot == null
                  ? 'Not on the rail'
                  : 'Position ${slot + 1} of ${settings.slots.length}',
              description: slot == null
                  ? 'Add it to show its usage on the edge of your screen.'
                  : 'Remove it to free the position for another app. Your '
                      'account stays connected.',
              control: PillButton(
                label: slot == null ? 'Add to rail' : 'Remove',
                emphasised: slot == null,
                onPressed: () async {
                  if (slot != null) {
                    await usage.clearSlot(slot);
                    return;
                  }
                  final free = settings.emptySlotIndices.firstOrNull;
                  if (free == null) return;
                  await usage.assignSlot(free, providerId);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsSection(
          title: 'Where the figures come from',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                provider?.sourceDescription ?? descriptor.tagline,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: palette.textSecondary,
                ),
              ),
            ),
            if (state.usageUnavailableReason case final reason?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  reason,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: palette.textTertiary,
                  ),
                ),
              ),
          ],
        ),
        if (descriptor.optionalKeyLabel case final keyLabel?) ...[
          const SizedBox(height: 20),
          SettingsSection(
            title: 'Optional key',
            children: [
              SettingsRow(
                label: keyLabel,
                description: 'Adds a separate figure. Not needed for the '
                    'allowance above, which reads a tool already signed in on '
                    'this Mac.',
                control: PillButton(
                  label: 'Set up',
                  onPressed: () => shell.openPanel(
                    ShellSurface.providerDetail,
                    providerId: providerId,
                  ),
                ),
              ),
            ],
          ),
        ],
        // Budgets only mean something where the app measures local token
        // counts against them, which is Claude alone.
        if (providerId == 'claude') ...[
          const SizedBox(height: 20),
          _LocalTrackingSection(settings: settings, onUpdate: onUpdate),
        ],
      ],
    );
  }
}

/// What the app is and what it reads.
class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        Text(
          'Flux',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'A menu-bar monitor for how much of your AI quota you have used.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        SettingsSection(
          title: 'What it reads',
          children: [
            for (final line in const [
              'The session each tool has already established on this Mac — '
                  'Claude Code, Codex, the Antigravity CLI, the Gemini CLI.',
              'Those sessions are used to ask each provider for your own '
                  'usage, and for nothing else. No token is stored, logged, '
                  'or sent anywhere but to the provider it belongs to.',
              'No web page is scraped, no browser cookie is read, and no '
                  'credential file is written to.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '·  $line',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: palette.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
