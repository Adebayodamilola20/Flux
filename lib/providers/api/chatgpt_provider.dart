import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/formatting.dart';
import '../../models/app_settings.dart';
import '../../models/connection_status.dart';
import '../../models/provider_connection.dart';
import '../../models/usage_failure.dart';
import '../../models/usage_source.dart';
import '../../models/usage_window.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';
import '../chatgpt/codex_account_source.dart';
import '../chatgpt/codex_usage_source.dart';
import 'api_key_provider.dart';

/// OpenAI usage, from the documented organization costs endpoint.
///
/// OpenAI publishes no browser sign-in that grants a third-party app access to
/// usage, so the account is linked with a key the user creates in their own
/// OpenAI account. That is OpenAI's own supported mechanism for this, not a
/// workaround invented here.
///
/// What it reports is **API usage and spend**. A ChatGPT Plus subscription is a
/// different product with no usage endpoint at all, and this provider does not
/// pretend otherwise — a key on an account with no API activity reports zero
/// spend, which is the truth rather than a gap.
class ChatGptProvider extends ApiKeyUsageProvider {
  ChatGptProvider({
    required super.native,
    required super.connectionStore,
    super.httpClient,
    super.logger,
    Uri? endpoint,
    CodexUsageSource? codexSource,
    CodexAccountSource? accountSource,
  }) : _endpoint = endpoint ?? defaultEndpoint,
       _codex = codexSource ?? CodexUsageSource(),
       _account = accountSource ?? CodexAccountSource();

  static final Uri defaultEndpoint = Uri.parse(
    'https://api.openai.com/v1/organization/costs',
  );

  final Uri _endpoint;
  final CodexUsageSource _codex;
  final CodexAccountSource _account;

  /// True when Codex has recorded an allowance on this Mac, which is a link
  /// that needs no key at all.
  @override
  bool get supportsLocalOnly => _codex.isAvailable;

  /// Adopts the ChatGPT account Codex is signed in as.
  ///
  /// No browser step: OpenAI publishes no sign-in a third-party app can
  /// register for, and Codex has already authenticated. Connecting here means
  /// reading the allowance OpenAI reported for that account.
  @override
  Future<ProviderConnection> enableLocalOnly() async {
    final account = await _syncAccount();
    final reading = await _codex.read(notBefore: _cutOff(account));

    if (!reading.hasUsage) {
      return updateConnection(
        connection.copyWith(
          status: ConnectionStatus.error,
          message:
              'No Codex usage was found on this Mac. Run Codex once, then '
              'connect again.',
        ),
      );
    }

    return updateConnection(
      ProviderConnection(
        providerId: id,
        status: ConnectionStatus.connected,
        connectedAt: DateTime.now(),
        accountLabel: CodexUsageSource.planLabel(reading.planType),
        accountId: account.accountId,
        accountChangedAt: connection.accountChangedAt,
      ),
    );
  }

  /// Re-reads the moment Codex records a new allowance, or signs in again.
  ///
  /// Codex only learns the figure when it talks to OpenAI, so a transcript
  /// write is the earliest this app can possibly know the number moved. The
  /// auth file is watched alongside it because a sign-in changes which account
  /// the figures are even about, and that must not wait for the next poll.
  @override
  Stream<void>? get changes {
    final sources = [
      if (_codex.isAvailable) _codex.watch(),
      if (_account.isAvailable) _account.watch(),
    ];
    if (sources.isEmpty) return null;
    if (sources.length == 1) return sources.first;
    return _merge(sources);
  }

