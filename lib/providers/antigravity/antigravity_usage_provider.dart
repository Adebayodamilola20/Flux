import '../../core/logger.dart';
import '../../models/app_settings.dart';
import '../cli/cli_usage_provider.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';
import 'antigravity_local_server.dart';

/// Google Antigravity, read from the CLI that is already signed in.
///
/// **There is no sign-in step, deliberately.** This slot used to ask the user
/// to authorise Google in the browser. That was work for nothing: the token it
/// produced could name the account and carried no quota, because Antigravity
/// publishes no account quota API and caches nothing to disk. Meanwhile `agy`
/// is sitting on the same machine, already signed in, and will show the weekly
/// limit on request. So the account link is gone and the CLI is the source.
///
/// The figure comes from driving `agy` under a pseudo-terminal, typing
/// `/usage`, and reading the panel it drew — per model group, as Antigravity
/// reports it: Gemini models, and Claude and GPT models. The CLI authenticates
/// itself exactly as it would for a user at a terminal; this app never sees its
/// credentials.
///
/// These are labelled `UsageSource.interactiveCli`, because a rendered panel is
/// not an API contract and a layout change can make it unreadable.
class AntigravityUsageProvider extends CliUsageProvider {
  AntigravityUsageProvider({
    required super.native,
    required super.connectionStore,
    super.source,
    AntigravityLocalServer? server,
    Logger? logger,
  })  : _server = server ?? AntigravityLocalServer(),
        super(logger: logger ?? const Logger('antigravity'));

  /// Antigravity's own language server, asked first.
  final AntigravityLocalServer _server;

  /// Reads the quota, preferring the running server to driving the CLI.
  ///
  /// **Why the server comes first.** Both answer the same question, but one
  /// takes milliseconds and the other takes the better part of a minute and
  /// starts a real process. The consequence was not just slowness: because a
  /// CLI launch can open a browser, it could only ever be done when the user
  /// explicitly asked, so the figure on the rail was usually hours old and
  /// disagreed with what `/usage` showed. When Antigravity is running there is
  /// no reason to pay that cost at all.
  ///
  /// **The CLI is still the fallback**, for the case the server cannot cover:
  /// Antigravity closed. Then the last panel that was read still stands, and
  /// the user can still ask for a fresh one.
  @override
  Future<CliUsageReading> readUsage(AppSettings settings) async {
    final live = await _server.read();
    if (live != null && live.hasUsage) {
      return CliUsageReading(windows: live.windows);
    }
    return super.readUsage(settings);
  }

  @override
  ProviderDescriptor get descriptor => ProviderCatalog.antigravity;

  @override
  String get executable => 'agy';

  @override
  String get usageCommand => '/usage';

  @override
  String get activityLabel => 'Antigravity CLI';

  /// `agy` writes a log per session here. A new entry means the weekly limit
  /// has moved, so the cached panel is re-read rather than held until its TTL
  /// happens to expire.
  @override
  String get activityDirectory => '.gemini/antigravity-cli/log';

  /// What `agy` rewrites when the signed-in Google account changes: the
  /// account list and its OAuth grant, shared with the Gemini CLI, and its own
  /// state file. Any of them moving means the figure is about someone else.
  @override
  List<String> get credentialFiles => const [
        '.gemini/google_accounts.json',
        '.gemini/oauth_creds.json',
        '.gemini/antigravity-cli/jetski_state.pbtxt',
      ];

  /// A weekly limit moves slowly, but the user who just ran a long session
  /// wants to see it move. Short enough to feel current, long enough that the
  /// half-minute probe is not paid for on every poll.
  @override
  Duration get quotaTtl => const Duration(minutes: 3);

  @override
  String get sourceDescription =>
      'The weekly limit the Antigravity CLI reports through its own usage '
      'panel. No sign-in — it uses the session `agy` already holds.';
}
