import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../core/logger.dart';

/// Everything needed to run one provider's OAuth flow.
///
/// Registered by the app's owner with the provider, not discovered at runtime:
/// OAuth has no mechanism for an unregistered client to authenticate, so a
/// provider without a [clientId] here simply cannot be connected, and the UI
/// says so rather than opening a browser that will only show an error.
class OAuthConfig {
  const OAuthConfig({
    required this.providerId,
    required this.clientId,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.scopes,
    this.clientSecret,
    this.extraAuthParameters = const {},
  });

  final String providerId;
  final String clientId;

  /// Some providers issue a secret even for native "desktop" clients. It is
  /// not a real secret in a distributed app — which is exactly why PKCE is
  /// mandatory here rather than optional.
  final String? clientSecret;

  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final List<String> scopes;

  /// Provider-specific additions, e.g. Google's `access_type=offline`.
  final Map<String, String> extraAuthParameters;

  bool get isConfigured => clientId.trim().isNotEmpty;
}

/// The credentials an authorisation produced.
///
/// Never logged, never written to preferences. The refresh token goes to the
/// macOS Keychain and nowhere else.
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.scope,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String? scope;

  bool get isExpired {
    final at = expiresAt;
    if (at == null) return false;
    // A minute of slack, so a token does not expire mid-request.
    return DateTime.now().isAfter(at.subtract(const Duration(minutes: 1)));
  }

  @override
  String toString() => 'OAuthTokens(expires: $expiresAt)';
}

/// Why an authorisation did not produce tokens.
enum OAuthFailure {
  /// No client is registered for this provider.
  notConfigured,

  /// The user closed the browser or denied consent.
  cancelled,

  /// The provider rejected the request.
  rejected,

  /// The browser could not be opened.
  browserUnavailable,

  /// Network or transport problem.
  network,

  /// Nothing came back before the flow gave up.
  timedOut;

  String get message => switch (this) {
        OAuthFailure.notConfigured =>
          'Sign-in is not configured for this provider yet.',
        OAuthFailure.cancelled => 'Sign-in was cancelled.',
        OAuthFailure.rejected => 'The provider refused the sign-in request.',
        OAuthFailure.browserUnavailable => 'Could not open your browser.',
        OAuthFailure.network => 'Could not reach the provider.',
        OAuthFailure.timedOut => 'Sign-in timed out.',
      };
}

class OAuthResult {
  const OAuthResult.success(this.tokens)
      : failure = null,
        detail = null;
  const OAuthResult.failed(this.failure, {this.detail}) : tokens = null;

  final OAuthTokens? tokens;
  final OAuthFailure? failure;

  /// Provider-supplied explanation, when there is one worth showing.
  final String? detail;

  bool get isSuccess => tokens != null;
}

/// Opens a URL in the user's browser.
typedef BrowserLauncher = Future<bool> Function(Uri url);

/// Runs the authorisation-code flow with PKCE against a loopback redirect.
///
/// This is the flow providers document for native desktop apps, and the reason
/// it looks the way it does:
///
///  * the user authenticates on the **provider's own page in their own
///    browser**, so this app never sees a password and cannot,
///  * the redirect goes to `127.0.0.1` on an ephemeral port, so the code never
///    leaves the machine,
///  * PKCE binds the code to this specific request, so a client secret shipped
///    inside a distributed app is not what protects the exchange,
///  * `state` is checked, so a response this app did not ask for is discarded.
class BrowserOAuthClient {
  BrowserOAuthClient({http.Client? httpClient, Logger? logger, Random? random})
      : _http = httpClient ?? http.Client(),
        _log = logger ?? const Logger('oauth'),
        _random = random ?? Random.secure();

  /// How long to wait for the user to finish in the browser. Long enough to
  /// find a password and pass a 2FA prompt, short enough that an abandoned
  /// flow does not hold a socket open forever.
  static const Duration flowTimeout = Duration(minutes: 4);

  final http.Client _http;
  final Logger _log;
  final Random _random;

  void close() => _http.close();

  /// Runs the full flow and returns the resulting tokens.
  Future<OAuthResult> authorize(
    OAuthConfig config, {
    required BrowserLauncher launch,
  }) async {
    if (!config.isConfigured) {
      return const OAuthResult.failed(OAuthFailure.notConfigured);
    }

    final verifier = _randomUrlSafe(64);
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final state = _randomUrlSafe(24);

    HttpServer server;
    try {
      // Port 0 asks the OS for a free one. A fixed port would collide with
      // whatever else the developer happens to be running.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } on SocketException catch (e) {
      _log.error('could not bind loopback listener', e.osError?.message);
      return const OAuthResult.failed(OAuthFailure.network);
    }

    final redirectUri = Uri.parse('http://127.0.0.1:${server.port}');

    final authorizationUrl = config.authorizationEndpoint.replace(
      queryParameters: {
        'client_id': config.clientId,
        'redirect_uri': redirectUri.toString(),
        'response_type': 'code',
        'scope': config.scopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        ...config.extraAuthParameters,
      },
    );

    if (!await launch(authorizationUrl)) {
      await server.close(force: true);
      return const OAuthResult.failed(OAuthFailure.browserUnavailable);
    }

    final code = await _awaitRedirect(server, expectedState: state);
    await server.close(force: true);

    if (code.failure != null) {
      return OAuthResult.failed(code.failure!, detail: code.detail);
    }

    return _exchange(
      config,
      code: code.code!,
      verifier: verifier,
      redirectUri: redirectUri,
    );
  }

