import 'package:flutter/material.dart';

import '../../models/connection_status.dart';
import '../../models/provider_connection.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
import '../widgets/provider_glyph.dart';
import '../widgets/settings_controls.dart';

/// One provider slot on the connect screen.
///
/// Carries the whole connection flow for that provider: starting it, taking
/// whatever the provider asked the user for, and disconnecting. The card never
/// asks for a password and never renders a provider's sign-in form — the flow
/// always goes out to the user's own browser, and what comes back here is a
/// credential the user chose to create. Claude usage reporting specifically
/// needs an Anthropic Admin API key; it cannot be completed by normal account
/// authorization alone.
class ProviderConnectCard extends StatefulWidget {
  const ProviderConnectCard({
    super.key,
    required this.state,
    required this.supportsLocalOnly,
    required this.onConnect,
    required this.onSubmitCredential,
    required this.onUseLocalOnly,
    required this.onDisconnect,
  });

  final ProviderState state;

  /// Whether this provider can report anything without an account link.
  final bool supportsLocalOnly;

  final Future<ProviderConnection> Function() onConnect;
  final Future<ProviderConnection> Function(String credential)
  onSubmitCredential;
  final Future<ProviderConnection> Function() onUseLocalOnly;
  final Future<void> Function() onDisconnect;

  @override
  State<ProviderConnectCard> createState() => _ProviderConnectCardState();
}

class _ProviderConnectCardState extends State<ProviderConnectCard> {
  final TextEditingController _credential = TextEditingController();
  bool _isWorking = false;

  /// True once the browser has been opened and the card is waiting for the key
  /// the user is creating over there.
  bool _awaitingCredential = false;

  @override
  void dispose() {
    _credential.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ProviderConnection> Function() action) async {
    setState(() => _isWorking = true);
    final result = await action();
    if (!mounted) return;
    setState(() {
      _isWorking = false;
      _awaitingCredential = result.status == ConnectionStatus.connecting;
      if (result.isConnected) _credential.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = widget.state;
    final descriptor = state.descriptor;
    final accent = Color(descriptor.accent);
    final isReserved = state.status == ConnectionStatus.unsupported;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: state.connection.isConnected
              ? accent.withValues(alpha: 0.4)
              : palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isReserved ? 0.08 : 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: ProviderGlyph(
                    providerId: descriptor.id,
                    color: isReserved ? palette.textTertiary : accent,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      descriptor.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isReserved
                            ? palette.textSecondary
                            : palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      state.connection.status.detail,
                      style: TextStyle(
                        fontSize: 11,
                        color: _statusColor(context, state.connection.status),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            descriptor.tagline,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: palette.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          if (_awaitingCredential)
            _buildCredentialStep(context)
          else
            _buildActions(context),
          if (state.connection.message != null && !_awaitingCredential) ...[
            const SizedBox(height: 8),
            Text(
              state.connection.message!,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: state.connection.status == ConnectionStatus.error
                    ? palette.accentCritical
                    : palette.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final palette = context.palette;
    final state = widget.state;
    final method = state.descriptor.authMethod;

    if (state.status == ConnectionStatus.unsupported) {
      return Text(
        method.explanation,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.35,
          color: palette.textTertiary,
        ),
      );
    }

    if (state.connection.isConnected) {
      return Row(
        children: [
          PillButton(
            label: 'Disconnect',
            onPressed: _isWorking
                ? null
                : () async {
                    setState(() => _isWorking = true);
                    await widget.onDisconnect();
                    if (mounted) setState(() => _isWorking = false);
                  },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PillButton(
              label: _isWorking ? 'Opening…' : method.callToAction,
              emphasised: true,
              onPressed: _isWorking ? null : () => _run(widget.onConnect),
            ),
            if (widget.supportsLocalOnly) ...[
              const SizedBox(width: 8),
              PillButton(
                label: 'Local only',
                onPressed: _isWorking
                    ? null
                    : () => _run(widget.onUseLocalOnly),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          method.explanation,
          style: TextStyle(
            fontSize: 10.5,
            height: 1.35,
            color: palette.textTertiary,
          ),
        ),
      ],
    );
  }

  /// Shown after the browser has been opened: a field for the key the user is
  /// creating on the provider's own site.
  Widget _buildCredentialStep(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paste your Anthropic Admin API key',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        SettingsTextField(
          controller: _credential,
          hintText: 'sk-ant-admin…',
          obscure: true,
          width: double.infinity,
          onSubmitted: (value) => _run(() => widget.onSubmitCredential(value)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            PillButton(
              label: _isWorking ? 'Checking…' : 'Save key',
              emphasised: true,
              onPressed: _isWorking
                  ? null
                  : () =>
                        _run(() => widget.onSubmitCredential(_credential.text)),
            ),
            const SizedBox(width: 8),
            PillButton(
              label: 'Cancel',
              onPressed: _isWorking
                  ? null
                  : () => setState(() => _awaitingCredential = false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'The key is stored in your macOS Keychain and never leaves this Mac '
          'except in requests to the provider.',
          style: TextStyle(
            fontSize: 10,
            height: 1.35,
            color: palette.textTertiary,
          ),
        ),
      ],
    );
  }

  Color _statusColor(BuildContext context, ConnectionStatus status) {
    final palette = context.palette;
    return switch (status) {
      ConnectionStatus.connected => palette.accentPositive,
      ConnectionStatus.limited => palette.textSecondary,
      ConnectionStatus.error => palette.accentCritical,
      _ => palette.textTertiary,
    };
  }
}
