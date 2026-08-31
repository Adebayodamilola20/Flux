import 'package:flutter/material.dart';

import '../../models/connection_status.dart';
import '../../models/provider_connection.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_button.dart';
import '../widgets/provider_glyph.dart';
import '../widgets/settings_controls.dart';
import 'onboarding_view.dart' show statusColorFor;

/// One application on the connect screen.
///
/// The whole interaction is: **Connect → the provider's own sign-in in your
/// browser → back here, connected**. This card never renders a sign-in form,
/// never asks for a password, and never presents another app's credentials as
/// its own.
///
/// Nothing here is written for a particular provider. Every string comes from
/// the descriptor or the auth method, because hard-coding one integration's
/// wording here is exactly how OpenRouter ended up telling users to open their
/// Anthropic account.
class ProviderConnectCard extends StatefulWidget {
  const ProviderConnectCard({
    super.key,
    required this.state,
    required this.supportsLocalOnly,
    required this.onConnect,
    required this.onSubmitCredential,
    required this.onUseLocalOnly,
    required this.onDisconnect,
    required this.onOpenUsage,
  });

  final ProviderState state;

  /// Whether this provider can report anything without an account link.
  final bool supportsLocalOnly;

  final Future<ProviderConnection> Function() onConnect;
  final Future<ProviderConnection> Function(String credential)
      onSubmitCredential;
  final Future<ProviderConnection> Function() onUseLocalOnly;
  final Future<void> Function() onDisconnect;

  /// Opens this provider's usage inside the app.
  final VoidCallback onOpenUsage;

  @override
  State<ProviderConnectCard> createState() => _ProviderConnectCardState();
}

class _ProviderConnectCardState extends State<ProviderConnectCard> {
  final TextEditingController _credential = TextEditingController();
  bool _isWorking = false;

  /// True once the browser has been opened and the card is waiting for the key
  /// the user is creating over there.
  bool _awaitingCredential = false;

  bool _hovered = false;

  @override
  void dispose() {
    _credential.dispose();
    super.dispose();
  }

