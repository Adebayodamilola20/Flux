import '../models/active_session.dart';
import '../models/app_settings.dart';
import '../models/provider_connection.dart';
import '../models/usage_data.dart';

/// Everything the UI needs to render a provider before any data arrives.
///
/// Kept separate from the provider implementation so the onboarding screen can
/// draw all three slots without instantiating or contacting anything.
class ProviderDescriptor {
  const ProviderDescriptor({
    required this.id,
    required this.displayName,
    required this.tagline,
    required this.authMethod,
    required this.accent,
    this.isImplemented = true,
    this.connectNote,
    this.credentialHint,
    this.optionalKeyLabel,
  });

  /// Stable machine key, used for persistence and snapshot grouping.
  final String id;

  /// Display name shown in the UI ("Claude").
  final String displayName;

  /// One line describing what this provider covers.
  final String tagline;

  final ProviderAuthMethod authMethod;

  /// Brand accent as a 0xAARRGGBB value. Kept as an int so this file stays
  /// free of Flutter imports and remains testable without a binding.
  final int accent;

  /// False for reserved slots that ship without an implementation. The slot is
  /// still shown, so the product's shape is honest about what is coming.
  final bool isImplemented;

  /// Shape of the credential this provider issues, e.g. `sk-or-v1-…`.
  ///
  /// Shown in the paste field so the user can tell at a glance whether they
  /// copied the right thing.
  final String? credentialHint;

  /// Label for an *additional*, optional credential this provider can also use,
  /// e.g. `Add API key`.
  ///
  /// Only meaningful for a provider whose main connection needs no credential
  /// at all. Such a provider may still have a key that unlocks a second,
  /// different figure — Codex reports the plan allowance with no key, and API
  /// spend with one. Naming that separately is what keeps the key out of the
  /// main path: a user who does not have one is never shown a paste box, and a
  /// user who does is not told it is required.
  ///
  /// Null when there is no such extra.
  final String? optionalKeyLabel;

  /// A caveat specific to this provider, shown under the connect action.
  ///
  /// Exists so provider-specific wording lives with the provider instead of
  /// leaking into the shared enum, where it would be shown against every
  /// integration that happens to use the same auth method.
  final String? connectNote;
}

/// Opens a URL in the user's default browser.
///
/// Injected rather than imported so the connect flow can be tested without
/// launching anything.
typedef UrlLauncher = Future<bool> Function(Uri url);

/// Contract every AI provider implements.
///
/// Adding a provider means writing one class against this interface and
/// registering it — no UI, controller, or persistence change is required.
///
/// Implementations must:
///  * never block the UI isolate on heavy I/O,
///  * throw [UsageFailure] (not raw exceptions) for expected error paths,
///  * label every [UsageWindow] with an honest [UsageSource],
///  * never fabricate a number when the real one is unavailable.
abstract class UsageProvider {
  /// Static description of this provider.
  ProviderDescriptor get descriptor;

  String get id => descriptor.id;
  String get displayName => descriptor.displayName;

  /// Short description of where this provider's numbers come from, shown in
  /// Settings so the user can judge how much to trust them.
  String get sourceDescription;

  /// The current account-link state. Reflects what [restore] loaded and what
  /// [connect]/[disconnect] have since done.
  ProviderConnection get connection;

  /// Loads any previously stored connection. Called once at startup, before
  /// the first fetch.
  Future<void> restore();

  /// Cheap check for whether this provider can produce anything at all on this
  /// machine right now. Used to decide between "not connected" and "error".
  Future<bool> isAvailable();

  /// True when this provider can report something useful with no account link
  /// at all, from artifacts already on this Mac.
  ///
  /// The connect screen offers such providers a second, lesser option so the
  /// user is never forced to hand over a credential to get any value — and so
  /// the resulting figures are labelled [ConnectionStatus.limited] rather than
  /// passed off as provider-reported.
  bool get supportsLocalOnly => false;

  /// Adopts local-only mode without an account link. Only meaningful when
  /// [supportsLocalOnly] is true.
  Future<ProviderConnection> enableLocalOnly() async => connection;

  /// Begins authentication.
  ///
  /// Implementations open the provider's own page via [launchUrl] and return
  /// the resulting state. They must never present a password field, read
  /// browser cookies, or reuse credentials the user did not deliberately give
  /// this app.
  ///
  /// Returns the connection state to adopt. A provider whose flow finishes in
  /// the browser returns [ConnectionStatus.connecting] and completes later via
  /// [completeAuthentication].
  Future<ProviderConnection> connect({required UrlLauncher launchUrl});

  /// Finishes a browser-based flow from a URL-scheme callback, or accepts the
  /// credential the user pasted from the provider's console.
  ///
  /// [payload] is whatever the flow produced — an authorisation code from a
  /// deep link, or an API key. Returns the resulting connection state.
  Future<ProviderConnection> completeAuthentication(String payload);

  /// Forgets this provider's credentials, removing them from the Keychain.
  Future<void> disconnect();

  /// Locally observable sessions for this provider.
  ///
  /// Deliberately separate from [fetchUsage] and from any notion of being
  /// connected. Whether a tool is running on this Mac is an observation about
  /// this Mac; it is not a claim about an account, it needs no credential, and
  /// it must keep working for a provider the user has never signed in to.
  Future<List<ActiveSession>> detectActivity() async => const [];

  /// Fires when this provider's underlying data changes.
  ///
  /// For providers whose figures come from a local file the provider's own app
  /// rewrites, this is what keeps the rail current: the alternative is polling
  /// on a timer and showing a number that is up to a refresh interval old.
  /// Null when a provider has nothing to watch.
  Stream<void>? get changes => null;

  /// How often this provider wants to be polled, when that differs from the
  /// interval the user chose.
  ///
  /// The global setting is a ceiling for providers whose figures cost a real
  /// network round trip and barely move. A provider reading a number that
  /// changes with every prompt — and reading it cheaply — should not be held to
  /// it, because a five-minute-old percentage is wrong for most of those five
  /// minutes. Honoured as a floor, never as a way to poll less often than the
  /// user asked for.
  ///
  /// Null means "use the user's interval".
  Duration? get preferredRefreshInterval => null;

  /// Discards anything this provider is holding on to that a user pressing
  /// Refresh would expect to be reconsidered.
  ///
  /// Providers cache to avoid repeating expensive or intrusive work — a
  /// Keychain read that raises a system dialog, a CLI session that takes half a
  /// minute to run. That caching is right on a timer and wrong when the user
  /// has just fixed something and is asking again, so a deliberate refresh says
  /// so and a scheduled one does not.
  void invalidateCaches() {}

  /// Fetch current usage.
  ///
  /// Throws [UsageFailure] when usage cannot be determined. Must never return
  /// fabricated numbers — an unmeasurable window is simply omitted.
  Future<UsageData> fetchUsage(AppSettings settings);

  /// Release any long-lived resources. Called on app shutdown.
  Future<void> dispose() async {}
}
