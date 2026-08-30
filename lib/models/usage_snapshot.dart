import 'usage_data.dart';
import 'usage_source.dart';

/// A point-in-time record kept for the local history view.
///
/// Deliberately small: just enough to draw a sparkline and say where the number
/// came from. Stored on disk, so it must round-trip through JSON.
class UsageSnapshot {
  const UsageSnapshot({
    required this.takenAt,
    required this.providerId,
    required this.windowId,
    required this.consumed,
    required this.source,
    this.limit,
    this.percent,
  });

  final DateTime takenAt;
  final String providerId;
  final String windowId;
  final num consumed;
  final num? limit;
  final int? percent;
  final UsageSource source;

  /// Builds snapshots for every measurable window in [data].
  static List<UsageSnapshot> fromUsage(UsageData data) {
    return [
      for (final w in data.windows)
        UsageSnapshot(
          takenAt: data.fetchedAt,
          providerId: data.providerId,
          windowId: w.id,
          consumed: w.consumed,
          limit: w.limit,
          percent: w.percentUsed,
          source: w.source,
        ),
    ];
  }

  Map<String, dynamic> toJson() => {
        'takenAt': takenAt.toIso8601String(),
        'providerId': providerId,
        'windowId': windowId,
        'consumed': consumed,
        'limit': limit,
        'percent': percent,
        'source': source.name,
      };

  static UsageSnapshot? fromJson(Map<String, dynamic> json) {
    final takenAt = switch (json['takenAt']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    };
    final providerId = json['providerId'];
    final windowId = json['windowId'];
    if (takenAt == null || providerId is! String || windowId is! String) {
      return null;
    }
    return UsageSnapshot(
      takenAt: takenAt,
      providerId: providerId,
      windowId: windowId,
      consumed: (json['consumed'] as num?) ?? 0,
      limit: json['limit'] as num?,
      percent: json['percent'] as int?,
      source: UsageSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => UsageSource.unavailable,
      ),
    );
  }

  @override
  String toString() =>
      'UsageSnapshot($providerId/$windowId, $percent%, $takenAt)';
}
