import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/logger.dart';
import '../../models/usage_source.dart';
import '../../models/usage_window.dart';

/// Why a live Gemini quota reading could not be taken.
enum GeminiQuotaFailure {
  /// Gemini CLI is not signed in on this Mac, so there is no session to use.
  notSignedIn,

  /// The stored access token has expired. Refreshing it is not done here — see
  /// [GeminiCodeAssistSource].
  tokenExpired,

  /// Google rejected the token.
  unauthorized,

  /// The account has no Code Assist project, so there is no quota to report.
  noProject,

  /// Network or transport problem.
  network,

  /// The response was not in a shape we recognise.
  badResponse,
}

/// What Google reported for the signed-in account.
class GeminiQuotaReading {
  const GeminiQuotaReading({
    required this.windows,
    this.tierLabel,
    this.fetchedAt,
  });

  final List<UsageWindow> windows;

  /// The Code Assist tier, e.g. `Google AI Pro`.
  final String? tierLabel;

  final DateTime? fetchedAt;

  bool get hasUsage => windows.isNotEmpty;
}

/// Fetches Gemini quota live, using the session Gemini CLI already holds.
///
/// **This exists because an earlier reading of the CLI was wrong.** Gemini CLI
/// calls `refreshUserQuota` from inside its `generateContent` path, which looks
/// like the quota is a by-product of sending a prompt. It is not: that method
/// calls `retrieveUserQuota` on Google's Code Assist service, which is an
/// ordinary request that can be made on its own. The CLI simply never has a
/// reason to call it at another time. So there *is* a way to ask "how much of
/// my Gemini allowance is left" without spending any of it.
///
/// The request is Google's own, for the user's own account, authorised by the
/// session Gemini CLI established on this Mac and stored in a file the user
/// owns. As with Claude, one line is drawn:
///
///  * the access token is **used** but never **refreshed**. A refresh would
///    mean presenting Gemini CLI's OAuth client as this app's. When the token
///    has expired the card says to run `gemini` once, which refreshes it.
///
/// Nothing is written to the credential file, no web page is scraped, and no
/// figure is invented.
class GeminiCodeAssistSource {
  GeminiCodeAssistSource({
    String? homeDirectory,
    http.Client? client,
    Logger? logger,
  })  : _home = homeDirectory ?? Platform.environment['HOME'] ?? '',
        _client = client ?? http.Client(),
        _log = logger ?? const Logger('gemini.quota');

  /// Google's Code Assist service — the one Gemini CLI talks to.
  static const String endpoint = 'https://cloudcode-pa.googleapis.com';
  static const String apiVersion = 'v1internal';

  static Uri methodUrl(String method) =>
      Uri.parse('$endpoint/$apiVersion:$method');

  final String _home;
  final http.Client _client;
  final Logger _log;

  /// The Code Assist project, once discovered. It does not change between
  /// calls, so the second request is skipped on later refreshes.
  String? _projectId;
  String? _tierLabel;

  String get credentialsPath => '$_home/.gemini/oauth_creds.json';

  /// True when Gemini CLI has signed in on this Mac.
  bool get isSignedIn => File(credentialsPath).existsSync();

  void close() => _client.close();

  /// Forgets the cached project, so the next fetch rediscovers it.
  void reset() {
    _projectId = null;
    _tierLabel = null;
  }

  Future<(GeminiQuotaReading?, GeminiQuotaFailure?)> fetch() async {
    final token = _readAccessToken();
    if (token == null) return (null, GeminiQuotaFailure.notSignedIn);
    if (token.isExpired) return (null, GeminiQuotaFailure.tokenExpired);

    final project = _projectId ?? await _discoverProject(token.value);
    if (project is GeminiQuotaFailure) return (null, project);
    if (project is! String) return (null, GeminiQuotaFailure.noProject);
    _projectId = project;

    final response = await _post(
      'retrieveUserQuota',
      {'project': project},
      token.value,
    );
    if (response is GeminiQuotaFailure) return (null, response);
    if (response is! Map<String, dynamic>) {
      return (null, GeminiQuotaFailure.badResponse);
    }

    final windows = parseBuckets(response);
    if (windows.isEmpty) return (null, GeminiQuotaFailure.badResponse);

    return (
      GeminiQuotaReading(
        windows: windows,
        tierLabel: _tierLabel,
        fetchedAt: DateTime.now(),
      ),
      null,
    );
  }

