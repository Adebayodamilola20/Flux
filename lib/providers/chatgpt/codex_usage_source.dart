import 'dart:convert';
import 'dart:io';

import '../../core/logger.dart';
import '../../models/usage_source.dart';
import '../../models/usage_window.dart';

/// What Codex last recorded about the ChatGPT account's Codex allowance.
class CodexUsageReading {
  const CodexUsageReading({
    required this.windows,
    this.planType,
    this.observedAt,
  });

  final List<UsageWindow> windows;

  /// The plan Codex reported, e.g. `plus` or `free`.
  final String? planType;

  /// When Codex recorded these figures — the last time it ran, not now.
  final DateTime? observedAt;

  bool get hasUsage => windows.isNotEmpty;

  static const CodexUsageReading none = CodexUsageReading(windows: []);
}

/// Reads the Codex allowance OpenAI reports to its own CLI.
///
/// Codex records a `rate_limits` block in each session transcript, containing
/// figures OpenAI computed for the signed-in ChatGPT account. This reads the
/// most recent one.
///
/// **What the number is, precisely.** Across a real session history the
/// `limit_id` is `codex` with a `window_minutes` of 43200 — a rolling 30-day
/// window. That is the **Codex allowance attached to the ChatGPT plan**. It is
/// deliberately not conflated with either of the two things it is easy to
/// mistake it for:
///
///  * **ChatGPT chat limits** — a different product with no local record and no
///    public endpoint,
///  * **OpenAI API spend** — a separate billing account, read from the costs
///    endpoint and reported as its own window.
///
/// Only the `codex` bucket is read. A `premium` bucket also appears, but on the
/// accounts observed it carried no figures at all, and reporting an empty
/// bucket as 0% would be a fabricated number.
///
/// **Why this is not fetched live.** Claude's figure can be re-read on demand
/// because Anthropic exposes a usage endpoint. OpenAI does not: Codex learns
/// its remaining allowance from the reply to a model request, and there is no
/// separate endpoint to ask. Polling one would therefore mean *sending a
/// prompt* — spending the user's allowance in order to measure it. So this
/// reads the last figure OpenAI reported, refreshes the instant Codex records a
/// new one, and states how old it is rather than implying it is current.
///
/// Nothing here reads `~/.codex/auth.json`, which holds Codex's OAuth tokens.
class CodexUsageSource {
  CodexUsageSource({String? homeDirectory, Logger? logger})
      : _home = homeDirectory ?? Platform.environment['HOME'] ?? '',
        _log = logger ?? const Logger('codex.usage');

  /// The `limit_id` that corresponds to the Codex plan allowance.
  static const String codexLimitId = 'codex';

  /// How many recent session files to scan.
  ///
  /// The newest file does not always contain a rate-limit event — a session
  /// that ended before one arrived has none — so a few are checked rather than
  /// reporting "unavailable" because of one quiet session.
  static const int _filesToScan = 12;

  /// How much of the end of a transcript to read before falling back to the
  /// whole file.
  ///
  /// Codex writes a rate-limit event after each turn, so the newest one is at
  /// the end. Transcripts reach several megabytes, and this runs on a timer —
  /// reading the tail keeps a routine refresh to a few kilobytes of I/O.
  static const int _tailBytes = 256 * 1024;

  final String _home;
  final Logger _log;

  String get sessionsPath => '$_home/.codex/sessions';

  bool get isAvailable => Directory(sessionsPath).existsSync();

  /// Fires when Codex records a new session event.
  ///
  /// Codex appends to the transcript as it works, so the directory's newest
  /// modification time moves the moment a fresh allowance is written. Watching
  /// it is what lets the card update when the user runs Codex, instead of at
  /// the next scheduled poll.
  Stream<DateTime> watch({
    Duration interval = const Duration(seconds: 5),
  }) async* {
    DateTime? last = await _newestModification();

    while (true) {
      await Future<void>.delayed(interval);
      final current = await _newestModification();
      if (current == null) continue;
      if (last == null || current.isAfter(last)) {
        last = current;
        yield current;
      }
    }
  }

  Future<DateTime?> _newestModification() async {
    final files = await _recentFiles();
    return files.isEmpty ? null : files.first.statSync().modified;
  }

