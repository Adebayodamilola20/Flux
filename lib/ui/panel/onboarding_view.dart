import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/connection_status.dart';
import '../../providers/provider_registry.dart';
import '../../services/shell_controller.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
import 'panel_chrome.dart';
import 'provider_connect_card.dart';

/// Connect accounts.
///
/// One card per application. Each opens that provider's own sign-in in the
/// user's browser, and comes back with the account connected — no terminal, no
/// mock sign-in, and no credential typed into this app that the provider did
/// not issue for it.
class OnboardingView extends StatelessWidget {
  const OnboardingView({super.key});

  /// Below this the two-column grid becomes one column rather than squeezing
  /// cards until their buttons wrap.
  static const double _twoColumnMinimum = 640;

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<UsageController>();
    final shell = context.read<ShellController>();
    final registry = context.read<ProviderRegistry>();
    final states = usage.states;

    final connected =
        states.where((s) => s.connection.isConnected).length;

    return PanelChrome(
      title: 'Connect your accounts',
      subtitle: 'Sign in to each service in your browser. AI Usage Monitor '
          'then shows what you have used, on the edge of your screen.',
      footer: _Footer(
        connected: connected,
        total: states.length,
        onDone: shell.finishOnboarding,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= _twoColumnMinimum ? 2 : 1;

          return GridView.count(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            // Tall enough for the connected state, which adds an account line
            // under the name.
            childAspectRatio: columns == 2 ? 1.42 : 2.6,
            physics: const ClampingScrollPhysics(),
            children: [
              for (final state in states)
                ProviderConnectCard(
                  state: state,
                  supportsLocalOnly:
                      registry.byId(state.id)?.supportsLocalOnly ?? false,
                  onConnect: () => usage.connect(state.id),
                  onSubmitCredential: (value) =>
                      usage.completeAuthentication(state.id, value),
                  onUseLocalOnly: () => usage.enableLocalOnly(state.id),
                  onDisconnect: () => usage.disconnect(state.id),
                  onOpenUsage: () => shell.openPanel(
                    ShellSurface.providerDetail,
                    providerId: state.id,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Progress across the four cards, and the way out.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.connected,
    required this.total,
    required this.onDone,
  });

  final int connected;
  final int total;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final none = connected == 0;

    return Row(
      children: [
        _ProgressDots(connected: connected, total: total),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            none
                ? 'Connect at least one account to see usage on the rail.'
                : '$connected of $total connected. You can change this later '
                    'in Settings.',
            style: TextStyle(fontSize: 11.5, color: palette.textTertiary),
          ),
        ),
        PillButton(
          label: none ? 'Skip for now' : 'Done',
          emphasised: !none,
          onPressed: onDone,
        ),
      ],
    );
  }
}

/// One dot per card, filled once that card is connected.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.connected, required this.total});

  final int connected;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: AnimatedContainer(
              duration: AppMetrics.fadeAnimation,
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < connected
                    ? palette.accentPositive
                    : palette.textTertiary.withValues(alpha: 0.3),
              ),
            ),
          ),
      ],
    );
  }
}

/// Colour for a connection state, shared by the cards.
Color statusColorFor(BuildContext context, ConnectionStatus status) {
  final palette = context.palette;
  return switch (status) {
    ConnectionStatus.connected => palette.accentPositive,
    ConnectionStatus.limited => palette.accentPositive,
    ConnectionStatus.connecting => palette.accentWarning,
    ConnectionStatus.error => palette.accentCritical,
    _ => palette.textTertiary,
  };
}
