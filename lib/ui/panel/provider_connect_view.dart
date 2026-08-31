import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/usage_window.dart';
import '../../services/shell_controller.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
import '../widgets/provider_glyph.dart';
import '../widgets/usage_bar.dart';
import 'panel_chrome.dart';

/// Connecting one app, and nothing else.
///
/// This replaced a grid of every provider at once. Reaching it means the user
/// has already said which app they want — from the rail, or from a slot — so
/// showing them the other three is asking a question they have answered, and
/// putting three accounts they did not ask about on screen while they are
/// trying to connect one.
///
/// The whole screen is: this app's mark, its name, and what was found. The
/// look-up starts as soon as the screen opens — there is no credential to
/// enter and nothing to confirm first, so asking the user to press Connect
/// before anything happens only delays the answer they came for. A button
/// appears once there is something to dismiss: Done, when the session was
/// found. When it was not, the reason is the whole answer, and a Connect
/// button that would repeat the same failed look-up is not offered.
class ProviderConnectView extends StatefulWidget {
  const ProviderConnectView({super.key, required this.providerId});

  final String providerId;

  @override
  State<ProviderConnectView> createState() => _ProviderConnectViewState();
}

class _ProviderConnectViewState extends State<ProviderConnectView> {
  bool _working = false;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    // Deferred by one frame: the look-up reads an inherited controller, and
    // notifying listeners during the first build would rebuild mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final usage = context.read<UsageController>();
      if (!usage.stateFor(widget.providerId).connection.isConnected) {
        _connect(usage);
      }
    });
  }

  Future<void> _connect(UsageController usage) async {
    setState(() {
      _working = true;
      _attempted = true;
    });
    await usage.connectLocally(widget.providerId);
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shell = context.watch<ShellController>();
    final usage = context.watch<UsageController>();
    final state = usage.stateFor(widget.providerId);
    final accent = Color(state.descriptor.accent);

    final windows = state.data?.windows ?? const <UsageWindow>[];
    final isConnected = state.connection.isConnected;
    final hasFigures = windows.isNotEmpty;

    return PanelChrome(
      title: 'Connect ${state.displayName}',
      onClose: shell.showRail,
      footer: isConnected
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PillButton(
                  label: 'Done',
                  emphasised: true,
                  onPressed: shell.showRail,
                ),
              ],
            )
          : null,
      child: ListView(
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: ProviderGlyph(
                  providerId: widget.providerId,
                  color: accent,
                  size: 30,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              state.displayName,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              state.descriptor.tagline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: palette.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (_working)
            _Status(
              icon: null,
              text: 'Looking on this Mac for the session '
                  '${state.displayName} already holds…',
            )
          else if (hasFigures) ...[
            _Figures(windows: windows),
            const SizedBox(height: 10),
            _Status(
              icon: Icons.check_circle_rounded,
              tint: palette.accentPositive,
              text: state.connection.accountLabel == null
                  ? 'Connected.'
                  : 'Connected as ${state.connection.accountLabel}.',
            ),
          ] else if (isConnected)
            _Status(
              icon: Icons.info_outline_rounded,
              text: state.usageUnavailableReason ??
                  'Connected, but there is no figure to show yet.',
            )
          else if (_attempted)
            _Status(
              icon: Icons.error_outline_rounded,
              tint: palette.accentCritical,
              text: state.connection.message ??
                  state.usageUnavailableReason ??
                  'Nothing was found on this Mac for ${state.displayName}.',
            )
          else
            _Status(
              icon: Icons.info_outline_rounded,
              text: state.descriptor.connectNote ??
                  'No sign-in needed. This reads the session '
                      '${state.displayName} already holds on this Mac.',
            ),
        ],
      ),
    );
  }
}

/// What was actually found — the point of the screen.
class _Figures extends StatelessWidget {
  const _Figures({required this.windows});

  final List<UsageWindow> windows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < windows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _WindowLine(window: windows[i]),
          ],
        ],
      ),
    );
  }
}

class _WindowLine extends StatelessWidget {
  const _WindowLine({required this.window});

  final UsageWindow window;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fraction = window.fractionUsed;
    final percent = window.percentUsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                window.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Text(
              percent == null ? '—' : '$percent% used',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        UsageBar(
          fraction: fraction,
          color: palette.accentFor(fraction),
          height: 4,
          indeterminate: fraction == null,
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.text, this.icon, this.tint});

  final String text;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 18,
          child: icon == null
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: palette.textTertiary,
                  ),
                )
              : Icon(icon, size: 14, color: tint ?? palette.textTertiary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