  /// Trades a refresh token for a new access token.
  Future<OAuthResult> refresh(OAuthConfig config, String refreshToken) async {
    if (!config.isConfigured) {
      return const OAuthResult.failed(OAuthFailure.notConfigured);
    }

    return _post(config, {
      'client_id': config.clientId,
      if (config.clientSecret != null) 'client_secret': config.clientSecret!,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    },
        // A refresh response usually omits the refresh token; the caller keeps
        // the one it already has.
        fallbackRefreshToken: refreshToken);
  }

  // MARK: - Internals

  Future<_RedirectOutcome> _awaitRedirect(
    HttpServer server, {
    required String expectedState,
  }) async {
    try {
      final request = await server.first.timeout(flowTimeout);
      final query = request.uri.queryParameters;

      final error = query['error'];
      final returnedState = query['state'];
      final code = query['code'];

      String body;
      _RedirectOutcome outcome;

      if (error != null) {
        outcome = _RedirectOutcome.failed(
          error == 'access_denied'
              ? OAuthFailure.cancelled
              : OAuthFailure.rejected,
          detail: query['error_description'] ?? error,
        );
        body = _page('Sign-in cancelled', 'You can close this tab.');
      } else if (returnedState != expectedState) {
        // A response we did not initiate. Discard it rather than exchange it.
        _log.warn('discarding redirect with mismatched state');
        outcome = const _RedirectOutcome.failed(OAuthFailure.rejected,
            detail: 'The sign-in response did not match this request.');
        body = _page('Sign-in failed', 'You can close this tab.');
      } else if (code == null || code.isEmpty) {
        outcome = const _RedirectOutcome.failed(OAuthFailure.rejected,
            detail: 'No authorization code was returned.');
        body = _page('Sign-in failed', 'You can close this tab.');
      } else {
        outcome = _RedirectOutcome.success(code);
        body = _page('Signed in', 'You can close this tab and return to AI '
            'Usage Monitor.');
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(body);
      await request.response.close();

      return outcome;
    } on TimeoutException {
      return const _RedirectOutcome.failed(OAuthFailure.timedOut);
    } catch (e) {
      _log.error('redirect listener failed', e.runtimeType);
      return const _RedirectOutcome.failed(OAuthFailure.network);
    }
  }

  Future<OAuthResult> _exchange(
    OAuthConfig config, {
    required String code,
    required String verifier,
    required Uri redirectUri,
  }) {
    return _post(config, {
      'client_id': config.clientId,
      if (config.clientSecret != null) 'client_secret': config.clientSecret!,
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': redirectUri.toString(),
      'grant_type': 'authorization_code',
    });
  }

  Future<OAuthResult> _post(
    OAuthConfig config,
    Map<String, String> body, {
    String? fallbackRefreshToken,
  }) async {
    http.Response response;
    try {
      response = await _http
          .post(
            config.tokenEndpoint,
            headers: const {
              'content-type': 'application/x-www-form-urlencoded',
              'accept': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      _log.warn('token request failed: ${e.runtimeType}');
      return const OAuthResult.failed(OAuthFailure.network);
    }

    if (response.statusCode != 200) {
      // The body can name the problem, but it can also echo request values, so
      // only the provider's own error code is surfaced.
      String? detail;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) detail = decoded['error_description'] as String?;
      } on FormatException {
        detail = null;
      }
      _log.warn('token endpoint returned HTTP ${response.statusCode}');
      return OAuthResult.failed(OAuthFailure.rejected, detail: detail);
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return const OAuthResult.failed(OAuthFailure.rejected);
    }
    if (decoded is! Map<String, dynamic>) {
      return const OAuthResult.failed(OAuthFailure.rejected);
    }

    final accessToken = decoded['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      return const OAuthResult.failed(OAuthFailure.rejected);
    }

    final expiresIn = decoded['expires_in'];
    return OAuthResult.success(OAuthTokens(
      accessToken: accessToken,
      refreshToken: (decoded['refresh_token'] as String?) ??
          fallbackRefreshToken,
      expiresAt: expiresIn is num
          ? DateTime.now().add(Duration(seconds: expiresIn.toInt()))
          : null,
      scope: decoded['scope'] as String?,
    ));
  }

  String _randomUrlSafe(int bytes) {
    final values = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  static String _page(String title, String message) => '''
<!doctype html>
<meta charset="utf-8">
<title>$title</title>
<style>
  body { font: 15px -apple-system, system-ui, sans-serif; color: #1d1d1f;
         background: #fbfbfd; display: grid; place-items: center;
         height: 100vh; margin: 0; }
  .card { text-align: center; }
  h1 { font-size: 19px; font-weight: 600; margin: 0 0 6px; }
  p { margin: 0; color: #6e6e73; }
  @media (prefers-color-scheme: dark) {
    body { background: #1c1c1e; color: #f5f5f7; }
    p { color: #98989d; }
  }
</style>
<div class="card"><h1>$title</h1><p>$message</p></div>
''';
}

class _RedirectOutcome {
  const _RedirectOutcome.success(this.code)
      : failure = null,
        detail = null;
  const _RedirectOutcome.failed(this.failure, {this.detail}) : code = null;

  final String? code;
  final OAuthFailure? failure;
  final String? detail;
}
