import 'dart:convert';

import '../../core/logger.dart';
import '../native/native_bridge.dart';
import 'oauth.dart';

/// Keeps OAuth tokens in the macOS Keychain.
///
/// Tokens are the one thing in this app that genuinely must not sit in a
/// preferences file: a refresh token is a standing grant on the user's account.
/// Everything here goes through the Keychain, and nothing is ever written to a
/// log — [toString] on [OAuthTokens] deliberately omits the values.
class OAuthTokenStore {
  OAuthTokenStore({required NativeBridge native, Logger? logger})
      : _native = native,
        _log = logger ?? const Logger('tokens');

  final NativeBridge _native;
  final Logger _log;

  static String _key(String providerId) => 'oauth.tokens.$providerId';

  Future<OAuthTokens?> read(String providerId) async {
    final raw = await _native.readSecret(_key(providerId));
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final accessToken = decoded['accessToken'];
      if (accessToken is! String || accessToken.isEmpty) return null;

      return OAuthTokens(
        accessToken: accessToken,
        refreshToken: decoded['refreshToken'] as String?,
        expiresAt: switch (decoded['expiresAt']) {
          final String s => DateTime.tryParse(s),
          _ => null,
        },
        scope: decoded['scope'] as String?,
      );
    } on FormatException {
      // A corrupt entry is discarded rather than repaired: the worst outcome
      // is one extra sign-in.
      _log.warn('discarding unreadable token entry for $providerId');
      return null;
    }
  }

  Future<bool> write(String providerId, OAuthTokens tokens) {
    return _native.writeSecret(
      _key(providerId),
      jsonEncode({
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
        'expiresAt': tokens.expiresAt?.toIso8601String(),
        'scope': tokens.scope,
      }),
    );
  }

  Future<void> clear(String providerId) async {
    await _native.writeSecret(_key(providerId), null);
  }
}
