import '../models/provider_connection.dart';
import 'usage_provider.dart';

/// The three provider slots this product ships with.
///
/// Version one is deliberately a fixed set of three rather than an open
/// marketplace: the rail is sized and laid out around exactly three rings, and
/// every slot gets a first-class integration instead of a generic adapter.
///
/// Renaming or re-ordering a slot is a change to this file alone. Nothing in
/// the UI, the controller, or persistence hard-codes a provider identity —
/// they all read [ProviderDescriptor].
abstract final class ProviderCatalog {
  /// Anthropic API usage, with local Claude Code activity where available.
  static const ProviderDescriptor claude = ProviderDescriptor(
    id: 'claude',
    displayName: 'Claude',
    tagline: 'Anthropic API usage and Claude Code activity',
    authMethod: ProviderAuthMethod.consoleApiKey,
    accent: 0xFFD97757,
    isImplemented: true,
  );

  /// OpenAI's Codex CLI.
  static const ProviderDescriptor codex = ProviderDescriptor(
    id: 'codex',
    displayName: 'Codex',
    tagline: 'OpenAI Codex CLI sessions',
    accent: 0xFF10A37F,
    authMethod: ProviderAuthMethod.browserOAuth,
    isImplemented: false,
  );

  /// Google's Antigravity CLI.
  static const ProviderDescriptor antigravity = ProviderDescriptor(
    id: 'antigravity',
    displayName: 'Google Antigravity',
    tagline: 'Google AI model quotas and credits',
    accent: 0xFF4285F4,
    authMethod: ProviderAuthMethod.browserOAuth,
    isImplemented: false,
  );

  /// Slot order, top to bottom in the rail.
  static const List<ProviderDescriptor> slots = [claude, codex, antigravity];

  /// The product's fixed slot count. Asserted by [ProviderRegistry] so a
  /// mismatch is caught at startup rather than by a broken layout.
  static const int slotCount = 3;
}
