import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/logger.dart';
import '../../models/usage_source.dart';
import '../../models/usage_window.dart';
import '../../services/native/native_bridge.dart';

/// Reads Claude Code's stored session from the Keychain.
///
/// Injected rather than imported so tests exercise this class without a native
/// binding, and so the only production implementation is the narrow, hard-coded
/// one in the native layer.
typedef KeychainCredentialReader = Future<ClaudeCodeCredentialAccess> Function();

/// Reads *when* Claude Code last wrote that session, without reading it.
///
/// Injected for the same reason as [KeychainCredentialReader]. Kept separate
/// because the two calls differ in the way that matters: this one touches only
/// the item's attributes, so it never raises the approval dialog and can be
/// asked on every poll.
typedef KeychainStampReader = Future<DateTime?> Function();

/// The result of a live usage fetch.
class ClaudeLiveReading {
  const ClaudeLiveReading({
    required this.windows,
    this.fetchedAt,
  });

  final List<UsageWindow> windows;

  /// When this was fetched — for a live call, essentially now.
  final DateTime? fetchedAt;

  bool get hasUsage => windows.isNotEmpty;
}

/// Why a live fetch could not be done, so the caller can fall back to the cache
/// rather than treat every miss the same way.
enum ClaudeLiveFailure {
  /// Claude Code is not signed in on this machine.
  noCredentials,

  /// The user declined the macOS prompt to read Claude Code's stored session.
  /// Nothing is broken; there is simply no live token to use this time.
  keychainDenied,

  /// The stored access token has expired. Refreshing it is possible but would
  /// invalidate Claude Code's own copy, so it is not done here — the caller
  /// uses the cache instead.
  tokenExpired,

  /// The endpoint rejected the token.
  unauthorized,

  /// Network or transport problem.
  network,

  /// The response was not in a shape we recognise.
  badResponse,
}

/// Fetches Claude subscription usage live, using the session Claude Code
/// already holds.
///
/// This is the same mechanism Claude Code itself uses: its OAuth access token
/// authorises a call to Anthropic's own usage endpoint, which returns the
/// server-computed utilization. The figures are Anthropic's, fetched now,
/// rather than the cached copy Claude Code last wrote to `~/.claude.json`.
///
/// The credential is Claude Code's, on the user's own machine, for the user's
/// own account, read from a file the user owns. This class deliberately draws
/// one line:
///
///  * it **uses** the existing access token, but does **not refresh** it. A
///    refresh would rotate the token and invalidate the copy Claude Code holds,
///    logging the user out of their own CLI. When the token has expired the
///    caller falls back to the cached figures instead, which is a stale number
///    but not a broken login.
///
/// **Where the session is found.** Claude Code used to keep its tokens in
/// `~/.claude/.credentials.json`. On macOS it now keeps them in the login
/// Keychain and leaves that file behind, unmaintained — so on a current install
/// the file holds a token that expired months ago. Reading the file alone
/// therefore fails every time, and the provider silently falls back to the
/// cached figure in `~/.claude.json`, which is exactly the stale number this
/// class exists to replace. The Keychain is tried first for that reason, with
/// the file kept as a fallback for older installs.
///
/// It never writes to Claude Code's credential store, never scrapes a web page,
/// and never fabricates a figure.
class ClaudeLiveUsageSource {
  ClaudeLiveUsageSource({
    String? homeDirectory,
    http.Client? client,
    Logger? logger,
    KeychainCredentialReader? keychainReader,
    KeychainStampReader? keychainStampReader,
  })  : _home = homeDirectory ?? Platform.environment['HOME'] ?? '',
        _client = client ?? http.Client(),
        _keychain = keychainReader,
        _stamp = keychainStampReader,
        _log = logger ?? const Logger('claude.live');

  /// Anthropic's own usage endpoint — the one Claude Code calls.
  static final Uri usageUrl =
      Uri.parse('https://api.anthropic.com/api/oauth/usage');

  /// Headers Anthropic expects on this call. The beta flag gates the OAuth
  /// surface; the user agent is what the endpoint (behind Cloudflare) accepts.
  static const Map<String, String> _headers = {
    'anthropic-beta': 'oauth-2025-04-20',
    'User-Agent': 'claude-code/1.0.0',
    'Accept': 'application/json',
  };

  /// How long to wait before asking the Keychain again after a refusal.
  ///
  /// Without this, a user who dismisses the approval dialog once would be shown
  /// it again on the next poll, and every poll after that. A refusal is an
  /// answer, and it is respected for a while.
  static const Duration keychainBackoff = Duration(minutes: 30);

  /// How long a token is trusted without re-checking the store behind it.
  ///
  /// The stamp check below is the real mechanism; this is the backstop for when
  /// there is no stamp to read — an older macOS, or a build without the native
  /// call. Without it, "held for its lifetime" means a token read before a
  /// sign-in can go on answering for the previous account for hours.
  static const Duration tokenHold = Duration(minutes: 5);

