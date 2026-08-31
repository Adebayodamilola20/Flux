import 'dart:convert';
import 'dart:io';

import '../../core/logger.dart';

/// Which account, if any, Gemini CLI is signed in as on this Mac.
class GeminiCliAccount {
  const GeminiCliAccount({this.email, this.isInstalled = false});

  /// The signed-in account, or null when nobody is.
  final String? email;

  /// True when Gemini CLI has been set up here at all.
  final bool isInstalled;

  bool get isSignedIn => email != null;

  static const GeminiCliAccount none = GeminiCliAccount();
}

/// Reads Gemini CLI's own record of who is signed in.
///
/// This exists to tell two very different situations apart, because they need
/// different things from the user:
///
///  * **Nobody is signed in to Gemini CLI.** Fixable — run `gemini` and sign
///    in. Worth saying so.
///  * **Signed in, but Google publishes no quota this app can read.** Not
///    fixable by the user, and worth saying that instead of implying they
///    missed a step.
///
/// Only the account file is read — never the OAuth credentials beside it.
class GeminiCliAccountSource {
  GeminiCliAccountSource({String? homeDirectory, Logger? logger})
      : _home = homeDirectory ?? Platform.environment['HOME'] ?? '',
        _log = logger ?? const Logger('gemini.cli');

  final String _home;
  final Logger _log;

  String get accountsPath => '$_home/.gemini/google_accounts.json';

  Future<GeminiCliAccount> read() async {
    final file = File(accountsPath);
    if (!file.existsSync()) return GeminiCliAccount.none;

    String contents;
    try {
      contents = await file.readAsString();
    } on FileSystemException catch (e) {
      _log.warn('could not read Gemini accounts: ${e.osError?.message}');
      return const GeminiCliAccount(isInstalled: true);
    }

    return parse(contents);
  }

  /// Extracts the active account from the accounts file.
  ///
  /// Separated from the read so the shape can be tested without a filesystem.
  /// The file records an `active` account and a list of previously used ones;
  /// signing out leaves the history in place and sets `active` to null, so only
  /// `active` answers the question being asked.
  static GeminiCliAccount parse(String contents) {
    Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      return const GeminiCliAccount(isInstalled: true);
    }
    if (decoded is! Map<String, dynamic>) {
      return const GeminiCliAccount(isInstalled: true);
    }

    final active = decoded['active'];
    return GeminiCliAccount(
      email: active is String && active.isNotEmpty ? active : null,
      isInstalled: true,
    );
  }
}
