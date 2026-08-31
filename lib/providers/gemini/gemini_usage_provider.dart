import '../../core/logger.dart';
import '../../models/app_settings.dart';
import '../cli/cli_usage_provider.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';
import 'gemini_cli_account.dart';
import 'gemini_code_assist_source.dart';

/// Gemini, read live from Google's Code Assist service.
///
/// **There is no sign-in step in this app**: it uses the session Gemini CLI
/// already established on this Mac, from `~/.gemini/oauth_creds.json`.
///
/// **A correction worth recording.** This slot previously reported that no
/// Gemini quota could be read at all. That was wrong, and wrong in an
/// instructive way. Gemini CLI calls `refreshUserQuota` from inside its
/// `generateContent` path, which makes the figure look like a by-product of
/// sending a prompt. It is not — that method calls `retrieveUserQuota` on
/// Google's Code Assist service, an ordinary request that stands on its own.
/// The CLI simply never has another reason to make it. Reading the call site
/// and inferring the capability from it was the mistake; reading what the call
/// actually does is what fixed it.
///
/// So the figure here is Google's own, fetched now, per model: each bucket
/// carries a `remainingFraction` and a reset time.
///
/// As with Claude, the stored token is used but never refreshed — that would
/// mean presenting Gemini CLI's OAuth client as this app's. When it expires the
/// card says to run `gemini` once, which refreshes it.
class GeminiUsageProvider extends CliUsageProvider {
  GeminiUsageProvider({
    required super.native,
    required super.connectionStore,
    super.source,
    GeminiCliAccountSource? accountSource,
    GeminiCodeAssistSource? quotaSource,
    Logger? logger,
  })  : _accounts = accountSource ?? GeminiCliAccountSource(),
        _quota = quotaSource ?? GeminiCodeAssistSource(),
        super(logger: logger ?? const Logger('gemini'));

  final GeminiCliAccountSource _accounts;
  final GeminiCodeAssistSource _quota;

  /// The account the last reading belonged to. See [readUsage].
  String? _lastAccount;

  @override
  ProviderDescriptor get descriptor => ProviderCatalog.gemini;

  @override
  String get executable => 'gemini';

  /// Never used: [readUsage] asks Google directly rather than driving the CLI.
  /// Declared only to satisfy the base class.
  @override
  String get usageCommand => '/stats';

  @override
  String get activityLabel => 'Gemini CLI';

  @override
  String get sourceDescription =>
      'Google’s Code Assist service, asked directly using the session Gemini '
      'CLI already holds on this Mac.';

  @override
  Future<CliUsageReading> readUsage(AppSettings settings) async {
    final account = await _accounts.read();

    // The Code Assist project is cached across refreshes because it does not
    // change — for one account. Signing in as a different Google account gives
    // a different project, and asking the new session about the old one either
    // fails or answers for an account the user has left.
    if (_lastAccount != null && account.email != _lastAccount) {
      log.info('the signed-in Google account changed; rediscovering its '
          'Code Assist project');
      _quota.reset();
    }
    _lastAccount = account.email;

    final (quota, failure) = await _quota.fetch();

    if (quota != null && quota.hasUsage) {
      return CliUsageReading(
        windows: quota.windows,
        accountLabel: account.email,
        notes: [
          if (quota.tierLabel != null) quota.tierLabel!,
          'Live from Google, just now.',
        ],
      );
    }

    return switch (failure) {
      GeminiQuotaFailure.notSignedIn => const CliUsageReading.unavailable(
          'Gemini CLI is not signed in on this Mac. Run `gemini`, sign in '
          'once, and your remaining quota appears here.',
        ),
      GeminiQuotaFailure.tokenExpired => CliUsageReading.unavailable(
          'Gemini CLI’s stored session has expired. Run `gemini` once to '
          'refresh it.',
          accountLabel: account.email,
        ),
      GeminiQuotaFailure.unauthorized => CliUsageReading.unavailable(
          'Google rejected the session Gemini CLI stored here. Run `gemini` '
          'and sign in again.',
          accountLabel: account.email,
        ),
      GeminiQuotaFailure.noProject => CliUsageReading.unavailable(
          'This Google account has no Code Assist project, which is what the '
          'quota is measured against. Running `gemini` once sets one up.',
          accountLabel: account.email,
        ),
      GeminiQuotaFailure.network => CliUsageReading.unavailable(
          'Google could not be reached.',
          accountLabel: account.email,
        ),
      _ => CliUsageReading.unavailable(
          'Google returned a quota response this app could not read. It may '
          'need an update.',
          accountLabel: account.email,
        ),
    };
  }

  @override
  void invalidateCaches() {
    _quota.reset();
    super.invalidateCaches();
  }

  /// One small request against Google's own service, so there is no reason to
  /// let the figure sit for the user's whole refresh interval.
  @override
  Duration? get preferredRefreshInterval => const Duration(seconds: 60);

  @override
  Future<void> dispose() async {
    _quota.close();
    await super.dispose();
  }
}