  /// Transcripts, newest first.
  Future<List<File>> _recentFiles() async {
    final directory = Directory(sessionsPath);
    if (!directory.existsSync()) return const [];

    final files = <File>[];
    try {
      await for (final entry in directory.list(recursive: true)) {
        if (entry is File && entry.path.endsWith('.jsonl')) files.add(entry);
      }
    } on FileSystemException catch (e) {
      _log.warn('could not list Codex sessions: ${e.osError?.message}');
      return const [];
    }

    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  Future<CodexUsageReading> read() async {
    for (final file in (await _recentFiles()).take(_filesToScan)) {
      final reading = await _readFile(file);
      if (reading != null) return reading;
    }

    return CodexUsageReading.none;
  }

  /// The last rate-limit event in one transcript, if it has one.
  Future<CodexUsageReading?> _readFile(File file) async {
    var contents = await _readTail(file);

    // A tail that happens to contain no rate-limit event is not proof the file
    // has none — a long turn can push the last one out of the window.
    if (contents != null && !contents.contains('"rate_limits"')) {
      contents = null;
    }

    if (contents == null) {
      try {
        contents = await file.readAsString();
      } on FileSystemException {
        return null;
      }
    }

    Map<String, dynamic>? latest;
    String? latestTimestamp;

    for (final line in const LineSplitter().convert(contents)) {
      // Cheap reject before paying for a JSON parse on a large transcript.
      if (!line.contains('"rate_limits"')) continue;

      Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, dynamic>) continue;

      final payload = decoded['payload'];
      if (payload is! Map<String, dynamic>) continue;
      final limits = payload['rate_limits'];
      if (limits is! Map<String, dynamic>) continue;

      // Only the Codex bucket carries the plan allowance.
      if (limits['limit_id'] != codexLimitId) continue;

      latest = limits;
      latestTimestamp = decoded['timestamp'] as String?;
    }

    if (latest == null) return null;
    return parse(latest, timestamp: latestTimestamp);
  }

  /// The last [_tailBytes] of a file, aligned to a line boundary.
  ///
  /// Returns null when the file is small enough to read whole, or when the tail
  /// cannot be read — both mean "fall back to reading all of it". The leading
  /// partial line is dropped, because half a JSON object is not parseable and
  /// would otherwise be counted as a malformed record.
  Future<String?> _readTail(File file) async {
    RandomAccessFile? handle;
    try {
      final length = await file.length();
      if (length <= _tailBytes) return null;

      handle = await file.open();
      await handle.setPosition(length - _tailBytes);
      final bytes = await handle.read(_tailBytes);

      final text = utf8.decode(bytes, allowMalformed: true);
      final firstBreak = text.indexOf('\n');
      return firstBreak == -1 ? null : text.substring(firstBreak + 1);
    } on FileSystemException {
      return null;
    } finally {
      await handle?.close();
    }
  }

  /// Turns one `rate_limits` block into windows.
  ///
  /// Exposed for tests so the shape can be exercised without a filesystem.
  static CodexUsageReading parse(
    Map<String, dynamic> limits, {
    String? timestamp,
  }) {
    final observedAt =
        timestamp == null ? null : DateTime.tryParse(timestamp)?.toLocal();
    final windows = <UsageWindow>[];

    for (final key in const ['primary', 'secondary']) {
      final window = _window(limits[key], key: key, observedAt: observedAt);
      if (window != null) windows.add(window);
    }

    return CodexUsageReading(
      windows: windows,
      planType: limits['plan_type'] as String?,
      observedAt: observedAt,
    );
  }

  static UsageWindow? _window(
    Object? bucket, {
    required String key,
    DateTime? observedAt,
  }) {
    if (bucket is! Map<String, dynamic>) return null;

    final used = bucket['used_percent'];
    if (used is! num) return null;

    final minutes = bucket['window_minutes'];
    final resets = bucket['resets_at'];

    return UsageWindow(
      id: 'codex_$key',
      label: minutes is num
          ? 'Codex allowance (${_windowLabel(minutes)})'
          : 'Codex allowance',
      consumed: used.clamp(0, 100),
      limit: 100,
      unit: '%',
      resetsAt: resets is num
          ? DateTime.fromMillisecondsSinceEpoch(resets.toInt() * 1000)
          : null,
      // When OpenAI measured this, not when we read the file. A free-plan
      // allowance sitting at 100% since yesterday must not read as current.
      observedAt: observedAt,
      // OpenAI computed this for the account; it reaches us through Codex's
      // own transcript rather than a call this app made.
      source: UsageSource.officialApi,
    );
  }

  /// `43200` minutes reads as "30 days", not as a number of minutes.
  static String _windowLabel(num minutes) {
    if (minutes >= 1440 && minutes % 1440 == 0) {
      final days = minutes ~/ 1440;
      return days == 1 ? '1 day' : '$days days';
    }
    if (minutes >= 60 && minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    return '${minutes.toInt()} min';
  }

  /// A human label for the ChatGPT plan Codex reported.
  static String? planLabel(String? plan) => switch (plan) {
        'free' => 'ChatGPT Free',
        'plus' => 'ChatGPT Plus',
        'pro' => 'ChatGPT Pro',
        'team' => 'ChatGPT Team',
        'enterprise' => 'ChatGPT Enterprise',
        null => null,
        _ => plan,
      };
}
