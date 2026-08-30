import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/logger.dart';
import '../models/usage_data.dart';
import '../models/usage_snapshot.dart';

/// Local, cloud-free storage of usage snapshots.
///
/// Snapshots are appended on refresh and pruned by both age and count so the
/// store stays small. Nothing leaves the machine.
class HistoryService {
  HistoryService({
    required SharedPreferences preferences,
    Logger? logger,
    this.retention = const Duration(days: 7),
    this.maxEntries = 720,
    this.minimumInterval = const Duration(minutes: 5),
  })  : _prefs = preferences,
        _log = logger ?? const Logger('history');

  static const String _storageKey = 'usage_history_v1';

  final SharedPreferences _prefs;
  final Logger _log;

  /// Snapshots older than this are dropped.
  final Duration retention;

  /// Hard cap on stored snapshots, as a backstop against unbounded growth.
  final int maxEntries;

  /// Snapshots closer together than this are skipped, so a burst of manual
  /// refreshes does not flood the history.
  final Duration minimumInterval;

  List<UsageSnapshot> _entries = [];
  bool _loaded = false;

  Future<List<UsageSnapshot>> load() async {
    if (_loaded) return _entries;

    final raw = _prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _entries = decoded
              .whereType<Map<String, dynamic>>()
              .map(UsageSnapshot.fromJson)
              .whereType<UsageSnapshot>()
              .toList();
        }
      } on FormatException catch (e) {
        _log.warn('discarding unreadable history: ${e.message}');
        _entries = [];
      }
    }

    _loaded = true;
    _prune();
    return _entries;
  }

  /// Records [data], unless a snapshot was taken very recently.
  Future<void> record(UsageData data) async {
    await load();

    final last = _lastFor(data.providerId);
    if (last != null &&
        data.fetchedAt.difference(last.takenAt).abs() < minimumInterval) {
      return;
    }

    final additions = UsageSnapshot.fromUsage(data);
    if (additions.isEmpty) return;

    _entries.addAll(additions);
    _prune();
    await _persist();
  }

  /// Snapshots for one window, oldest first.
  Future<List<UsageSnapshot>> seriesFor({
    required String providerId,
    required String windowId,
  }) async {
    final all = await load();
    return all
        .where((s) => s.providerId == providerId && s.windowId == windowId)
        .toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  }

  Future<void> clear() async {
    _entries = [];
    _loaded = true;
    await _prefs.remove(_storageKey);
  }

  UsageSnapshot? _lastFor(String providerId) {
    UsageSnapshot? latest;
    for (final entry in _entries) {
      if (entry.providerId != providerId) continue;
      if (latest == null || entry.takenAt.isAfter(latest.takenAt)) {
        latest = entry;
      }
    }
    return latest;
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(retention);
    _entries.removeWhere((e) => e.takenAt.isBefore(cutoff));
    _entries.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    if (_entries.length > maxEntries) {
      _entries = _entries.sublist(_entries.length - maxEntries);
    }
  }

  Future<void> _persist() async {
    final encoded = jsonEncode([for (final e in _entries) e.toJson()]);
    await _prefs.setString(_storageKey, encoded);
  }
}
