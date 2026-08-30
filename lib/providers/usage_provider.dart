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

  /// Fetch current usage.
  ///
  /// Throws [UsageFailure] when usage cannot be determined. Must never return
  /// fabricated numbers — an unmeasurable window is simply omitted.
  Future<UsageData> fetchUsage(AppSettings settings);

  /// Release any long-lived resources. Called on app shutdown.
  Future<void> dispose() async {}
}
