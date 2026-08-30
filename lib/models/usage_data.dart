import 'active_session.dart';
import 'connection_status.dart';
import 'usage_source.dart';
import 'usage_window.dart';

/// The complete, provider-agnostic snapshot the UI renders.
///
/// Every provider implementation produces one of these. No widget in this app
/// knows what "Claude" is — they all consume [UsageData].
class UsageData {
  const UsageData({
    required this.providerId,
    required this.providerName,
    required this.windows,
    required this.connection,
    required this.fetchedAt,
    this.sessions = const <ActiveSession>[],
    this.accountLabel,
    this.notes = const <String>[],
  });

  /// Stable provider key (`claude`).
  final String providerId;

  /// Display name ("Claude").
  final String providerName;

  /// Quota windows, most significant first. May be empty when unavailable.
  final List<UsageWindow> windows;

  /// Account-link state at the time of this fetch.
  final ConnectionStatus connection;

  /// When this snapshot was produced.
  final DateTime fetchedAt;

  /// Provider-related processes observed on this machine, most recently active
  /// first. Empty when nothing is running or nothing can be detected.
  final List<ActiveSession> sessions;

  /// Account or organisation name as reported by the provider, when it reports
  /// one.
  final String? accountLabel;

  /// Human-readable caveats worth surfacing (e.g. "Weekly budget not set").
  final List<String> notes;

  /// An empty snapshot used before the first successful fetch.
  factory UsageData.empty({
    required String providerId,
    required String providerName,
    ConnectionStatus connection = ConnectionStatus.notConnected,
  }) {
    return UsageData(
      providerId: providerId,
      providerName: providerName,
      windows: const [],
      connection: connection,
      fetchedAt: DateTime.now(),
    );
  }

  /// The window that drives the rail's ring.
  UsageWindow? get primaryWindow => windows.isEmpty ? null : windows.first;

  /// Rail percentage, or null when nothing is measurable.
  int? get primaryPercent => primaryWindow?.percentUsed;

  /// The session shown first — the busiest one, else the most recent.
  ActiveSession? get activeSession => sessions.isEmpty ? null : sessions.first;

  /// What this provider is doing locally right now.
  ///
  /// Reported as [ActivityStatus.unknown] rather than "idle" when the provider
  /// cannot see local activity at all, so an unwatchable provider is never
  /// misreported as quiet.
  ActivityStatus get activity {
    if (connection == ConnectionStatus.unsupported) {
      return ActivityStatus.unknown;
    }
    if (sessions.isEmpty) return ActivityStatus.idle;
    return sessions.any((s) => s.isBusy)
        ? ActivityStatus.working
        : ActivityStatus.waiting;
  }

  /// Weakest provenance across all windows — this is what the UI labels the
  /// card with, so a mixed snapshot is never over-claimed as authoritative.
  UsageSource get source {
    if (windows.isEmpty) return UsageSource.unavailable;
    if (windows.every((w) => w.source == UsageSource.providerReported)) {
      return UsageSource.providerReported;
    }
    if (windows.any((w) => w.source != UsageSource.unavailable)) {
      return UsageSource.localTracking;
    }
    return UsageSource.unavailable;
  }

  bool get hasUsage => windows.isNotEmpty;

  UsageWindow? windowById(String id) {
    for (final w in windows) {
      if (w.id == id) return w;
    }
    return null;
  }

  UsageData copyWith({
    List<UsageWindow>? windows,
    ConnectionStatus? connection,
    DateTime? fetchedAt,
    List<ActiveSession>? sessions,
    String? accountLabel,
    bool clearAccountLabel = false,
    List<String>? notes,
  }) {
    return UsageData(
      providerId: providerId,
      providerName: providerName,
      windows: windows ?? this.windows,
      connection: connection ?? this.connection,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      sessions: sessions ?? this.sessions,
      accountLabel:
          clearAccountLabel ? null : (accountLabel ?? this.accountLabel),
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() =>
      'UsageData($providerId, ${windows.length} windows, ${connection.name})';
}
