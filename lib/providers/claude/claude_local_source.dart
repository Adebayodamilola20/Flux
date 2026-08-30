import 'dart:io';
import 'dart:isolate';

import '../../core/logger.dart';
import '../../models/app_settings.dart';
import '../../models/usage_source.dart';
import '../../models/usage_window.dart';
import 'transcript_scanner.dart';

/// Usage derived from Claude Code's own local session transcripts.
///
/// This is *local tracking*, not a provider-reported figure: it sees only work
/// done through Claude Code on this Mac, and the percentage is measured against
/// a user-configurable token budget rather than a published plan limit. Every
/// window it produces is labelled [UsageSource.localTracking] so the UI can say
/// so plainly.
class ClaudeLocalSource {
  ClaudeLocalSource({String? claudeHome, Logger? logger})
      : _claudeHome = claudeHome ?? defaultClaudeHome(),
        _log = logger ?? const Logger('claude.local');

  /// Claude's documented rolling session length.
  static const Duration sessionWindow = Duration(hours: 5);
  static const Duration weeklyWindow = Duration(days: 7);

  final String _claudeHome;
  final Logger _log;

  /// Byte offsets per transcript file, so each refresh re-reads only what was
  /// appended since the previous pass.
  final Map<String, int> _cursors = {};

  /// Events inside the retention window, keyed by uuid for deduplication.
  final Map<String, TranscriptEvent> _events = {};

  String get projectsPath => '$_claudeHome/projects';

  static String defaultClaudeHome() {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.claude';
  }

  /// True when there is a Claude Code transcript directory to read.
  bool get isAvailable => Directory(projectsPath).existsSync();

  /// Refreshes the event cache and computes the session and weekly windows.
  ///
  /// The filesystem scan runs on a background isolate; the UI isolate only ever
  /// sees the aggregated result.
  Future<ClaudeLocalUsage> load(AppSettings settings) async {
    final now = DateTime.now();
    final retentionStart = now.subtract(weeklyWindow);

    final request = ScanRequest(
      rootPath: projectsPath,
      cursors: Map.of(_cursors),
      notBefore: retentionStart,
    );

    final result = await Isolate.run(() => scanTranscripts(request));

    for (final cursor in result.cursors) {
      _cursors[cursor.path] = cursor.offset;
    }
    for (final event in result.events) {
      _events[event.id] = event;
    }
    // Drop anything that has aged out so memory stays bounded.
    _events.removeWhere((_, e) => e.timestamp.isBefore(retentionStart));

    _log.debug(
      'scanned ${result.cursors.length} transcripts, '
      '${result.events.length} new events, ${_events.length} retained',
    );

    final events = _events.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return ClaudeLocalUsage(
      windows: [
        _sessionWindow(events, now, settings.sessionTokenBudget),
        _weeklyWindow(events, now, settings.weeklyTokenBudget),
      ],
      latestEvent: events.isEmpty ? null : events.last,
    );
  }

  /// The current rolling 5-hour block.
  ///
  /// Blocks are anchored to the top of the hour in which their first turn
  /// occurred and run for five hours, matching how Claude describes session
  /// windows. Turns that fall outside the active block start a new one.
  UsageWindow _sessionWindow(
    List<TranscriptEvent> events,
    DateTime now,
    int budget,
  ) {
    DateTime? blockStart;
    var consumed = 0;

    for (final event in events) {
      final start = blockStart;
      if (start == null || event.timestamp.difference(start) >= sessionWindow) {
        blockStart = _floorToHour(event.timestamp);
        consumed = event.tokens;
      } else {
        consumed += event.tokens;
      }
    }

    // The last block found may already have expired.
    final start = blockStart;
    if (start == null || now.difference(start) >= sessionWindow) {
      return UsageWindow(
        id: sessionWindowId,
        label: 'Current session',
        consumed: 0,
        limit: budget,
        source: UsageSource.localTracking,
        resetsAt: null,
      );
    }

    return UsageWindow(
      id: sessionWindowId,
      label: 'Current session',
      consumed: consumed,
      limit: budget,
      source: UsageSource.localTracking,
      resetsAt: start.add(sessionWindow),
    );
  }

  /// A rolling 7-day window. It resets progressively as old turns age out, so
  /// the reported reset time is when the oldest counted turn leaves the window.
  UsageWindow _weeklyWindow(
    List<TranscriptEvent> events,
    DateTime now,
    int budget,
  ) {
    final start = now.subtract(weeklyWindow);
    var consumed = 0;
    DateTime? oldest;

    for (final event in events) {
      if (event.timestamp.isBefore(start)) continue;
      consumed += event.tokens;
      oldest ??= event.timestamp;
    }

    return UsageWindow(
      id: weeklyWindowId,
      label: 'All models',
      consumed: consumed,
      limit: budget,
      source: UsageSource.localTracking,
      resetsAt: oldest?.add(weeklyWindow),
    );
  }

  static DateTime _floorToHour(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour);

  static const String sessionWindowId = 'session';
  static const String weeklyWindowId = 'weekly';
}

/// Aggregated result of one local scan.
class ClaudeLocalUsage {
  const ClaudeLocalUsage({required this.windows, this.latestEvent});

  final List<UsageWindow> windows;

  /// Most recent turn seen anywhere on this machine, used to describe the
  /// active session in the UI.
  final TranscriptEvent? latestEvent;
}
