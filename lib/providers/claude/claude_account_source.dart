import 'dart:convert';
import 'dart:io';

import '../../core/logger.dart';
import '../../models/usage_source.dart';
import '../../models/usage_window.dart';

/// The Claude account and subscription usage Claude Code records locally.
class ClaudeAccountReading {
  const ClaudeAccountReading({
    required this.windows,
    this.email,
    this.displayName,
    this.plan,
    this.fetchedAt,
  });

  final List<UsageWindow> windows;
  final String? email;
  final String? displayName;

  /// The subscription tier Anthropic reports, e.g. `claude_pro`.
  final String? plan;

  /// When Claude Code last refreshed these figures.
  ///
  /// Surfaced rather than hidden: this is a cache, and a percentage from three
  /// hours ago should say so instead of implying a live reading.
  final DateTime? fetchedAt;

  bool get isSignedIn => email != null;
  bool get hasUsage => windows.isNotEmpty;

  static const ClaudeAccountReading none = ClaudeAccountReading(windows: []);
}

/// Reads Claude subscription usage from Claude Code's own local state.
///
/// Anthropic publishes no OAuth flow a third-party app can register for, and no
/// public endpoint for subscription usage. What it does do is have Claude Code
/// fetch the user's utilization and cache it in `~/.claude.json`, a plain
/// config file in the user's home directory.
///
/// The figures here are **Anthropic's own**: `five_hour` and `seven_day`
/// utilization percentages, computed server-side and written verbatim. They are
/// not derived from transcripts, not measured against a budget, and not
/// calculated by this app.
///
/// What this deliberately does not do:
///
///  * read `~/.claude/.credentials.json`, which holds Claude Code's OAuth
///    tokens. Using those would mean presenting Claude Code's credentials as
///    this app's, which is a line this app does not cross,
///  * call any Anthropic endpoint on the user's behalf,
///  * scrape claude.ai.
///
/// It reads one config file the user owns, containing the user's own numbers.
class ClaudeAccountSource {
  ClaudeAccountSource({String? homeDirectory, Logger? logger})
      : _home = homeDirectory ?? Platform.environment['HOME'] ?? '',
        _log = logger ?? const Logger('claude.account');

  final String _home;
  final Logger _log;

  String get configPath => '$_home/.claude.json';

  /// True when Claude Code has been set up on this Mac.
  bool get isAvailable => File(configPath).existsSync();

  /// Fires whenever Claude Code rewrites its config.
  ///
  /// This is the *fallback* path. The live reading in [ClaudeLiveUsageSource]
  /// is what normally produces the figure; this file only carries whatever
  /// Claude Code last cached. Watching it still matters, because a rewrite is
  /// the earliest signal that the account's usage moved — it is what triggers
  /// the live re-fetch, rather than waiting for the next scheduled poll.
  ///
  /// Watching the modification time rather than using a filesystem event
  /// stream, because the file is replaced by an atomic rename — the inode the
  /// watcher attached to is discarded, and the events stop arriving after the
  /// first write.
  /// [interval] is a `stat` of one file, so it is cheap enough to run often.
  /// Two seconds is the difference between the rail agreeing with the CLI and
  /// visibly trailing it.
  Stream<DateTime> watch({
    Duration interval = const Duration(seconds: 2),
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
      final file = File(configPath);
      return file.existsSync() ? file.statSync().modified : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<ClaudeAccountReading> read() async {
    final file = File(configPath);
    if (!file.existsSync()) return ClaudeAccountReading.none;

    String contents;
    try {
      contents = await file.readAsString();
    } on FileSystemException catch (e) {
      _log.warn('could not read Claude config: ${e.osError?.message}');
      return ClaudeAccountReading.none;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      _log.warn('Claude config is not readable JSON');
      return ClaudeAccountReading.none;
    }
    if (decoded is! Map<String, dynamic>) return ClaudeAccountReading.none;

    return parse(decoded);
  }

  /// Extracts the account and usage from a decoded config.
  ///
  /// Separated from the file read so the parsing can be tested against
  /// recorded shapes without a filesystem.
  static ClaudeAccountReading parse(Map<String, dynamic> config) {
    final account = config['oauthAccount'];
    final email = account is Map<String, dynamic>
        ? account['emailAddress'] as String?
        : null;
    final displayName =
        account is Map<String, dynamic> ? account['displayName'] as String? : null;
    final plan = account is Map<String, dynamic>
        ? account['organizationType'] as String?
        : null;

    final cached = config['cachedUsageUtilization'];
    if (cached is! Map<String, dynamic>) {
      return ClaudeAccountReading(
        windows: const [],
        email: email,
        displayName: displayName,
        plan: plan,
      );
    }

    final fetchedAtMs = cached['fetchedAtMs'];
    final fetchedAt = fetchedAtMs is num
        ? DateTime.fromMillisecondsSinceEpoch(fetchedAtMs.toInt())
        : null;

    final utilization = cached['utilization'];
    final windows = <UsageWindow>[];

    if (utilization is Map<String, dynamic>) {
      // Only the two windows a person actually budgets against. The config
      // carries several codenamed buckets that are null for most accounts, and
      // an extra-usage bucket denominated in credits rather than percent —
      // all of it noise next to the session and the week.
      const named = {
        'five_hour': 'Current session',
        'seven_day': 'This week',
      };

      named.forEach((key, label) {
        final window = _window(utilization[key], id: key, label: label);
        if (window != null) windows.add(window);
      });
    }

    return ClaudeAccountReading(
      windows: windows,
      email: email,
      displayName: displayName,
      plan: plan,
      fetchedAt: fetchedAt,
    );
  }

  /// One utilization bucket as a window.
  ///
  /// Anthropic reports a whole percentage, so the window is expressed against
  /// 100 rather than against a token budget — there is no token limit involved
  /// and inventing one would be the mistake this replaces.
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
      // Anthropic computed this, not us. It arrives by way of a local cache
      // rather than a call this app made, which the card states.
      source: UsageSource.officialApi,
    );
  }

  /// A human label for the subscription tier.
  static String? planLabel(String? plan) => switch (plan) {
        'claude_pro' => 'Claude Pro',
        'claude_max' => 'Claude Max',
        'claude_team' => 'Claude Team',
        'claude_enterprise' => 'Claude Enterprise',
        null => null,
        _ => plan,
      };
}
