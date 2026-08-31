import '../../core/logger.dart';
import '../cli/cli_usage_provider.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';

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
    Logger? logger,
  }) : super(logger: logger ?? const Logger('antigravity'));

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
