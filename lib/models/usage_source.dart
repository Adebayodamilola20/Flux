/// Where a piece of usage information actually came from.
///
/// The UI must always be able to say how much a number is worth. These values
/// are ordered by authority, and the distinction that matters most is between
/// everything a provider told us ([officialApi], [officialCli],
/// [interactiveCli]) and the one value we worked out ourselves
/// ([localTracking]). A locally derived estimate is never presented as if the
/// provider had blessed it.
enum UsageSource {
  /// The provider's own documented API reported these numbers.
  officialApi,

  /// The provider's own CLI reported these numbers through a supported,
  /// machine-readable output mode — a `--json` flag or similar.
  officialCli,

  /// Read from the provider's own CLI, but out of an interactive panel that
  /// the CLI draws for the authenticated user. The figures are the provider's;
  /// the extraction is ours, so a layout change can break it in ways an API
  /// contract would not.
  interactiveCli,

  /// Derived on this machine from local artifacts (e.g. CLI session logs).
  /// Accurate for what happened on this Mac; blind to usage elsewhere, and
  /// measured against a budget the user set rather than a published limit.
  localTracking,

  /// Nothing could be determined.
  unavailable;

  /// True when the provider itself produced the figure, by any route.
  ///
  /// This is the test for "may be shown as a quota". Everything else is an
  /// estimate and has to be labelled as one.
  bool get isProviderReported =>
      this == UsageSource.officialApi ||
      this == UsageSource.officialCli ||
      this == UsageSource.interactiveCli;

  /// True only for sources with a stable contract behind them.
  bool get isAuthoritative =>
      this == UsageSource.officialApi || this == UsageSource.officialCli;

  /// How much to trust this, highest first. Used to order windows and to pick
  /// the weakest source when a snapshot mixes several.
  int get rank => switch (this) {
        UsageSource.officialApi => 0,
        UsageSource.officialCli => 1,
        UsageSource.interactiveCli => 2,
        UsageSource.localTracking => 3,
        UsageSource.unavailable => 4,
      };

  String get label => switch (this) {
        UsageSource.officialApi => 'Official API',
        UsageSource.officialCli => 'Official CLI',
        UsageSource.interactiveCli => 'CLI usage panel',
        UsageSource.localTracking => 'Local tracking',
        UsageSource.unavailable => 'Unavailable',
      };

  /// Short caption shown under the usage card.
  String get caption => switch (this) {
        UsageSource.officialApi => 'Reported by the provider’s API',
        UsageSource.officialCli => 'Reported by the provider’s CLI',
        UsageSource.interactiveCli => 'Read from the provider’s usage panel',
        UsageSource.localTracking => 'Estimated on this Mac',
        UsageSource.unavailable => 'No usage source available',
      };

  /// Parses a persisted value, tolerating records written before this
  /// taxonomy replaced the older three-value one.
  static UsageSource fromName(Object? name) {
    for (final source in UsageSource.values) {
      if (source.name == name) return source;
    }
    // `providerReported` was the old catch-all for anything the provider said.
    // Mapping it to the API is the safe reading: it was only ever produced by
    // the Anthropic API path.
    if (name == 'providerReported') return UsageSource.officialApi;
    return UsageSource.unavailable;
  }
}
