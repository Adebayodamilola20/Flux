import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logger.dart';
import '../models/app_settings.dart';
import 'native/native_bridge.dart';

/// Loads, persists, and applies user preferences.
///
/// Settings are stored as a single JSON blob so adding a field never requires a
/// migration. The launch-at-login preference is mirrored into the real macOS
/// login-item registration, and the stored value is reconciled with the system
/// state on startup.
class SettingsService extends ChangeNotifier {
  SettingsService({
    required SharedPreferences preferences,
    required NativeBridge native,
    Logger? logger,
  })  : _prefs = preferences,
        _native = native,
        _log = logger ?? const Logger('settings');

  static const String _storageKey = 'app_settings_v1';

  final SharedPreferences _prefs;
  final NativeBridge _native;
  final Logger _log;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  /// Reads persisted settings and reconciles them with macOS state.
  Future<void> load() async {
    final raw = _prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _settings = AppSettings.fromJson(decoded);
        }
      } on FormatException catch (e) {
        _log.warn('discarding unreadable settings: ${e.message}');
      }
    }

    // The system is the source of truth for login-item state — the user may
    // have removed it in System Settings since we last wrote it.
    final actualLoginItem = await _native.isLaunchAtLoginEnabled();
    if (actualLoginItem != _settings.launchAtLogin) {
      _settings = _settings.copyWith(launchAtLogin: actualLoginItem);
      await _persist();
    }

    notifyListeners();
  }

  Future<void> update(AppSettings next) async {
    if (next == _settings) return;
    final previous = _settings;
    _settings = next;
    notifyListeners();

    if (next.launchAtLogin != previous.launchAtLogin) {
      final applied = await _native.setLaunchAtLogin(next.launchAtLogin);
      if (!applied) {
        // Registration failed — reflect reality rather than the request.
        _log.warn('login item registration was refused by macOS');
        _settings = _settings.copyWith(launchAtLogin: previous.launchAtLogin);
        notifyListeners();
      }
    }

    await _persist();
  }

  Future<void> _persist() async {
    await _prefs.setString(_storageKey, jsonEncode(_settings.toJson()));
  }
}