  /// Two watchers as one stream, for the single listener that subscribes.
  ///
  /// Hand-rolled rather than pulling in a package for one merge. The sources
  /// are infinite polling loops, so cancelling has to reach both of them or
  /// they keep statting files after the provider is gone.
  static Stream<void> _merge(List<Stream<DateTime>> sources) {
    final subscriptions = <StreamSubscription<DateTime>>[];
    late final StreamController<void> controller;

    controller = StreamController<void>(
      onListen: () {
        for (final source in sources) {
          subscriptions.add(
            source.listen(
              (_) => controller.add(null),
              onError: controller.addError,
            ),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        subscriptions.clear();
      },
    );

    return controller.stream;
  }

  /// The moment before which no figure belongs to the account signed in now.
  ///
  /// Two things can establish it, and the later one wins. [signedInAt] is when
  /// Codex last wrote its credentials, which is the sign-in now in force;
  /// `accountChangedAt` is when this app noticed the identifier change. The
  /// file is the more reliable of the two — it is stamped by the sign-in
  /// itself, so it is already correct the first time the app looks, without
  /// having to have been watching when it happened.
  DateTime? _cutOff(CodexAccount account) {
    final noticed = connection.accountChangedAt;
    final signedIn = account.signedInAt;
    if (noticed == null) return signedIn;
    if (signedIn == null) return noticed;
    return signedIn.isAfter(noticed) ? signedIn : noticed;
  }

  /// Notices a sign-in as a different ChatGPT account, and records when.
  ///
  /// Returns the account Codex holds now. When it is not the one the stored
  /// connection was made for, the changeover is stamped — every allowance Codex
  /// recorded before that moment belongs to the previous sign-in, and is
  /// excluded from then on.
  Future<CodexAccount> _syncAccount() async {
    final account = await _account.read();
    final current = account.accountId;

    // Nothing to compare against: either Codex is signed out, or this is the
    // first reading and there is no earlier account to have left.
    if (current == null) return account;
    if (current == connection.accountId) return account;

    final changedAt = DateTime.now();
    if (connection.accountId != null) {
      log.info(
        'Codex signed in as a different account; earlier figures '
        'no longer apply',
      );
    }

    await updateConnection(
      connection.copyWith(
        accountId: current,
        // Stamped only when there was a previous identifier to differ from. A
        // first sighting excludes nothing, because figures recorded before the
        // app ever ran can still belong to the account signed in now — and the
        // sign-in time from the auth file covers the case this cannot: a
        // reconnect clears the stored identifier, so a genuine switch would
        // otherwise read as a first sighting and exclude nothing at all.
        accountChangedAt: connection.accountId == null ? null : changedAt,
        clearAccountLabel: connection.accountId != null,
      ),
    );

    return account;
  }

  /// Reading a local transcript costs nothing, so there is no reason to let the
  /// figure sit for the user's whole refresh interval.
  @override
  Duration? get preferredRefreshInterval => const Duration(seconds: 30);

  @override
  ProviderDescriptor get descriptor => ProviderCatalog.chatgpt;

  @override
  String get sourceDescription =>
      'The Codex allowance OpenAI reports for your ChatGPT account, recorded '
      'locally by Codex. An optional API key adds separate spend reporting.';

  @override
  Uri get keyUrl => Uri.parse('https://platform.openai.com/api-keys');

  @override
  String get keyHint => 'sk-…';

  @override
  Future<ApiUsageReading?> readUsageWithoutKey(AppSettings settings) =>
      readCodexAllowance();

  /// Reads the Codex allowance, which needs no key.
  ///
  /// Kept separate from [readUsage] because the two describe different things:
  /// this is the plan allowance OpenAI reports for the ChatGPT account, and
  /// [readUsage] is spend on a separate API billing account.
  Future<ApiUsageReading> readCodexAllowance() async {
    final account = await _syncAccount();

    if (account.isInstalled && !account.isSignedIn) {
      return const ApiUsageReading.unavailable(
        'Codex is signed out on this Mac. Run `codex` and sign in, then '
        'refresh.',
      );
    }

    // Anything Codex recorded before this sign-in belongs to the account the
    // user left, so it is not offered as this one's.
    final since = _cutOff(account);
    final reading = await _codex.read(notBefore: since);

    if (!reading.hasUsage) {
      return ApiUsageReading.unavailable(
        since == null
            ? 'Codex has not recorded an allowance on this Mac yet.'
            : 'Codex is signed in as a different ChatGPT account than before. '
                  'Run Codex once so OpenAI reports this account’s allowance — '
                  'until then there is nothing to show for it.',
      );
    }

    final plan = CodexUsageSource.planLabel(reading.planType);
    final observedAt = reading.observedAt;

    return ApiUsageReading(
      windows: reading.windows,
      accountLabel: plan,
      notes: [
        if (plan != null) plan,
        // Named precisely: this is the Codex allowance on the ChatGPT plan,
        // not chat message limits and not API spend.
        if (observedAt != null)
          'Codex allowance reported by OpenAI, as of '
              '${Format.relativeTime(observedAt)}.',
      ],
    );
  }

  @override
  Future<ApiUsageReading> readUsage(String apiKey, AppSettings settings) async {
    // Costs are bucketed by day; the current month is the window a spend
    // figure is actually read against.
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);

    final uri = _endpoint.replace(
      queryParameters: {
        'start_time': (monthStart.millisecondsSinceEpoch ~/ 1000).toString(),
        'bucket_width': '1d',
        'limit': '31',
      },
    );

    http.Response response;
    try {
      response = await client
          .get(
            uri,
            headers: {
              'authorization': 'Bearer $apiKey',
              'accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      log.warn('openai request failed: ${e.runtimeType}');
      throw const UsageFailure(
        UsageFailureKind.network,
        'Could not reach OpenAI.',
        hint: 'Check your internet connection and try again.',
      );
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        throw const UsageFailure(
          UsageFailureKind.authentication,
          'OpenAI rejected that key.',
          hint: 'Create a new key at platform.openai.com and paste it again.',
        );
      case 403:
        throw const UsageFailure(
          UsageFailureKind.authentication,
          'That key cannot read usage.',
          hint: 'Costs need an admin key from an account owner.',
        );
      case 429:
        throw const UsageFailure(
          UsageFailureKind.rateLimited,
          'OpenAI rate-limited the request.',
        );
      default:
        throw UsageFailure(
          UsageFailureKind.unknown,
          'OpenAI returned an unexpected response '
          '(HTTP ${response.statusCode}).',
        );
    }

    final spend = _parse(response.body, monthStart);

    // A key adds spend reporting; it does not replace the plan allowance. The
    // allowance is the figure the rail's ring is for — a Plus subscriber with
    // no API activity would otherwise connect a key and see "$0.00", which is
    // true and useless. Both are shown, allowance first.
    final allowance = await readCodexAllowance();
    if (!allowance.hasWindows) return spend;

    return ApiUsageReading(
      windows: [...allowance.windows, ...spend.windows],
      accountLabel: allowance.accountLabel,
      notes: [...allowance.notes, ...spend.notes],
    );
  }

  ApiUsageReading _parse(String body, DateTime monthStart) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const UsageFailure(
        UsageFailureKind.unknown,
        'OpenAI returned a response this app could not read.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const UsageFailure(
        UsageFailureKind.unknown,
        'The OpenAI response format was not recognised.',
      );
    }

    final buckets = decoded['data'];
    if (buckets is! List) {
      throw const UsageFailure(
        UsageFailureKind.unknown,
        'The OpenAI response format was not recognised.',
      );
    }

    var total = 0.0;
    var sawAmount = false;

    for (final bucket in buckets) {
      if (bucket is! Map<String, dynamic>) continue;
      final results = bucket['results'];
      if (results is! List) continue;
      for (final entry in results) {
        if (entry is! Map<String, dynamic>) continue;
        final amount = entry['amount'];
        if (amount is Map<String, dynamic>) {
          final value = amount['value'];
          if (value is num) {
            total += value.toDouble();
            sawAmount = true;
          }
        }
      }
    }

    // A shape we do not recognise must not be reported as a figure — showing
    // zero would be indistinguishable from "you spent nothing this month".
    if (!sawAmount && buckets.isNotEmpty) {
      throw const UsageFailure(
        UsageFailureKind.unknown,
        'The OpenAI usage format was not recognised.',
        hint: 'This app may need an update to read the current response.',
      );
    }

    final nextMonth = DateTime(monthStart.year, monthStart.month + 1);

    return ApiUsageReading(
      windows: [
        UsageWindow(
          id: 'spend_this_month',
          label: 'Spend this month',
          consumed: double.parse(total.toStringAsFixed(2)),
          // OpenAI reports spend, not an allowance. Any budget shown here
          // would be one this app invented.
          limit: null,
          unit: 'USD',
          resetsAt: nextMonth,
          source: UsageSource.officialApi,
        ),
      ],
      notes: const ['API usage and spend, not ChatGPT Plus messages.'],
    );
  }
}
