import 'package:flutter/widgets.dart';

import '../../core/formatting.dart';
import '../../models/active_session.dart';
import '../../models/connection_status.dart';
import '../../models/usage_window.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/provider_glyph.dart';
import '../widgets/usage_bar.dart';
import 'rail_shapes.dart';

/// The card that appears beside the ring the pointer is on.
///
/// One provider only. The rings already answer "how am I doing across
/// everything"; this answers "what exactly is going on with *this* one", and
/// its tail says which one it means.
class RailCallout extends StatelessWidget {
  const RailCallout({
    super.key,
    required this.state,
    required this.onRightEdge,
    required this.onConnect,
  });

  final ProviderState state;
  final bool onRightEdge;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CalloutShape(
      fill: palette.surface,
      borderColor: palette.border,
      shadowColor: palette.shadow,
      tailOnRight: onRightEdge,
      child: SizedBox(
        width: AppMetrics.calloutWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(state: state),
              const SizedBox(height: 9),
              ..._buildBody(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    final palette = context.palette;
    final data = state.data;

    if (state.status == ConnectionStatus.unsupported) {
      return [
        _Note(
          text: '${state.displayName} is not available in this version.',
          color: palette.textTertiary,
        ),
      ];
    }

    if (!state.connection.isConnected) {
      return [
        _Note(
          text: 'Sign in to ${state.displayName} to see your usage.',
          color: palette.textSecondary,
        ),
        const SizedBox(height: 9),
        _ConnectButton(label: 'Connect ${state.displayName}', onTap: onConnect),
      ];
    }

    if (state.failure != null) {
      return [
        _Note(text: state.failure!.message, color: palette.accentCritical),
        if (state.lastUpdated != null) ...[
          const SizedBox(height: 5),
          _Note(
            text: 'Last update ${Format.relativeTime(state.lastUpdated!)}',
            color: palette.textTertiary,
          ),
        ],
      ];
    }

    if (data == null || data.windows.isEmpty) {
      return [
        _Note(
          text: state.isRefreshing
              ? 'Checking usage…'
              : 'No usage reported yet.',
          color: palette.textTertiary,
        ),
      ];
    }

    return [
      for (final window in data.windows) ...[
        _WindowRow(window: window),
        if (window != data.windows.last) const SizedBox(height: 9),
      ],
      if (data.sessions.isNotEmpty) ...[
        const SizedBox(height: 9),
        Container(height: 1, color: palette.divider),
        const SizedBox(height: 8),
        _SessionRow(session: data.sessions.first),
      ],
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final ProviderState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        ProviderGlyph(
          providerId: state.id,
          color: palette.textPrimary,
          size: 12,
        ),
        const SizedBox(width: 6),
        Text(
          '${state.displayName} Usage',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// One quota window, laid out as in the reference: label and reset time on one
/// line, the bar beneath it, then the percentage.
class _WindowRow extends StatelessWidget {
  const _WindowRow({required this.window});

  final UsageWindow window;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fraction = window.fractionUsed;
    final percent = window.percentUsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                window.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            if (window.resetsAt != null)
              Text(
                'Resets ${Format.resetTime(window.resetsAt!)}',
                style: TextStyle(fontSize: 9.5, color: palette.textTertiary),
              ),
          ],
        ),
        const SizedBox(height: 4),
        UsageBar(
          fraction: fraction,
          color: palette.accentFor(fraction),
          height: 3,
          indeterminate: fraction == null,
        ),
        const SizedBox(height: 4),
        Text(
          // A window with no published limit reports a total, not a share of
          // one — inventing a denominator would be a lie.
          percent == null
              ? '${Format.compactNumber(window.consumed)} ${window.unit}'
              : '$percent% Used',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final ActiveSession session;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                session.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Text(
              session.isBusy ? 'working' : 'idle',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: session.isBusy
                    ? palette.accentPositive
                    : palette.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Row(
          children: [
            Expanded(
              child: Text(
                session.subtitle(session.title),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9.5, color: palette.textTertiary),
              ),
            ),
            if (session.lastActivity != null)
              Text(
                Format.relativeTime(session.lastActivity!),
                style: TextStyle(fontSize: 9.5, color: palette.textTertiary),
              ),
          ],
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 10.5, height: 1.35, color: color),
    );
  }
}

class _ConnectButton extends StatefulWidget {
  const _ConnectButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMetrics.fadeAnimation,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? palette.textPrimary : palette.surfaceRaised,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: palette.border),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: _hovered ? palette.surface : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