  /// Runs a connect action.
  ///
  /// [expectsCredential] says whether *this action* ends with the user pasting
  /// something. It is a property of the action, not of the provider: a provider
  /// can have both a main path that needs no credential and an optional key,
  /// and only the second should raise a paste box. A browser OAuth flow
  /// completes on the loopback redirect, so a paste box for it is a dead end.
  Future<void> _run(
    Future<ProviderConnection> Function() action, {
    bool expectsCredential = false,
  }) async {
    setState(() => _isWorking = true);
    final result = await action();
    if (!mounted) return;
    setState(() {
      _isWorking = false;
      _awaitingCredential =
          expectsCredential && result.status == ConnectionStatus.connecting;
      if (result.isConnected) _credential.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = widget.state;
    final accent = Color(state.descriptor.accent);
    final isConnected = state.connection.isConnected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMetrics.fadeAnimation,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isConnected
                ? accent.withValues(alpha: 0.45)
                : (_hovered
                    ? palette.textTertiary.withValues(alpha: 0.35)
                    : palette.border),
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: palette.shadow.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CardHeader(state: state, accent: accent),
            const SizedBox(height: 10),
            Text(
              state.descriptor.tagline,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: palette.textTertiary,
              ),
            ),
            const Spacer(),
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
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final state = widget.state;
    final method = state.descriptor.authMethod;

    if (state.status == ConnectionStatus.unsupported) {
      return _Note(state.descriptor.connectNote ?? method.explanation);
    }

    // Connected: the card's job is done, so it offers the thing the user came
    // for — their usage — rather than making Disconnect the prominent action.
    if (state.connection.isConnected) {
      return Row(
        children: [
          PillButton(
            label: 'View usage',
            emphasised: true,
            onPressed: widget.onOpenUsage,
          ),
          const SizedBox(width: 8),
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

    // A provider with no account sign-in gets an explanation, not a button
    // that does nothing when pressed.
    if (method == ProviderAuthMethod.localActivityOnly ||
        method == ProviderAuthMethod.unavailable) {
      return _Note(state.descriptor.connectNote ?? method.explanation);
    }

    // Which action is the *main* one depends on whether this provider needs a
    // credential at all. For one that does not — its own tool is already signed
    // in — putting the key flow on the emphasised button asks the user for
    // something the product does not need, and a paste box is the first thing
    // they see. The key still exists, as a clearly secondary extra.
    final needsNoCredential = method == ProviderAuthMethod.localOnly;
    final optionalKey = state.descriptor.optionalKeyLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PillButton(
              label: _isWorking
                  ? (needsNoCredential ? 'Checking…' : 'Opening…')
                  : method.callToAction,
              emphasised: true,
              onPressed: _isWorking
                  ? null
                  : () => _run(
                        needsNoCredential
                            ? widget.onUseLocalOnly
                            : widget.onConnect,
                        expectsCredential: !needsNoCredential &&
                            method == ProviderAuthMethod.consoleApiKey,
                      ),
            ),
            if (needsNoCredential && optionalKey != null) ...[
              const SizedBox(width: 8),
              PillButton(
                label: optionalKey,
                onPressed: _isWorking
                    ? null
                    : () => _run(widget.onConnect, expectsCredential: true),
              ),
            ] else if (!needsNoCredential && widget.supportsLocalOnly) ...[
              const SizedBox(width: 8),
              PillButton(
                label: 'Enable',
                onPressed:
                    _isWorking ? null : () => _run(widget.onUseLocalOnly),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _Note(state.descriptor.connectNote ?? method.explanation),
      ],
    );
  }

  /// Shown after the browser has been opened, for providers whose flow ends
  /// with a key the user created on the provider's own site.
  Widget _buildCredentialStep(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // When the key is an optional extra rather than the way in, naming
          // the provider here reads as though it were required — and for Codex
          // it would name the wrong thing entirely, since the key is an OpenAI
          // API key rather than a Codex one.
          widget.state.descriptor.optionalKeyLabel != null
              ? 'Paste the key you just created'
              : 'Paste your ${widget.state.displayName} key',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        SettingsTextField(
          controller: _credential,
          hintText: widget.state.descriptor.credentialHint ?? 'Paste your key',
          obscure: true,
          width: double.infinity,
          onSubmitted: (value) => _run(() => widget.onSubmitCredential(value)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            PillButton(
              label: _isWorking ? 'Checking…' : 'Save',
              emphasised: true,
              onPressed: _isWorking
                  ? null
                  : () => _run(
                        () => widget.onSubmitCredential(_credential.text),
                      ),
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
        const _Note(
          'Stored in your macOS Keychain. It never leaves this Mac except in '
          'requests to the provider.',
        ),
      ],
    );
  }
}

/// Logo, name, and the account once there is one.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.state, required this.accent});

  final ProviderState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isReserved = state.status == ConnectionStatus.unsupported;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isReserved ? 0.08 : 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: ProviderGlyph(
              providerId: state.id,
              color: isReserved ? palette.textTertiary : accent,
              size: 17,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.displayName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: isReserved
                      ? palette.textSecondary
                      : palette.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              _StatusLine(state: state),
            ],
          ),
        ),
      ],
    );
  }
}

/// The connection status, with a tick once connected.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});

  final ProviderState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = state.connection.status;
    final color = statusColorFor(context, status);
    final isConnected = state.connection.isConnected;
    final account = state.connection.accountLabel;

    return Row(
      children: [
        if (isConnected) ...[
          Icon(Icons.check_circle_rounded, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            // Once connected, which account it is beats the word "Connected"
            // repeated down every card.
            isConnected && account != null ? account : status.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: isConnected ? color : palette.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        height: 1.35,
        color: context.palette.textTertiary,
      ),
    );
  }
}
