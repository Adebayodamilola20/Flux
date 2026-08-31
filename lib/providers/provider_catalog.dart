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
  /// Codex, reached through the ChatGPT account it is already signed in as.
  ///
  /// Named for the tool, not the account, because the tool is what is being
  /// measured: the figure on the rail is the **Codex allowance**, which moves
  /// when you run Codex. Chat messages in ChatGPT do not appear here and have
  /// no local record at all.
  ///
  /// The `id` stays `chatgpt`: it is a storage key — for the saved connection,
  /// the Keychain entry, and recorded history — not a label. Changing it would
  /// orphan all three to rename something the user never sees.
  static const ProviderDescriptor chatgpt = ProviderDescriptor(
    id: 'chatgpt',
    displayName: 'Codex',
    tagline: 'Codex allowance on your ChatGPT plan',
    // No credential: Codex has already signed in, and the allowance it recorded
    // needs nothing further. An API key is an optional extra, below.
    authMethod: ProviderAuthMethod.localOnly,
    accent: 0xFF10A37F,
    isImplemented: true,
    credentialHint: 'sk-…',
    optionalKeyLabel: 'Add API key',
    connectNote:
        'Uses the ChatGPT account Codex is already signed in as, and the '
        'allowance OpenAI reported for it. An API key is optional and adds '
        'separate spend reporting — it is not needed for the allowance.',
  );

  /// OpenRouter — the first integration built on an official usage API.
  ///
  /// Its key endpoint returns spend and limit in one call, which makes it the
  /// proof that the generic pipeline can put a real percentage on the rail
  /// without a CLI, a scrape, or an estimate.
  static const ProviderDescriptor openRouter = ProviderDescriptor(
    id: 'openrouter',
    displayName: 'OpenRouter',
    tagline: 'Credits and rate limit from your OpenRouter key',
    authMethod: ProviderAuthMethod.consoleApiKey,
    accent: 0xFF6467F2,
    isImplemented: true,
    connectNote: 'Opens openrouter.ai so you can create a key. It reports '
        'credits used and your limit.',
    credentialHint: 'sk-or-v1-…',
  );

  /// Anthropic API usage, with local Claude Code activity where available.
  static const ProviderDescriptor claude = ProviderDescriptor(
    id: 'claude',
    displayName: 'Claude',
    tagline: 'Claude subscription usage and Claude Code activity',
    authMethod: ProviderAuthMethod.localOnly,
    optionalKeyLabel: 'Add admin key',
    connectNote:
        'Anthropic publishes no sign-in a third-party app can register for, so '
        'this uses the account Claude Code is already signed in as, and the '
        'usage Anthropic reports for it. An Admin API key is optional and adds '
        'organisation API usage.',
    accent: 0xFFD97757,
    isImplemented: true,
  );

  /// Google's Gemini CLI.
  static const ProviderDescriptor gemini = ProviderDescriptor(
    id: 'gemini',
    displayName: 'Gemini',
    tagline: 'Remaining Gemini quota, per model',
    accent: 0xFF9168F0,
    // No sign-in of our own: the CLI's stored session authorises the call.
    authMethod: ProviderAuthMethod.localOnly,
    isImplemented: true,
    connectNote:
        'No sign-in needed. Uses the session Gemini CLI already holds to ask '
        'Google what is left of your quota.',
  );

  /// A slot with no integration behind it.
  ///
  /// Not a product decision about any particular provider — it exists so
  /// [ReservedProvider] has an unimplemented descriptor to stand behind, and so
  /// the tests can exercise how the rail draws a slot that cannot report
  /// anything.
  static const ProviderDescriptor reserved = ProviderDescriptor(
    id: 'reserved',
    displayName: 'Reserved',
    tagline: 'Not available in this version',
    accent: 0xFF8A8A8E,
    authMethod: ProviderAuthMethod.unavailable,
    isImplemented: false,
  );

  /// Google's Antigravity CLI.
  static const ProviderDescriptor antigravity = ProviderDescriptor(
    id: 'antigravity',
    displayName: 'Google Antigravity',
    tagline: 'Weekly model limits from the Antigravity CLI',
    accent: 0xFF4285F4,
    // Reads `agy /usage` rather than asking for a Google sign-in that would
    // carry no quota. If the CLI is here and signed in, the slot works.
    authMethod: ProviderAuthMethod.localOnly,
    isImplemented: true,
    connectNote:
        'No sign-in needed. Uses the session the Antigravity CLI already '
        'holds, and reads the weekly limit from its own usage panel.',
  );

  /// Slot order, top to bottom in the rail.
  static const List<ProviderDescriptor> slots = [
    gemini,
    chatgpt,
    antigravity,
    claude,
  ];

  /// The product's fixed slot count. Asserted by [ProviderRegistry] so a
  /// mismatch is caught at startup rather than by a broken layout.
  static const int slotCount = 4;
}
