import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/logger.dart';
import '../models/provider_connection.dart';

/// Persists which providers the user has connected.
///
/// Stores state only — never credentials. The secret that backs a connection
/// lives in the macOS Keychain and is reachable only by the provider that owns
/// it, so a copied preferences file grants nothing.
class ConnectionStore {
  ConnectionStore({required SharedPreferences preferences, Logger? logger})
      : _prefs = preferences,
        _log = logger ?? const Logger('connections');

  static const String _keyPrefix = 'connection.';

  final SharedPreferences _prefs;
  final Logger _log;

  ProviderConnection load(String providerId) {
    final raw = _prefs.getString('$_keyPrefix$providerId');
    if (raw == null) return ProviderConnection.notConnected(providerId);

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return ProviderConnection.notConnected(providerId);
      }
      return ProviderConnection.fromJson(decoded) ??
          ProviderConnection.notConnected(providerId);
    } on FormatException {
      _log.warn('discarding unreadable connection record for $providerId');
      return ProviderConnection.notConnected(providerId);
    }
  }

  Future<void> save(ProviderConnection connection) async {
    await _prefs.setString(
      '$_keyPrefix${connection.providerId}',
      jsonEncode(connection.toJson()),
    );
  }

  Future<void> clear(String providerId) async {
    await _prefs.remove('$_keyPrefix$providerId');
  }
}
