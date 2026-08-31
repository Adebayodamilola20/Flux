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

  static const String _dismissedPrefix = 'connection.dismissed.';

  /// True when this provider has a stored record of any kind.
  bool has(String providerId) =>
      _prefs.containsKey('$_keyPrefix$providerId');

  /// True when the user deliberately switched this provider off.
  ///
  /// A provider with a working local source adopts itself, so it needs to tell
  /// "never set up" from "switched off" — both of which read as *not
  /// connected*. Only this flag stops adoption, and it is only ever set by
  /// [markDisconnected].
  ///
  /// Deliberately a separate key rather than an inference from the stored
  /// record. A record can be left in a not-connected state by something going
  /// wrong — a sign-in that expired, a credential that vanished from the
  /// Keychain — and treating that as a decision the user made would leave a
  /// slot switched off forever for a reason they never chose.
  bool isDismissed(String providerId) =>
      _prefs.getBool('$_dismissedPrefix$providerId') ?? false;

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
    // Connecting is the opposite of switching off, so it clears the flag.
    if (connection.isConnected) {
      await _prefs.remove('$_dismissedPrefix${connection.providerId}');
    }
    await _prefs.setString(
      '$_keyPrefix${connection.providerId}',
      jsonEncode(connection.toJson()),
    );
  }

  /// Records that the user switched this provider off.
  ///
  /// Sets the flag [isDismissed] reads, so a provider that would otherwise
  /// adopt itself at the next launch leaves the slot alone.
  Future<void> markDisconnected(String providerId) async {
    await save(ProviderConnection.notConnected(providerId));
    await _prefs.setBool('$_dismissedPrefix$providerId', true);
  }

  Future<void> clear(String providerId) async {
    await _prefs.remove('$_keyPrefix$providerId');
    await _prefs.remove('$_dismissedPrefix$providerId');
  }
}
