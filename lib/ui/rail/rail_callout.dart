import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../models/connection_status.dart';
import '../../models/provider_connection.dart';
import '../../models/usage_failure.dart';
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
    required this.onRetry,
  });

  final ProviderState state;
  final bool onRightEdge;
  final VoidCallback onConnect;

  /// Re-runs the fetch for this provider.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.of(Brightness.dark),
      child: Builder(
        builder: (context) {
          return CalloutShape(
            fill: const Color(0xFF050506),
            borderColor: const Color(0xFF171719),
            shadowColor: const Color(0xCC000000),
            tailOnRight: onRightEdge,
            radius: 14,
            tailWidth: 12,
            tailHeight: 18,
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
        },
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
      final noSignIn =
          state.descriptor.authMethod == ProviderAuthMethod.localActivityOnly;

      return [
        _Note(
          text: noSignIn
              // Nothing to connect, so do not invite the user to try.
              ? 'No account sign-in is available for ${state.displayName}.'
              : 'Sign in to ${state.displayName} to see your usage.',
          color: palette.textSecondary,
        ),
        if (noSignIn) ...[
          const SizedBox(height: 5),
          _Note(
            text: 'Nothing running right now.',
            color: palette.textTertiary,
          ),
        ],
        if (!noSignIn) ...[
          const SizedBox(height: 9),
          _ConnectButton(
            label: 'Connect ${state.displayName}',
            onTap: onConnect,
          ),
        ],
      ];
    }

    // Connected, but the provider has no quota to give. Not an error: the sign-in
    // worked and there is nothing for the user to fix, so it is stated plainly
    // and local activity is still shown underneath.
    if (state.isUsageUnavailable) {
      return [
        _Note(text: 'Usage unavailable', color: palette.textSecondary),
        if (state.usageUnavailableReason != null) ...[
          const SizedBox(height: 4),
          _Note(
            text: state.usageUnavailableReason!,
            color: palette.textTertiary,
          ),
        ],
        // Retry is offered only where retrying could change the answer. When
        // the record is simply empty, pressing it re-reads the same nothing —
        // so the card points at the panel, which has room for the steps.
        if (state.canRetryUsage) ...[
          const SizedBox(height: 9),
          _ConnectButton(
            label: state.isRefreshing ? 'Checking…' : 'Retry',
            onTap: onRetry,
            enabled: !state.isRefreshing,
          ),
        ] else if (data?.fixItSteps.isNotEmpty ?? false) ...[
          const SizedBox(height: 5),
          _Note(
            text: 'Click for what to do.',
            color: palette.textSecondary,
          ),
        ],
      ];
    }

    final failure = state.failure;
    if (failure != null) {
      // A stale credential is the user's problem to fix, and retrying will not
      // fix it — so that case gets Reconnect, everything else gets Retry.
      final needsReauth = failure.kind == UsageFailureKind.authentication;

      return [
        _Note(
          text: needsReauth ? 'Authentication required' : 'Usage unavailable',
          color: palette.accentCritical,
        ),
        const SizedBox(height: 4),
        // The reason, always. "Unavailable" on its own tells the user nothing
        // about whether to wait, retry, or go and sign in again.
        _Note(text: failure.message, color: palette.textSecondary),
        if (failure.hint != null) ...[
          const SizedBox(height: 3),
          _Note(text: failure.hint!, color: palette.textTertiary),
        ],
        if (state.lastUpdated != null) ...[
          const SizedBox(height: 5),
          _Note(
            text: 'Last update ${Format.relativeTime(state.lastUpdated!)}',
            color: palette.textTertiary,
          ),
        ],
        const SizedBox(height: 9),
        _ConnectButton(
          label: needsReauth
              ? 'Reconnect ${state.displayName}'
              : (state.isRefreshing ? 'Retrying…' : 'Retry'),
          onTap: needsReauth ? onConnect : onRetry,
          enabled: !state.isRefreshing,
        ),
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
        if (!state.isRefreshing) ...[
          const SizedBox(height: 9),
          _ConnectButton(label: 'Retry', onTap: onRetry),
        ],
      ];
    }

    return [
      for (final window in data.windows) ...[
        _WindowRow(window: window, isReaching: state.isReaching),
        if (window != data.windows.last) const SizedBox(height: 9),
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
  const _WindowRow({required this.window, this.isReaching = false});

  final UsageWindow window;

  /// The provider could not be reached, so this figure is the previous one.
  final bool isReaching;

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
          indeterminate: fraction == null || isReaching,
        ),
        const SizedBox(height: 4),
        Text(
          // A window with no published limit reports a total, not a share of
          // one — inventing a denominator would be a lie.
          [
            // Says the figure is being fetched rather than presenting the last
            // one as current. The rail showed 26% while Claude's own menu bar
            // showed 31%, with nothing on screen to say which was live.
            if (isReaching)
              'Connecting…'
            else
              percent == null
                  ? '${Format.compactNumber(window.consumed)} ${window.unit}'
                  : '$percent% Used',
            // When the provider measured it, if that is not now. A figure that
            // cannot be asked for on demand — OpenAI reports the Codex
            // allowance only in the reply to a prompt — can be days old, and
            // "100% Used" with no date reads as current.
            if (window.isStale)
              'as of ${Format.relativeTime(window.observedAt!)}',
          ].join(' · '),
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
  const _ConnectButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final enabled = widget.enabled;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = enabled),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
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
              color: !enabled
                  ? palette.textTertiary
                  : (_hovered ? palette.surface : palette.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
