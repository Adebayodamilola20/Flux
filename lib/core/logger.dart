import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Minimal leveled logger.
///
/// Debug output is compiled out of release builds. Nothing in this app logs
/// credentials, tokens, prompts, or model output — see [redact] for the helper
/// used whenever a value could conceivably be sensitive.
class Logger {
  const Logger(this.scope);

  final String scope;

  void debug(String message) {
    if (kReleaseMode) return;
    _emit('DEBUG', message);
  }

  void info(String message) => _emit('INFO', message);

  void warn(String message) => _emit('WARN', message);

  void error(String message, [Object? cause, StackTrace? stack]) {
    _emit('ERROR', cause == null ? message : '$message: $cause');
    if (!kReleaseMode && stack != null) {
      developer.log(stack.toString(), name: scope, level: 1000);
    }
  }

  void _emit(String level, String message) {
    developer.log('[$level] $message', name: scope);
  }

  /// Renders a secret as a non-reversible presence indicator.
  ///
  /// Used so logs can say "a key is configured" without the key itself ever
  /// reaching a log sink.
  static String redact(String? secret) {
    if (secret == null || secret.isEmpty) return '<none>';
    return '<redacted:${secret.length} chars>';
  }
}
