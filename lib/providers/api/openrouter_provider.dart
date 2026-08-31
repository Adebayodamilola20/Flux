import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/app_settings.dart';
import '../../models/usage_failure.dart';
import '../../models/usage_source.dart';
import '../../models/usage_window.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';
import 'api_key_provider.dart';

/// OpenRouter usage, from its documented key endpoint.
///
/// `GET /api/v1/auth/key` returns the credit spend, the credit limit, and the
/// rate limit for the key making the call — everything needed for a real
/// percentage in one request, with no CLI, no scraping, and no undocumented
/// endpoint.
///
/// A key with no credit limit (pay-as-you-go) has no denominator, so spend is
/// reported as a figure rather than a bar. Inventing a ceiling to draw a
/// percentage against would be the same lie as any other made-up quota.
class OpenRouterProvider extends ApiKeyUsageProvider {
  OpenRouterProvider({
    required super.native,
    required super.connectionStore,
    super.httpClient,
    super.logger,
    Uri? endpoint,
  }) : _endpoint = endpoint ?? defaultEndpoint;

  static final Uri defaultEndpoint =
      Uri.parse('https://openrouter.ai/api/v1/auth/key');

  final Uri _endpoint;

  @override
  ProviderDescriptor get descriptor => ProviderCatalog.openRouter;

  @override
  String get sourceDescription =>
      'OpenRouter’s key endpoint, which reports credits used and your limit.';

  @override
  Uri get keyUrl => Uri.parse('https://openrouter.ai/settings/keys');

  @override
  String get keyHint => 'sk-or-v1-…';

  @override
  Future<ApiUsageReading> readUsage(String apiKey, AppSettings settings) async {
    http.Response response;
    try {
      response = await client.get(
        _endpoint,
        headers: {
          'authorization': 'Bearer $apiKey',
          'accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      log.warn('openrouter request failed: ${e.runtimeType}');
      throw const UsageFailure(
        UsageFailureKind.network,
        'Could not reach OpenRouter.',
        hint: 'Check your internet connection and try again.',
      );
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 401:
      case 403:
        throw const UsageFailure(
          UsageFailureKind.authentication,
          'OpenRouter rejected that key.',
          hint: 'Create a new key at openrouter.ai and paste it again.',
        );
      case 429:
        throw const UsageFailure(
          UsageFailureKind.rateLimited,
          'OpenRouter rate-limited the request.',
          hint: 'Try again shortly, or increase the refresh interval.',
        );
      default:
        throw UsageFailure(
          UsageFailureKind.unknown,
          'OpenRouter returned an unexpected response '
          '(HTTP ${response.statusCode}).',
        );
    }

    return _parse(response.body);
  }

  ApiUsageReading _parse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const UsageFailure(
        UsageFailureKind.unknown,
        'OpenRouter returned a response this app could not read.',
      );
    }

    final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
    if (data is! Map<String, dynamic>) {
      throw const UsageFailure(
        UsageFailureKind.unknown,
        'The OpenRouter response format was not recognised.',
      );
    }

    final label = data['label'] as String?;
    final usage = _number(data['usage']);
    final limit = _number(data['limit']);
    final windows = <UsageWindow>[];

    if (usage != null) {
      windows.add(UsageWindow(
        id: 'credits',
        label: 'Credits',
        consumed: usage,
        // Null for an unlimited key, which renders as a figure without a bar.
        limit: limit != null && limit > 0 ? limit : null,
        unit: 'credits',
        source: UsageSource.officialApi,
      ));
    }

    // The rate limit is a second, genuinely useful window: it is the ceiling
    // users actually hit day to day, and it costs nothing extra to report.
    final rateLimit = data['rate_limit'];
    if (rateLimit is Map<String, dynamic>) {
      final requests = _number(rateLimit['requests']);
      final interval = rateLimit['interval'];
      if (requests != null && requests > 0) {
        windows.add(UsageWindow(
          id: 'rate_limit',
          label: interval is String ? 'Rate limit ($interval)' : 'Rate limit',
          // A ceiling, not a consumption: reported as its own limit so the UI
          // shows the allowance rather than pretending to know what is left.
          consumed: 0,
          limit: requests,
          unit: 'requests',
          source: UsageSource.officialApi,
        ));
      }
    }

    if (windows.isEmpty) {
      return ApiUsageReading.unavailable(
        'OpenRouter reported no usage for this key.',
        accountLabel: label,
      );
    }

    return ApiUsageReading(
      windows: windows,
      accountLabel: label,
      notes: [
        if (data['is_free_tier'] == true) 'Free tier key.',
      ],
    );
  }

  static num? _number(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }
}
