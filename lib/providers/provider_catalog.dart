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
    connectNote:
        'Opens openrouter.ai so you can create a key. It reports '
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

  /// OpenCode, read from the session store it keeps on this Mac.
  static const ProviderDescriptor openCode = ProviderDescriptor(
    id: 'opencode',
    displayName: 'OpenCode',
    tagline: 'Tokens used by the model OpenCode is on',
    accent: 0xFFEBEBF0,
    authMethod: ProviderAuthMethod.localOnly,
    isImplemented: true,
    connectNote:
        'No sign-in needed. Reads the session record OpenCode already keeps '
        'on this Mac, for whichever model you are currently on.',
  );

  /// Kilo Code. A fork of OpenCode, with the same session store.
  static const ProviderDescriptor kiloCode = ProviderDescriptor(
    id: 'kilocode',
    displayName: 'Kilo Code',
    tagline: 'Tokens used by the model Kilo Code is on',
    accent: 0xFF7C5CFF,
    authMethod: ProviderAuthMethod.localOnly,
    isImplemented: true,
    connectNote:
        'No sign-in needed. Reads the session record Kilo Code already keeps '
        'on this Mac, for whichever model you are currently on.',
  );

  /// Hermes Agent.
  static const ProviderDescriptor hermes = ProviderDescriptor(
    id: 'hermes',
    displayName: 'Hermes',
    tagline: 'Tokens used by the model Hermes is on',
    accent: 0xFFE0A458,
    authMethod: ProviderAuthMethod.localOnly,
    isImplemented: true,
    connectNote:
        'No sign-in needed. Reads the session history Hermes reports through '
        'its own insights command, for the model it is set to.',
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

  /// Every provider this build can measure, in the order the picker offers
  /// them.
  ///
  /// Deliberately longer than [slotCount]. These are not rail positions — the
  /// rail has three, and which providers occupy them is the user's choice,
  /// stored in `AppSettings.slots`. Tying the two together is what made an
  /// empty position carry a provider's identity, so that a plus the user had
  /// not filled still described a provider they had never picked.
  static const List<ProviderDescriptor> available = [
    claude,
    chatgpt,
    openCode,
    kiloCode,
    antigravity,
    hermes,
    openRouter,
  ];

  /// How many positions the rail has.
  ///
  /// A layout number, not a catalogue number: the rail window is sized for
  /// exactly this many rings on the native side. `settings_slots_test.dart`
  /// holds it to `AppSettings.emptySlots`, and `MainFlutterWindow.slotCount`
  /// has to agree.
  static const int slotCount = 3;
}
