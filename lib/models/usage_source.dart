/// Where a piece of usage information actually came from.
///
/// The UI must always be able to tell the user whether a number is authoritative
/// (reported by the provider itself) or derived locally by this app. We never
/// present a locally derived estimate as if the provider had blessed it.
enum UsageSource {
  /// The provider's own API reported these numbers.
  providerReported,

  /// Derived on this machine from local artifacts (e.g. CLI session logs).
  /// Accurate for what happened on this Mac; blind to usage elsewhere.
  localTracking,

  /// Nothing could be determined.
  unavailable;

  bool get isAuthoritative => this == UsageSource.providerReported;

  String get label => switch (this) {
        UsageSource.providerReported => 'Provider reported',
        UsageSource.localTracking => 'Local tracking',
        UsageSource.unavailable => 'Unavailable',
      };

  /// Short caption shown under the usage card.
  String get caption => switch (this) {
        UsageSource.providerReported => 'Reported by provider',
        UsageSource.localTracking => 'Tracked locally on this Mac',
        UsageSource.unavailable => 'No usage source available',
      };
}
