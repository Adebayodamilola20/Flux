import 'usage_source.dart';

/// One measured quota window for a provider — e.g. Claude's rolling 5-hour
/// session window, or a weekly all-models window.
///
/// A window is deliberately generic: any provider can express its quotas as a
/// list of these, and the UI renders them without knowing which provider it is
/// looking at.
class UsageWindow {
  const UsageWindow({
    required this.id,
    required this.label,
    required this.consumed,
    required this.source,
    this.limit,
    this.unit = 'tokens',
    this.resetsAt,
    this.observedAt,
  });

  /// Stable identifier, unique within a provider (`session`, `weekly`, …).
  final String id;

  /// Human label shown in the UI ("Current session").
  final String label;

  /// Amount consumed so far in this window, in [unit].
  final num consumed;

  /// Ceiling for this window, in [unit]. Null when no limit is known.
  final num? limit;

  /// Unit of [consumed] and [limit].
  final String unit;

  /// When this window rolls over. Null when unknown.
  final DateTime? resetsAt;

  /// When the *provider* measured this, which is not always when the app
  /// fetched it.
  ///
  /// The distinction matters wherever a figure cannot be asked for on demand.
  /// OpenAI reports the Codex allowance only in the reply to a model request,
  /// so the newest figure available may be days old — and "100% Used" shown
  /// without that context reads as current, which is the same failure as
  /// showing a stale cache and calling it live.
  ///
  /// Null when the reading is taken at fetch time, which is the common case.
  final DateTime? observedAt;

  /// True when this figure is old enough that saying so matters.
  ///
  /// A few minutes is noise; an hour is a different number.
  bool get isStale {
    final at = observedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) > const Duration(minutes: 15);
  }

  /// Provenance of these specific numbers.
  final UsageSource source;

  /// Fraction used in `0.0 – 1.0`, or null when no limit is known.
  ///
  /// Clamped at 1.0 so an over-budget window renders as a full bar rather than
  /// overflowing the progress track.
  double? get fractionUsed {
    final l = limit;
    if (l == null || l <= 0) return null;
    final raw = consumed / l;
    if (raw.isNaN || raw.isInfinite) return null;
    return raw.clamp(0.0, 1.0).toDouble();
  }

  /// Whole-percent value in `0 – 100`, or null when no limit is known.
  int? get percentUsed {
    final f = fractionUsed;
    return f == null ? null : (f * 100).round();
  }

  /// True once the window is close enough to its limit to warrant a warning
  /// colour in the UI.
  bool get isNearLimit => (fractionUsed ?? 0) >= 0.8;

  /// True once the window is effectively exhausted.
  bool get isExhausted => (fractionUsed ?? 0) >= 1.0;

  UsageWindow copyWith({
    String? id,
    String? label,
    num? consumed,
    num? limit,
    String? unit,
    DateTime? resetsAt,
    UsageSource? source,
  }) {
    return UsageWindow(
      id: id ?? this.id,
      label: label ?? this.label,
      consumed: consumed ?? this.consumed,
      limit: limit ?? this.limit,
      unit: unit ?? this.unit,
      resetsAt: resetsAt ?? this.resetsAt,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'consumed': consumed,
        'limit': limit,
        'unit': unit,
        'resetsAt': resetsAt?.toIso8601String(),
        'source': source.name,
      };

  static UsageWindow fromJson(Map<String, dynamic> json) {
    return UsageWindow(
      id: json['id'] as String,
      label: json['label'] as String,
      consumed: (json['consumed'] as num?) ?? 0,
      limit: json['limit'] as num?,
      unit: (json['unit'] as String?) ?? 'tokens',
      resetsAt: switch (json['resetsAt']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
      source: UsageSource.fromName(json['source']),
    );
  }

  @override
  String toString() =>
      'UsageWindow($id, $consumed/$limit $unit, ${source.name})';

  @override
  bool operator ==(Object other) =>
      other is UsageWindow &&
      other.id == id &&
      other.label == label &&
      other.consumed == consumed &&
      other.limit == limit &&
      other.unit == unit &&
      other.resetsAt == resetsAt &&
      other.source == source;

  @override
  int get hashCode =>
      Object.hash(id, label, consumed, limit, unit, resetsAt, source);
}
