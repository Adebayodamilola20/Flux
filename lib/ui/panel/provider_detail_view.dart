import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import '../../models/connection_status.dart';
import '../../models/usage_window.dart';
import '../../services/history_service.dart';
import '../../services/shell_controller.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
import '../widgets/provider_glyph.dart';
import '../widgets/usage_bar.dart';
import 'panel_chrome.dart';

/// One provider in full: every window, its sessions, and its recent history.
///
/// Reached by clicking a provider in the rail. Everything here is also visible
/// somewhere in the rail — this surface exists to give it room, not to hide
/// anything behind a click.
class ProviderDetailView extends StatelessWidget {
  const ProviderDetailView({super.key, required this.providerId});

  final String providerId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final usage = context.watch<UsageController>();
    final shell = context.read<ShellController>();
    final history = context.read<HistoryService>();
    final state = usage.stateFor(providerId);
    final data = state.data;

    return PanelChrome(
      title: state.displayName,
      subtitle: state.connection.status.detail,
      onClose: shell.showRail,
      onBack: shell.showRail,
      footer: Row(
        children: [
          Expanded(
            child: Text(
              state.lastUpdated == null
                  ? 'Never updated'
                  : 'Updated ${Format.relativeTime(state.lastUpdated!)}',
              style: TextStyle(fontSize: 11, color: palette.textTertiary),
            ),
          ),
          // An unconnected slot gets one action, and it is the only one that
          // does anything: Refresh would just fail again, and Disconnect has
          // nothing to disconnect. Offering them here was a dead end — the
          // panel said "not connected" and gave no way to fix it.
          if (!state.connection.isConnected)
            PillButton(
              label: 'Connect ${state.displayName}',
              emphasised: true,
              onPressed: state.status == ConnectionStatus.unsupported
                  ? null
                  : () => shell.openPanel(
                        ShellSurface.connectProvider,
                        providerId: providerId,
                      ),
            )
          else ...[
            PillButton(
              label: state.isRefreshing ? 'Refreshing…' : 'Refresh',
              emphasised: true,
              onPressed:
                  state.isRefreshing ? null : () => usage.refresh(providerId, manual: true),
            ),
            const SizedBox(width: 8),
            // Two different requests, so two different actions. Taking a
            // provider off the rail is about what you want on screen;
            // disconnecting is about forgetting the account. Collapsing them
            // into one button would make clearing a slot look destructive.
            if (usage.slotIndexOf(providerId) case final slot?)
              PillButton(
                label: 'Remove from rail',
                onPressed: () async {
                  await usage.clearSlot(slot);
                  await shell.showRail();
                },
              ),
            const SizedBox(width: 8),
            PillButton(
              label: 'Disconnect',
              onPressed: () => usage.disconnect(providerId),
            ),
          ],
        ],
      ),
      child: ListView(
        children: [
          Row(
            children: [
              ProviderGlyph(
                providerId: state.id,
                color: Color(state.descriptor.accent),
                size: 15,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.descriptor.tagline,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // "Not connected" is a starting point, not a fault, so it is
          // explained rather than shown in a red error box.
          if (!state.connection.isConnected &&
              state.status != ConnectionStatus.unsupported)
            _NotConnectedBlock(state: state)
          else if (state.failure != null)
            _FailureBlock(
              message: state.failure!.message,
              hint: state.failure!.hint,
            )
          // Connected, nothing to show, and nothing broken. This is where a
          // user ends up after adding a tool they have not used yet, so it has
          // to answer "what do I do" rather than restate the problem.
          else if (data != null && data.isUsageUnavailable)
            _NothingToShowBlock(
              reason: data.usageUnavailableReason!,
              steps: data.fixItSteps,
            )
          else if (data == null || data.windows.isEmpty)
            Text(
              'No usage has been recorded for this provider yet.',
              style: TextStyle(fontSize: 12, color: palette.textTertiary),
            )
          else ...[
            for (final window in data.windows) ...[
              _WindowDetail(
                window: window,
                history: history,
                providerId: providerId,
              ),
              const SizedBox(height: 18),
            ],
          ],
          if (data != null && data.notes.isNotEmpty)
            for (final note in data.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  note,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: palette.textTertiary,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _WindowDetail extends StatelessWidget {
  const _WindowDetail({
    required this.window,
    required this.history,
    required this.providerId,
  });

  final UsageWindow window;
  final HistoryService history;
  final String providerId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fraction = window.fractionUsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                window.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Text(
              window.percentUsed == null
                  ? Format.compactNumber(window.consumed)
                  : '${window.percentUsed}%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        UsageBar(
          fraction: fraction,
          color: palette.accentFor(fraction),
          height: 6,
          indeterminate: fraction == null,
        ),
        const SizedBox(height: 6),
        Text(
          [
            Format.consumption(window.consumed, window.limit, window.unit),
            if (window.resetsAt != null)
              'Resets ${Format.resetTime(window.resetsAt!)}',
            if (window.isStale)
              'measured ${Format.relativeTime(window.observedAt!)}',
            window.source.label,
          ].join(' · '),
          style: TextStyle(fontSize: 10.5, color: palette.textTertiary),
        ),
        // What was actually spent, where the app knows it.
        //
        // This replaced a sparkline of recent readings. Over a percentage that
        // barely moves the chart was a flat line saying nothing, and it took
        // the space that the one genuinely useful extra figure wanted: how
        // many tokens went into reaching that percentage.
        if (window.tokensUsed case final tokens?) ...[
          const SizedBox(height: 5),
          Text(
            '${Format.compactNumber(tokens)} tokens used on this Mac',
            style: TextStyle(fontSize: 10.5, color: palette.textTertiary),
          ),
        ],
      ],
    );
  }
}

class _FailureBlock extends StatelessWidget {
  const _FailureBlock({required this.message, this.hint});

  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.accentCritical.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.accentCritical.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(fontSize: 12, color: palette.accentCritical),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NothingToShowBlock extends StatelessWidget {
  const _NothingToShowBlock({required this.reason, required this.steps});

  final String reason;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.textTertiary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nothing to show yet',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            reason,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: palette.textSecondary,
            ),
          ),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              'WHAT TO DO',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: palette.textTertiary,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 16,
                      child: Text(
                        '${i + 1}.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: palette.textTertiary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _NotConnectedBlock extends StatelessWidget {
  const _NotConnectedBlock({required this.state});

  final ProviderState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final method = state.descriptor.authMethod;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Not connected yet',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            method.explanation,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _scopeNote(state.id),
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: palette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  /// What the resulting numbers will actually cover.
  static String _scopeNote(String providerId) => switch (providerId) {
        'claude' =>
          'Connecting reports Anthropic API usage for your account. Anthropic '
              'publishes no API for Claude or Claude Code plan limits, so those '
              'are not shown here. Claude Code sessions running on this Mac are '
              'still detected without connecting — they appear as activity, not '
              'as usage.',
        'opencode' || 'kilocode' =>
          'Adding this reads the session record the tool already keeps on this '
              'Mac, for whichever model you are currently on. Switch models '
              'and the figure follows you to the new one.',
        'hermes' =>
          'Adding this runs Hermes’s own insights report and reads the totals '
              'for the model it is set to.',
        'antigravity' =>
          'Connecting uses the session your Antigravity CLI already holds and '
              'reads the quota panel it draws for that account.',
        _ => 'Connecting lets this provider report usage for your account.',
      };
}