  final String _home;
  final http.Client _client;
  final KeychainCredentialReader? _keychain;
  final KeychainStampReader? _stamp;
  final Logger _log;

  /// The last token read, held until the store behind it changes.
  ///
  /// Reading the Keychain's *data* is not free — it is an inter-process call
  /// that can raise a dialog — so the token is kept in memory and re-read only
  /// when there is reason to. Reading the *stamp* is free and silent, and it is
  /// what supplies the reason.
  _AccessToken? _token;

  /// The credential's modification date as of the last time the store was
  /// consulted — whatever came of it.
  ///
  /// When the current stamp no longer matches this, the stored session has been
  /// replaced: the user signed in again, possibly as somebody else. Anything
  /// decided last time is then out of date — both a held token, which now
  /// answers for an account they have left, and a refusal, which was an answer
  /// about a session that no longer exists.
  ///
  /// Recorded on a refusal too, deliberately. Only recording it alongside a
  /// successful read would mean a user who declined the prompt could never be
  /// noticed signing in again, which is the one case where asking once more is
  /// obviously right.
  DateTime? _seenStamp;

  /// When [_token] was read, for the [tokenHold] backstop.
  DateTime? _tokenReadAt;

  /// When the Keychain last refused, so it is not asked again immediately.
  DateTime? _deniedAt;

  String get credentialsPath => '$_home/.claude/.credentials.json';

  void close() => _client.close();

  /// True when Claude Code has stored credentials on this machine.
  ///
  /// The Keychain cannot be consulted without possibly raising a dialog, so
  /// this stays a cheap filesystem check: a `~/.claude.json` written by Claude
  /// Code means Claude Code is set up here, whichever store holds its token.
  bool get isAvailable =>
      File(credentialsPath).existsSync() || File('$_home/.claude.json').existsSync();

  /// Fetches live usage, or returns the reason it could not.
  ///
  /// Returns a [ClaudeLiveFailure] rather than throwing so the provider can
  /// decide between falling back to the cache (expired token) and surfacing an
  /// error (rejected token).
  Future<(ClaudeLiveReading?, ClaudeLiveFailure?)> fetch() async {
    final (token, lookupFailure) = await _accessToken();
    if (lookupFailure != null) return (null, lookupFailure);
    if (token == null) return (null, ClaudeLiveFailure.noCredentials);
    if (token.isExpired) return (null, ClaudeLiveFailure.tokenExpired);

    http.Response response;
    try {
      response = await _client.get(
        usageUrl,
        headers: {
          ..._headers,
          'Authorization': 'Bearer ${token.value}',
        },
      ).timeout(const Duration(seconds: 12));
    } catch (e) {
      _log.warn('live usage request failed: ${e.runtimeType}');
      return (null, ClaudeLiveFailure.network);
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return (null, ClaudeLiveFailure.unauthorized);
    }
    if (response.statusCode != 200) {
      _log.warn('live usage returned HTTP ${response.statusCode}');
      return (null, ClaudeLiveFailure.badResponse);
    }

    final reading = _parse(response.body);
    if (reading == null) return (null, ClaudeLiveFailure.badResponse);
    return (reading, null);
  }

  /// Finds a usable session: Keychain first, then the legacy file.
  ///
  /// The two stores are tried in the order Claude Code actually maintains them.
  /// A token that parses but has expired is not treated as the final answer
  /// while another store is still untried — an old file next to a live Keychain
  /// entry is the normal state of a current install, and stopping at the file
  /// is what makes the rail show a stale figure.
  Future<(_AccessToken?, ClaudeLiveFailure?)> _accessToken() async {
    // Has the stored session been replaced since the held token was read? This
    // is the question a signed-in-again user is really asking, and it is
    // answered without touching the secret or raising a dialog.
    final stamp = await _currentStamp();
    if (stamp != null && _seenStamp != null && stamp != _seenStamp) {
      _log.info('Claude Code’s stored session changed; re-reading it');
      _token = null;
      // A new sign-in is a new question, so an earlier refusal is not held
      // against it. The user who declined once and has now signed in again
      // should not have to wait out the back-off to see their own account.
      _deniedAt = null;
    }

    // A token already in hand is reused while the store behind it is unchanged
    // and it has not expired. Claude Code also rotates it on its own schedule;
    // when it does, this goes stale and the stores are consulted again.
    final held = _token;
    if (held != null && !held.isExpired && !_isHeldTooLong) return (held, null);
    _token = null;

    var denied = false;

    // The best expired token seen so far. Kept because "signed in, but the
    // token has gone stale" and "not signed in at all" mean different things to
    // the user, and only the second is worth reporting as a missing account.
    _AccessToken? expired;

    final read = _keychain;
    if (read != null && !_isInKeychainBackoff) {
      final access = await read();
      // The store has now been consulted at this stamp, whatever it said.
      _seenStamp = stamp;
      if (access.isDenied) {
        denied = true;
        _deniedAt = DateTime.now();
        _log.info('Keychain read declined; falling back to the stored file');
      }
      final blob = access.blob;
      if (blob != null) {
        _deniedAt = null;
        final token = _parseToken(blob);
        if (token != null) {
          if (!token.isExpired) {
            _hold(token, stamp);
            return (token, null);
          }
          expired ??= token;
        }
      }
    } else if (read != null) {
      denied = true;
    }

    final file = File(credentialsPath);
    if (file.existsSync()) {
      String contents;
      try {
        contents = file.readAsStringSync();
      } on FileSystemException {
        contents = '';
      }
      final token = _parseToken(contents);
      if (token != null) {
        if (!token.isExpired) {
          _hold(token, stamp);
          return (token, null);
        }
        expired ??= token;
      }
    }

    if (expired != null) return (expired, null);
    if (denied) return (null, ClaudeLiveFailure.keychainDenied);
    return (null, null);
  }

