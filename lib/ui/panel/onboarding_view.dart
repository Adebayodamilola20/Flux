import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/provider_registry.dart';
import '../../services/shell_controller.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
import 'panel_chrome.dart';
import 'provider_connect_card.dart';

/// First run: connect the three provider slots.
///
/// Shown once, then replaced by the rail. The user can leave without connecting
/// everything — two of the three slots have no integration in this build, and
/// blocking on them would be a wall in front of a working product.
class OnboardingView extends StatelessWidget {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final usage = context.watch<UsageController>();
    final shell = context.read<ShellController>();
    final registry = context.read<ProviderRegistry>();
    final states = usage.states;

    return PanelChrome(
      title: 'Connect your AI tools',
      subtitle:
          'AI Usage Monitor tracks how much of each tool you have used '
          'and shows it on the edge of your screen.',
      footer: Row(
        children: [
          Expanded(
            child: Text(
              usage.hasAnyConnection
                  ? 'You can change any of this later in Settings.'
                  : 'Connect at least one tool to see usage on the rail.',
              style: TextStyle(fontSize: 11, color: palette.textTertiary),
            ),
          ),
          PillButton(
            label: usage.hasAnyConnection ? 'Done' : 'Skip for now',
            emphasised: usage.hasAnyConnection,
            onPressed: shell.finishOnboarding,
          ),
        ],
      ),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.55,
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
            ),
        ],
      ),
    );
  }
}
