/// Why a usage fetch could not produce data.
enum UsageFailureKind {
  /// No local artifacts and no configured API — nothing to read.
  notConfigured,

  /// Network request failed or timed out.
  network,

  /// Credentials rejected by the provider.
  authentication,

  /// Provider returned a rate-limit response.
  rateLimited,

  /// Local files exist but could not be read (permissions, corruption).
  localRead,

  /// Anything else.
  unknown;

  String get title => switch (this) {
        UsageFailureKind.notConfigured => 'Not configured',
        UsageFailureKind.network => 'Connection failed',
        UsageFailureKind.authentication => 'Authentication failed',
        UsageFailureKind.rateLimited => 'Rate limited',
        UsageFailureKind.localRead => 'Could not read local data',
        UsageFailureKind.unknown => 'Something went wrong',
      };
}

/// A structured, user-presentable failure. Carries no credentials — the
/// [message] is safe to render and to log.
class UsageFailure implements Exception {
  const UsageFailure(this.kind, this.message, {this.hint});

  final UsageFailureKind kind;

  /// Short explanation shown in the error state.
  final String message;

  /// Optional actionable next step ("Open Settings to add an admin key").
  final String? hint;

  /// True when retrying without user intervention could plausibly succeed.
  bool get isRetryable => switch (kind) {
        UsageFailureKind.network ||
        UsageFailureKind.rateLimited ||
        UsageFailureKind.unknown =>
          true,
        UsageFailureKind.notConfigured ||
        UsageFailureKind.authentication ||
        UsageFailureKind.localRead =>
          false,
      };

  @override
  String toString() => 'UsageFailure(${kind.name}): $message';
}
