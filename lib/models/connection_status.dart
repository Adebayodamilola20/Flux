/// Whether this app has a working link to a provider's account.
///
/// This describes the *link*, not what the user is doing right now — activity
/// is [ActivityStatus]. Keeping the two apart is what lets the UI say
/// "Connected · idle" without either word contradicting the other.
enum ConnectionStatus {
  /// The user has not connected this provider yet.
  notConnected,

  /// Authentication or the first fetch is in flight.
  connecting,

  /// Linked, and the provider itself is reporting usage.
  connected,

  /// Usable, but only locally tracked figures are available — no
  /// provider-reported numbers. Honest middle ground, never dressed up as
  /// [connected].
  limited,

  /// The last attempt failed.
  error,

  /// A reserved provider slot with no implementation in this build.
  unsupported;

  bool get isBusy => this == ConnectionStatus.connecting;

  /// True when the provider can produce usage of some kind.
  bool get isHealthy =>
      this == ConnectionStatus.connected || this == ConnectionStatus.limited;

  /// True when the user still has to do something to link this provider.
  bool get needsSetup =>
      this == ConnectionStatus.notConnected || this == ConnectionStatus.error;

  /// True when the slot should be shown but not offered for connection.
  bool get isReserved => this == ConnectionStatus.unsupported;

  String get label => switch (this) {
        ConnectionStatus.notConnected => 'Not connected',
        ConnectionStatus.connecting => 'Connecting…',
        ConnectionStatus.connected => 'Connected',
        ConnectionStatus.limited => 'Local only',
        ConnectionStatus.error => 'Disconnected',
        ConnectionStatus.unsupported => 'Coming soon',
      };

  /// Longer form used on the onboarding cards, where there is room to explain.
  String get detail => switch (this) {
        ConnectionStatus.notConnected => 'Not connected',
        ConnectionStatus.connecting => 'Waiting for authentication…',
        ConnectionStatus.connected => 'Reporting usage',
        ConnectionStatus.limited => 'Tracking locally on this Mac',
        ConnectionStatus.error => 'Connection failed',
        ConnectionStatus.unsupported => 'Not available in this version',
      };
}

/// What a provider is doing on this machine right now.
///
/// Derived from observed local processes and session transcripts, never from
/// the provider's servers.
enum ActivityStatus {
  /// Nothing of this provider's is running locally.
  idle,

  /// A CLI session for this provider is running and recently active.
  working,

  /// Running, but with no recent activity.
  waiting,

  /// Activity cannot be determined.
  unknown;

  String get label => switch (this) {
        ActivityStatus.idle => 'Idle',
        ActivityStatus.working => 'Working',
        ActivityStatus.waiting => 'Waiting',
        ActivityStatus.unknown => 'Unknown',
      };

  bool get isActive =>
      this == ActivityStatus.working || this == ActivityStatus.waiting;
}
