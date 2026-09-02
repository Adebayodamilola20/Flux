import 'dart:convert';
import 'dart:io';

import '../../core/logger.dart';

/// Which ChatGPT account Codex is signed in as on this Mac.
class CodexAccount {
  const CodexAccount({
    this.accountId,
    this.authMode,
    this.isInstalled = false,
    this.signedInAt,
  });

  /// OpenAI's own identifier for the signed-in account.
  ///
  /// Opaque and stable: it is not an email, not a name, and not a credential.
  /// Its only job is to answer "is this the same account as last time".
  final String? accountId;

  /// How Codex is authenticated — `chatgpt` for a plan sign-in, `apikey` for a
  /// key. The plan allowance only exists for the first.
  final String? authMode;

  /// True when Codex has been set up here at all.
  final bool isInstalled;

  /// When Codex last wrote its credentials — the moment of the sign-in now in
  /// force.
  ///
  /// This is the cut-off the transcripts cannot supply themselves. A signed-in
  /// account is not enough to attribute a figure to it: the previous account's
  /// transcripts are still on disk and still the newest thing with an allowance
  /// in them. Anything recorded before this moment was recorded by whoever was
  /// signed in before, so it is not this account's to show.
  ///
  /// A routine token refresh moves it too, which costs at most a few recent
  /// figures — the alternative is showing the account the user just left.
  final DateTime? signedInAt;

  bool get isSignedIn => accountId != null;

  static const CodexAccount none = CodexAccount();

  /// The same account, stamped with when its credentials were written.
  CodexAccount at({DateTime? signedInAt}) => CodexAccount(
    accountId: accountId,
    authMode: authMode,
    isInstalled: isInstalled,
    signedInAt: signedInAt,
  );
}

/// Reads Codex's record of who is signed in.
///
/// This exists because a Codex transcript does not say which account it
/// belongs to. Signing in as somebody else leaves every previous transcript on
/// disk, and the allowance recorded in them keeps reading as current — so a
/// user who switches to a fresh account goes on being shown the exhausted one
/// they left. The account identifier is what tells those transcripts apart from
/// the ones that belong to the account signed in now.
///
/// Only `tokens.account_id` and `auth_mode` are read. The access, refresh and
/// identity tokens in the same file are never read, never parsed, and never
/// leave it — they are not needed to answer this question, and the app has no
/// business holding them.
class CodexAccountSource {
  CodexAccountSource({String? homeDirectory, Logger? logger})
    : _home = homeDirectory ?? Platform.environment['HOME'] ?? '',
      _log = logger ?? const Logger('codex.account');

  final String _home;
  final Logger _log;

  String get authPath => '$_home/.codex/auth.json';

  bool get isAvailable => File(authPath).existsSync();

  /// Fires when Codex rewrites its auth file.
  ///
  /// A sign-in rewrites it, which is the earliest this app can know the account
  /// changed. A routine token refresh rewrites it too, and costs one re-read of
  /// a small file — cheaper than showing the wrong account until the next poll.
  Stream<DateTime> watch({
    Duration interval = const Duration(seconds: 3),
  }) async* {
    DateTime? last = _modifiedAt();

    while (true) {
      await Future<void>.delayed(interval);
      final current = _modifiedAt();
      if (current == null) continue;
      if (last == null || current.isAfter(last)) {
        last = current;
        yield current;
      }
    }
  }

  DateTime? _modifiedAt() {
    try {
      final file = File(authPath);
      return file.existsSync() ? file.statSync().modified : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<CodexAccount> read() async {
    final file = File(authPath);
    if (!file.existsSync()) return CodexAccount.none;

    String contents;
    try {
      contents = await file.readAsString();
    } on FileSystemException catch (e) {
      _log.warn('could not read Codex auth: ${e.osError?.message}');
      return const CodexAccount(isInstalled: true);
    }

    return parse(contents).at(signedInAt: _modifiedAt());
  }

  /// Extracts the account identity from the auth file.
  ///
  /// Separated from the read so the shape can be tested without a filesystem.
  static CodexAccount parse(String contents) {
    Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      return const CodexAccount(isInstalled: true);
    }
    if (decoded is! Map<String, dynamic>) {
      return const CodexAccount(isInstalled: true);
    }

    final tokens = decoded['tokens'];
    final id = tokens is Map<String, dynamic> ? tokens['account_id'] : null;

    return CodexAccount(
      accountId: id is String && id.isNotEmpty ? id : null,
      authMode: decoded['auth_mode'] as String?,
      isInstalled: true,
    );
  }
}
