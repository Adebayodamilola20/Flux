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
  })  : _endpoint = endpoint ?? defaultEndpoint,
        _codex = codexSource ?? CodexUsageSource();

  static final Uri defaultEndpoint =
      Uri.parse('https://api.openai.com/v1/organization/costs');

  final Uri _endpoint;
  final CodexUsageSource _codex;

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
    final reading = await _codex.read();
    if (!reading.hasUsage) {
      return updateConnection(connection.copyWith(
        status: ConnectionStatus.error,
        message: 'No Codex usage was found on this Mac. Run Codex once, then '
            'connect again.',
      ));
    }

    return updateConnection(ProviderConnection(
      providerId: id,
      status: ConnectionStatus.connected,
      connectedAt: DateTime.now(),
      accountLabel: CodexUsageSource.planLabel(reading.planType),
    ));
  }

  /// Re-reads the moment Codex records a new allowance.
  ///
  /// Codex only learns the figure when it talks to OpenAI, so a transcript
  /// write is the earliest this app can possibly know the number moved.
  @override
  Stream<void>? get changes => _codex.isAvailable ? _codex.watch() : null;

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
    final reading = await _codex.read();

    if (!reading.hasUsage) {
      return const ApiUsageReading.unavailable(
        'Codex has not recorded an allowance on this Mac yet.',
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

    final uri = _endpoint.replace(queryParameters: {
      'start_time': (monthStart.millisecondsSinceEpoch ~/ 1000).toString(),
      'bucket_width': '1d',
      'limit': '31',
    });

    http.Response response;
    try {
      response = await client.get(
        uri,
        headers: {
          'authorization': 'Bearer $apiKey',
          'accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));
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
