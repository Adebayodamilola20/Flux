import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import '../../models/app_settings.dart';
import '../../models/rail_placement.dart';
import '../../providers/provider_registry.dart';
import '../../services/update_checker.dart';
import '../../services/native/native_bridge.dart';
import '../../services/settings_service.dart';
import '../../services/shell_controller.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import 'update_section.dart';
import '../widgets/app_mark.dart';
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
            width: 176,
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? palette.accentSystem
                : (_hovered
                      ? palette.surfaceRaised.withValues(alpha: 0.8)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Center(
                  child: widget.providerId != null
                      ? ProviderGlyph(
                          providerId: widget.providerId!,
                          // A selected row is filled with system blue, so the
                          // mark on it has to be white or it disappears.
                          color: active
                              ? Colors.white
                              : (widget.accent ?? palette.textSecondary),
                          size: 14,
                        )
                      : Icon(
                          widget.icon,
                          size: 15,
                          color: active ? Colors.white : palette.textTertiary,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: -0.1,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? Colors.white : palette.textPrimary,
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
      footnote: settings.railAppearance.description,
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
        SettingsRow(
          label: 'Rail surface',
          control: SettingsSegmented<RailAppearance>(
            value: settings.railAppearance,
            items: RailAppearance.values,
            labelBuilder: (a) => a.label,
            onChanged: (v) => onUpdate(settings.copyWith(railAppearance: v)),
          ),
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
            if (slot != null)
              SettingsRow(
                label: 'Position ${slot + 1} of ${settings.slots.length}',
                description:
                    'Remove it to free the position for another app. '
                    'Your account stays connected.',
                control: PillButton(
                  label: 'Remove',
                  onPressed: () => usage.clearSlot(slot),
                ),
              )
            // The rail holds a fixed number of positions, and every one of
            // them is taken. Adding used to be offered anyway and then do
            // nothing at all when there was nowhere to put it — a button that
            // looks live, is pressed, and leaves the user with no idea why.
            else if (settings.emptySlotIndices.isEmpty)
              SettingsRow(
                label:
                    'Rail is full — '
                    '${settings.slots.length} of ${settings.slots.length}',
                description:
                    'Pick one to swap out, or remove one first. '
                    'Whatever you swap out stays connected.',
                control: _SwapIntoRailButton(providerId: providerId),
              )
            else
              SettingsRow(
                label: 'Not on the rail',
                description:
                    'Add it to show its usage on the edge of your '
                    'screen.',
                control: PillButton(
                  label: 'Add to rail',
                  emphasised: true,
                  onPressed: () async {
                    final free = settings.emptySlotIndices.first;
                    await usage.assignSlot(free, providerId);
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsSection(
          title: 'Connection',
          footnote: provider?.sourceDescription ?? descriptor.tagline,
          trailing: SettingsBadge(
            label: state.connection.isConnected ? 'Active' : 'Off',
            color: state.connection.isConnected
                ? palette.accentPositive
                : palette.textTertiary,
          ),
          children: [
            SettingsRow(
              label: state.connection.isConnected
                  ? 'Connected via ${descriptor.displayName}'
                  : 'Not connected',
              description: state.connection.accountLabel,
              control: PillButton(
                label: state.connection.isConnected ? 'Refresh' : 'Connect',
                onPressed: () => state.connection.isConnected
                    ? usage.refresh(providerId, manual: true)
                    : shell.openPanel(
                        ShellSurface.connectProvider,
                        providerId: providerId,
                      ),
              ),
            ),
            if (state.usageUnavailableReason case final reason?)
              SettingsRow(label: 'Why there is no figure', description: reason),
          ],
        ),
        if (descriptor.optionalKeyLabel case final keyLabel?) ...[
          const SizedBox(height: 20),
          SettingsSection(
            title: 'Optional key',
            children: [
              SettingsRow(
                label: keyLabel,
                description:
                    'Adds a separate figure. Not needed for the '
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
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const AppMark(size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'DevNotch',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A menu-bar monitor for how much of your AI quota you '
                    'have used.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const UpdateSection(version: UpdateChecker.compiledVersion),
        const SizedBox(height: 20),
        SettingsSection(
          title: 'What it reads',
          children: [
            for (final line in const [
              'The session record each tool already keeps on this Mac — '
                  'Claude Code, Codex, OpenCode, Kilo Code, the Antigravity '
                  'CLI, Hermes.',
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
        const SizedBox(height: 20),
        const _ResetSection(),
      ],
    );
  }
}

/// The way back to a new install.
///
/// macOS keeps an app's preferences in the user's Library, not in the app, so
/// deleting DevNotch and downloading it again brings back the same slots and
/// skips the intro — which looks like a fresh copy that arrived already set
/// up. This is the honest way to start over, and it takes two presses because
/// it cannot be undone.
class _ResetSection extends StatefulWidget {
  const _ResetSection();

  @override
  State<_ResetSection> createState() => _ResetSectionState();
}

class _ResetSectionState extends State<_ResetSection> {
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Start over',
      footnote: _armed
          ? 'This cannot be undone.'
          : 'Deleting the app does not remove its settings. This does.',
      children: [
        SettingsRow(
          label: 'Reset DevNotch',
          description:
              'Clears your slots, connections and history, and shows the '
              'intro screen again, exactly as on a new Mac.',
          control: PillButton(
            label: _armed ? 'Tap again to reset' : 'Reset…',
            onPressed: () {
              if (!_armed) {
                setState(() => _armed = true);
                return;
              }
              unawaited(context.read<ShellController>().resetEverything());
            },
          ),
        ),
      ],
    );
  }
}

/// Offered when every rail position is taken.
///
/// The rail is a fixed number of positions by design, so "add" has to become
/// "swap" once they are all used. Naming what is currently there — and its
/// position — is the part that matters: the user picks what to give up rather
/// than being told to go and clear a slot somewhere else first.
class _SwapIntoRailButton extends StatelessWidget {
  const _SwapIntoRailButton({required this.providerId});

  /// The provider that wants a position.
  final String providerId;

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<UsageController>();
    final palette = context.palette;
    final occupants = usage.slots;

    return PillButton(
      label: 'Swap in…',
      emphasised: true,
      onPressed: () async {
        final box = context.findRenderObject() as RenderBox?;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (box == null || overlay == null) return;

        final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
        final chosen = await showMenu<int>(
          context: context,
          color: palette.surfaceRaised,
          position: RelativeRect.fromLTRB(
            origin.dx,
            origin.dy + box.size.height + 4,
            overlay.size.width - origin.dx - box.size.width,
            0,
          ),
          items: [
            for (var i = 0; i < occupants.length; i++)
              if (occupants[i] case final occupant?)
                PopupMenuItem<int>(
                  value: i,
                  height: 36,
                  child: Text(
                    'Replace ${occupant.displayName} '
                    '(position ${i + 1})',
                    style: TextStyle(fontSize: 12, color: palette.textPrimary),
                  ),
                ),
          ],
        );

        if (chosen == null) return;
        // Assigning over an occupied position replaces what is there. The
        // provider that leaves keeps its connection — only its place on the
        // rail is given up.
        await usage.assignSlot(chosen, providerId);
      },
    );
  }
}
