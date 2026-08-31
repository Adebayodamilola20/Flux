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
    this.usageUnavailableReason,
    this.usageUnavailableIsPermanent = false,
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

  /// Why there are no [windows], when the account is connected and nothing
  /// went wrong.
  ///
  /// A connected provider that publishes no readable quota is a normal state,
  /// not an error: the user has done everything right and has nothing to fix.
  /// Carrying the reason here lets the card say "Connected · Usage
  /// unavailable" and still show local activity, instead of the whole snapshot
  /// being replaced by a failure.
  final String? usageUnavailableReason;

  /// True when the provider publishes no such data at all, so trying again
  /// cannot change the answer.
  ///
  /// The difference matters in the UI: a temporary gap deserves a Retry, and a
  /// structural one deserves an explanation. Offering Retry against an
  /// endpoint that does not exist just invites the user to press it forever.
  final bool usageUnavailableIsPermanent;

  /// True when the provider is connected but had no quota to report.
  bool get isUsageUnavailable =>
      windows.isEmpty && usageUnavailableReason != null;

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
    // The weakest source in the set. A snapshot is only as trustworthy as its
    // least trustworthy number, and labelling it by the best one would let a
    // single official figure launder the estimates sitting beside it.
    return windows
        .map((w) => w.source)
        .reduce((a, b) => a.rank >= b.rank ? a : b);
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
    String? usageUnavailableReason,
    bool? usageUnavailableIsPermanent,
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
      usageUnavailableReason:
          usageUnavailableReason ?? this.usageUnavailableReason,
      usageUnavailableIsPermanent:
          usageUnavailableIsPermanent ?? this.usageUnavailableIsPermanent,
    );
  }

  @override
  String toString() =>
      'UsageData($providerId, ${windows.length} windows, ${connection.name})';
}
