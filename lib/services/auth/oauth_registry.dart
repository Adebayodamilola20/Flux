import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'oauth.dart';

/// Where each provider's sign-in lives, and which client this app presents.
///
/// The endpoints are fixed — they are the providers' documented OAuth
/// endpoints. The **client id is not shipped**, because an OAuth client has to
/// be registered by whoever publishes the app, and a client id baked into a
/// public repository is one revocation away from breaking every install.
///
/// So the id is read from configuration at runtime. Until one is present the
/// provider reports [OAuthFailure.notConfigured] and the connect screen says
/// what is missing, instead of opening a browser onto an error page.
class OAuthRegistry {
  OAuthRegistry({required SharedPreferences preferences})
      : _prefs = preferences;

  static const String _clientIdPrefix = 'oauth.clientId.';
  static const String _clientSecretPrefix = 'oauth.clientSecret.';

  final SharedPreferences _prefs;

  /// Google's OAuth 2.0 endpoints, used by both Gemini and Antigravity — they
  /// are the same Google account.
  static final Uri _googleAuthorize =
      Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');
  static final Uri _googleToken =
      Uri.parse('https://oauth2.googleapis.com/token');

  /// The scope templates each provider needs.
  ///
  /// Deliberately minimal: identity so the app can show which account is
  /// connected, and the one platform scope that quota endpoints require.
  /// Nothing that would grant access to the user's content.
  /// Only `openid` and `email`, which is all this app actually calls: the
  /// userinfo endpoint, to show which account is connected.
  ///
  /// A broader scope like `cloud-platform` would drag the user through
  /// Google's unverified-app warning and grant this app access it never uses.
  /// Scopes get added when an integration genuinely calls something, not in
  /// advance.
  static const Map<String, List<String>> _scopes = {
    'antigravity': ['openid', 'email'],
  };

  /// Whether this provider has an OAuth definition at all.
  bool supports(String providerId) => _scopes.containsKey(providerId);

  /// The config for a provider, or null when it does not use OAuth.
  OAuthConfig? configFor(String providerId) {
    final scopes = _scopes[providerId];
    if (scopes == null) return null;

    return OAuthConfig(
      providerId: providerId,
      clientId: _prefs.getString('$_clientIdPrefix$providerId') ?? '',
      clientSecret: _prefs.getString('$_clientSecretPrefix$providerId'),
      authorizationEndpoint: _googleAuthorize,
      tokenEndpoint: _googleToken,
      scopes: scopes,
      extraAuthParameters: const {
        // Without these Google returns no refresh token on repeat consent, and
        // the connection would silently stop working after an hour.
        'access_type': 'offline',
        // `select_account` is what lets someone with several Google accounts
        // choose which one to connect, instead of Google silently using
        // whichever happens to be signed in first. `consent` is kept so a
        // refresh token is issued every time.
        'prompt': 'select_account consent',
        'include_granted_scopes': 'true',
      },
    );
  }

  /// True when a client has been registered for this provider.
  bool isConfigured(String providerId) =>
      configFor(providerId)?.isConfigured ?? false;

  /// Records the client the app should present for a provider.
  ///
  /// The "secret" that desktop OAuth clients are issued is not a secret in a
  /// distributed app, which is why PKCE carries the security here. It is stored
  /// alongside the id rather than in the Keychain, so it is not mistaken for a
  /// user credential.
  Future<void> setClient(
    String providerId, {
    required String clientId,
    String? clientSecret,
  }) async {
    final trimmed = clientId.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove('$_clientIdPrefix$providerId');
    } else {
      await _prefs.setString('$_clientIdPrefix$providerId', trimmed);
    }

    final secret = clientSecret?.trim();
    if (secret == null || secret.isEmpty) {
      await _prefs.remove('$_clientSecretPrefix$providerId');
    } else {
      await _prefs.setString('$_clientSecretPrefix$providerId', secret);
    }
  }

  /// Reads a client out of the JSON Google hands you on download.
  ///
  /// Google's file is the artefact users actually have, so importing it beats
  /// asking them to copy two fields out of it by hand — and it rules out the
  /// commonest setup mistake, which is pasting the wrong one.
  ///
  /// Returns the client id on success, or null when the file is not a Google
  /// client file. Only `installed` (Desktop app) clients are accepted: a `web`
  /// client cannot use the loopback redirect this flow depends on, and would
  /// fail later with an opaque `redirect_uri_mismatch`.
  Future<String?> importGoogleClientFile(String contents, String providerId) async {
    Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final installed = decoded['installed'];
    if (installed is! Map<String, dynamic>) return null;

    final clientId = installed['client_id'];
    if (clientId is! String || clientId.isEmpty) return null;

    await setClient(
      providerId,
      clientId: clientId,
      clientSecret: installed['client_secret'] as String?,
    );
    return clientId;
  }

  /// Why an import was rejected, for the message shown to the user.
  static String importRejectionReason(String contents) {
    try {
      final decoded = jsonDecode(contents);
      if (decoded is Map && decoded.containsKey('web')) {
        return 'That is a Web application client. Create a Desktop app client '
            'instead — only those can use the loopback sign-in this app needs.';
      }
    } on FormatException {
      return 'That file is not valid JSON.';
    }
    return 'That does not look like a Google OAuth client file.';
  }

  /// Where the user goes to create the client, shown next to the field.
  static String? registrationUrl(String providerId) => switch (providerId) {
        'antigravity' =>
          'https://console.cloud.google.com/apis/credentials',
        _ => null,
      };
}
