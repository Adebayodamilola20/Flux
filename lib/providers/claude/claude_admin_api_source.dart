import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/logger.dart';
import '../../models/usage_failure.dart';
import '../../models/usage_source.dart';
import '../../models/usage_window.dart';

/// Provider-reported usage from Anthropic's official Admin API.
///
/// This is the only publicly documented, officially supported way to obtain
/// account-level Claude usage, and it reports **organization API consumption** —
/// not Claude subscription or Claude Code plan limits, which Anthropic does not
/// expose through any public endpoint. The app therefore treats this as an
/// optional supplement to local tracking and labels it accordingly.
///
/// Requires an Admin API key (`sk-ant-admin…`), which the user supplies in
/// Settings and which is stored only in the macOS Keychain.
class ClaudeAdminApiSource {
  ClaudeAdminApiSource({http.Client? client, Logger? logger})
      : _client = client ?? http.Client(),
        _log = logger ?? const Logger('claude.admin');

  static const String _host = 'api.anthropic.com';
  static const String _path = '/v1/organizations/usage_report/messages';
  static const String _apiVersion = '2023-06-01';
  static const Duration _timeout = Duration(seconds: 20);

  /// Window id for the figure this source produces.
  static const String windowId = 'api_daily';

  final http.Client _client;
  final Logger _log;

  void close() => _client.close();

  /// Fetches today's organization-wide token consumption.
  ///
  /// Returns null when the response is well-formed but contains no usage for
  /// the period. Throws [UsageFailure] on any error the user should see.
  Future<UsageWindow?> fetchDailyUsage({required String adminKey}) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc();

    final uri = Uri.https(_host, _path, {
      'starting_at': startOfDay.toIso8601String(),
      'bucket_width': '1d',
      'limit': '1',
    });

    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'x-api-key': adminKey,
          'anthropic-version': _apiVersion,
          'accept': 'application/json',
        },
      ).timeout(_timeout);
    } catch (e) {
      _log.warn('admin API request failed: ${e.runtimeType}');
      throw const UsageFailure(
        UsageFailureKind.network,
        'Could not reach the Anthropic API.',
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
          'The Anthropic admin key was rejected.',
          hint: 'Verify the key in Settings. It must be an Admin API key.',
        );
      case 429:
        throw const UsageFailure(
          UsageFailureKind.rateLimited,
          'Anthropic rate-limited the usage request.',
          hint: 'Try again in a few minutes, or increase the refresh interval.',
        );
      default:
        _log.warn('admin API returned HTTP ${response.statusCode}');
        throw UsageFailure(
          UsageFailureKind.unknown,
          'Anthropic returned an unexpected response '
          '(HTTP ${response.statusCode}).',
        );
    }

    return _parse(response.body);
  }

  UsageWindow? _parse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const UsageFailure(
        UsageFailureKind.unknown,
        'Anthropic returned a response this app could not read.',
      );
    }

    if (decoded is! Map<String, dynamic>) return null;
    final buckets = decoded['data'];
    if (buckets is! List || buckets.isEmpty) return null;

    var total = 0;
    var sawTokenField = false;
    DateTime? endsAt;

    for (final bucket in buckets) {
      if (bucket is! Map<String, dynamic>) continue;
      endsAt ??= switch (bucket['ending_at']) {
        final String s => DateTime.tryParse(s)?.toLocal(),
        _ => null,
      };
      final results = bucket['results'];
      if (results is! List) continue;
      for (final entry in results) {
        if (entry is! Map<String, dynamic>) continue;
        final counted = _sumTokens(entry);
        if (counted != null) {
          sawTokenField = true;
          total += counted;
        }
      }
    }

    // A shape we do not recognise must not be reported as a number — silently
    // showing zero would be indistinguishable from "you used nothing today".
    if (!sawTokenField) {
      throw const UsageFailure(
        UsageFailureKind.unknown,
        'The usage report format was not recognised.',
        hint: 'This app may need an update to read the current API response.',
      );
    }

    return UsageWindow(
      id: windowId,
      label: 'API usage today',
      consumed: total,
      // The Admin API reports consumption, not a quota, so there is no limit
      // to divide by. The UI renders this as a figure without a progress bar.
      limit: null,
      resetsAt: endsAt,
      source: UsageSource.providerReported,
    );
  }

  /// Sums the token fields of one usage result row.
  ///
  /// Returns null when the row carried no recognisable token counts, so the
  /// caller can distinguish "zero usage" from "unknown schema".
  int? _sumTokens(Map<String, dynamic> entry) {
    var total = 0;
    var found = false;

    void add(Object? value) {
      if (value is num) {
        total += value.toInt();
        found = true;
      }
    }

    add(entry['uncached_input_tokens']);
    add(entry['input_tokens']);
    add(entry['cache_read_input_tokens']);
    add(entry['output_tokens']);

    final cacheCreation = entry['cache_creation'];
    if (cacheCreation is Map<String, dynamic>) {
      for (final value in cacheCreation.values) {
        add(value);
      }
    } else {
      add(entry['cache_creation_input_tokens']);
    }

    return found ? total : null;
  }
}