  /// Asks Code Assist which project this account uses.
  ///
  /// Returns the project id, or a [GeminiQuotaFailure].
  Future<Object?> _discoverProject(String token) async {
    final response = await _post('loadCodeAssist', {
      'metadata': {
        'ideType': 'IDE_UNSPECIFIED',
        'platform': 'PLATFORM_UNSPECIFIED',
        'pluginType': 'GEMINI',
      },
    }, token);

    if (response is GeminiQuotaFailure) return response;
    if (response is! Map<String, dynamic>) {
      return GeminiQuotaFailure.badResponse;
    }

    final tier = response['currentTier'];
    if (tier is Map<String, dynamic>) {
      final name = tier['name'] ?? tier['id'];
      if (name is String && name.isNotEmpty) _tierLabel = name;
    }

    final project = response['cloudaicompanionProject'];
    if (project is String && project.isNotEmpty) return project;
    return GeminiQuotaFailure.noProject;
  }

  /// One Code Assist call. Returns the decoded body, or a failure.
  Future<Object?> _post(
    String method,
    Map<String, Object?> body,
    String token,
  ) async {
    http.Response response;
    try {
      response = await _client
          .post(
            methodUrl(method),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      _log.warn('$method request failed: ${e.runtimeType}');
      return GeminiQuotaFailure.network;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return GeminiQuotaFailure.unauthorized;
    }
    if (response.statusCode != 200) {
      _log.warn('$method returned HTTP ${response.statusCode}');
      return GeminiQuotaFailure.badResponse;
    }

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return GeminiQuotaFailure.badResponse;
    }
  }

  /// Turns the quota response into windows.
  ///
  /// Static so the shape can be tested against a recorded body. Each bucket is
  /// a model with a `remainingFraction` — what is *left*, so the consumed
  /// figure the ring wants is its complement.
  static List<UsageWindow> parseBuckets(Map<String, dynamic> body) {
    final buckets = body['buckets'];
    if (buckets is! List) return const [];

    final windows = <UsageWindow>[];
    final seen = <String>{};

    for (final bucket in buckets) {
      if (bucket is! Map<String, dynamic>) continue;

      final modelId = bucket['modelId'];
      final remaining = bucket['remainingFraction'];
      if (modelId is! String || modelId.isEmpty) continue;
      if (remaining is! num) continue;

      // A duplicate model would draw two rows for one quota.
      if (!seen.add(modelId)) continue;

      final resets = bucket['resetTime'];

      windows.add(UsageWindow(
        id: modelId,
        label: modelLabel(modelId),
        consumed: ((1 - remaining.toDouble()) * 100).clamp(0, 100),
        limit: 100,
        unit: '%',
        resetsAt: resets is String ? DateTime.tryParse(resets)?.toLocal() : null,
        // Google computed this for the account and returned it from its own
        // service — not a figure this app derived.
        source: UsageSource.officialApi,
      ));
    }

    return windows;
  }

  /// `gemini-3-pro-preview` reads as "Gemini 3 Pro" to a person.
  static String modelLabel(String modelId) {
    final words = modelId
        .replaceAll(RegExp(r'-(preview|latest|exp)\b.*$'), '')
        .split('-')
        .where((w) => w.isNotEmpty)
        .toList();

    return [
      for (final word in words)
        word[0].toUpperCase() + word.substring(1),
    ].join(' ');
  }

  _AccessToken? _readAccessToken() {
    final file = File(credentialsPath);
    if (!file.existsSync()) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final value = decoded['access_token'];
    if (value is! String || value.isEmpty) return null;

    final expiry = decoded['expiry_date'];
    return _AccessToken(
      value: value,
      expiresAt: expiry is num
          ? DateTime.fromMillisecondsSinceEpoch(expiry.toInt())
          : null,
    );
  }
}

class _AccessToken {
  const _AccessToken({required this.value, this.expiresAt});

  final String value;
  final DateTime? expiresAt;

  bool get isExpired {
    final at = expiresAt;
    if (at == null) return false;
    return DateTime.now().isAfter(at.subtract(const Duration(minutes: 1)));
  }
}