  bool get _isInKeychainBackoff {
    final at = _deniedAt;
    return at != null && DateTime.now().difference(at) < keychainBackoff;
  }

  bool get _isHeldTooLong {
    final at = _tokenReadAt;
    return at == null || DateTime.now().difference(at) >= tokenHold;
  }

  /// Keeps a token, and the state of the store it came from.
  void _hold(_AccessToken token, DateTime? stamp) {
    _token = token;
    _seenStamp = stamp;
    _tokenReadAt = DateTime.now();
  }

  /// The credential's modification date, or null when it cannot be read.
  ///
  /// A failure here is not treated as "unchanged" — it simply leaves the
  /// [tokenHold] backstop to decide, so a build that cannot read the stamp
  /// still notices a sign-in, just a few minutes later rather than at once.
  Future<DateTime?> _currentStamp() async {
    final read = _stamp;
    if (read == null) return null;
    try {
      return await read();
    } catch (e) {
      _log.debug('could not read the credential stamp: ${e.runtimeType}');
      return null;
    }
  }

  /// Forgets the held token and any refusal, so the next fetch consults the
  /// Keychain again.
  ///
  /// This is what the card's Refresh button is for: a user who declined the
  /// dialog, or who has since signed in to Claude Code, should not have to wait
  /// out [keychainBackoff] to try again.
  void reset() {
    _token = null;
    _seenStamp = null;
    _tokenReadAt = null;
    _deniedAt = null;
  }

  /// Reads an access token out of a stored credential blob.
  ///
  /// Static so the shape can be tested without a Keychain or a filesystem.
  static _AccessToken? _parseToken(String blob) {
    if (blob.isEmpty) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(blob);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    // The Keychain blob and the file share a shape, but the Keychain copy is
    // sometimes the inner object on its own.
    final oauth = decoded['claudeAiOauth'] is Map<String, dynamic>
        ? decoded['claudeAiOauth'] as Map<String, dynamic>
        : decoded;

    final value = oauth['accessToken'];
    if (value is! String || value.isEmpty) return null;

    final expiresAt = oauth['expiresAt'];
    return _AccessToken(
      value: value,
      expiresAt: expiresAt is num
          ? DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt())
          : null,
    );
  }

  /// Parses the live response into windows.
  ///
  /// Static so the shape can be tested against a recorded body. The response
  /// carries the same `utilization` structure as the local cache, so this
  /// mirrors the cache parser deliberately.
  static ClaudeLiveReading? _parse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    // The endpoint returns the utilization map either at the top level or under
    // a `utilization` key depending on version; both are handled.
    final utilization = decoded['utilization'] is Map<String, dynamic>
        ? decoded['utilization'] as Map<String, dynamic>
        : decoded;

    final windows = <UsageWindow>[];
    const named = {
      'five_hour': 'Current session',
      'seven_day': 'This week',
    };

    named.forEach((key, label) {
      final window = _window(utilization[key], id: key, label: label);
      if (window != null) windows.add(window);
    });

    if (windows.isEmpty) return null;
    return ClaudeLiveReading(windows: windows, fetchedAt: DateTime.now());
  }

  static UsageWindow? _window(
    Object? bucket, {
    required String id,
    required String label,
  }) {
    if (bucket is! Map<String, dynamic>) return null;
    final value = bucket['utilization'];
    if (value is! num) return null;

    final resets = bucket['resets_at'];
    return UsageWindow(
      id: id,
      label: label,
      consumed: value.clamp(0, 100),
      limit: 100,
      unit: '%',
      resetsAt: resets is String ? DateTime.tryParse(resets)?.toLocal() : null,
      source: UsageSource.officialApi,
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
    // A minute of slack so a token does not expire mid-request.
    return DateTime.now().isAfter(at.subtract(const Duration(minutes: 1)));
  }
}
