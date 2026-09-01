import 'connection_status.dart';

/// How a provider expects to be authenticated.
///
/// The app never invents a mechanism a provider does not offer. Where a
/// provider has no suitable public mechanism for reading personal usage, the
/// slot is declared [ProviderAuthMethod.unavailable] rather than papered over
/// with scraping or token extraction.
enum ProviderAuthMethod {
  /// A real OAuth authorisation-code flow: the browser opens the provider's
  /// own login page and the result comes back over a registered URL scheme.
  browserOAuth,

  /// The provider issues long-lived API keys from a console the user visits in
  /// their browser. The app opens that page and accepts the *key* — never a
  /// password — and stores it in the macOS Keychain.
  consoleApiKey,

  /// The provider's own CLI holds the session. Connecting means confirming
  /// that CLI is installed and signed in — and, if it is not, letting it run
  /// its own sign-in, which opens the provider's consent page in the browser.
  /// This app never handles the exchange or the resulting token.
  cliSession,

  /// The provider offers no account sign-in this app can use, but useful
  /// information about it can still be observed locally.
  ///
  /// Nothing to connect and nothing to configure: the app reports what is
  /// running on this Mac and is explicit that account-level usage is not
  /// available. Any optional credential lives in Settings, not in front of a
  /// user who just wants the product to work.
  localActivityOnly,

  /// No account link is needed; figures are derived from local artifacts this
  /// machine already owns.
  localOnly,

  /// The provider offers no legitimate mechanism for this use case yet.
  unavailable;

  String get callToAction => switch (this) {
    ProviderAuthMethod.browserOAuth => 'Connect',
    ProviderAuthMethod.consoleApiKey => 'Connect',
    ProviderAuthMethod.cliSession => 'Connect',
    ProviderAuthMethod.localActivityOnly => 'No sign-in needed',
    ProviderAuthMethod.localOnly => 'Enable',
    ProviderAuthMethod.unavailable => 'Unavailable',
  };

  /// Explains, on the card itself, what clicking the button will do — so the
  /// browser opening is never a surprise.
  String get explanation => switch (this) {
    ProviderAuthMethod.browserOAuth =>
      'Opens the provider’s sign-in page in your browser.',
    ProviderAuthMethod.consoleApiKey =>
      'Opens the provider’s own site so you can create a key, then paste it '
          'back here. A key, never a password.',
    ProviderAuthMethod.cliSession =>
      'Uses the sign-in already held by the provider’s own CLI. If it is '
          'signed out, the CLI opens its own sign-in page.',
    ProviderAuthMethod.localActivityOnly =>
      'This provider offers no account sign-in for reading usage, so there is '
          'nothing to connect. Sessions running on this Mac are detected '
          'automatically.',
    ProviderAuthMethod.localOnly =>
      'Reads usage from files already on this Mac. No sign-in needed.',
    ProviderAuthMethod.unavailable =>
      'This provider has no supported way to report personal usage yet.',
  };
}

/// The persisted state of one provider's account link.
///
/// Holds no secret material. Credentials live in the macOS Keychain and are
/// referenced only by the provider that owns them.
class ProviderConnection {
  const ProviderConnection({
    required this.providerId,
    required this.status,
    this.accountLabel,
    this.accountId,
    this.accountChangedAt,
    this.connectedAt,
    this.message,
    this.usesStoredKey = false,
  });

  final String providerId;
  final ConnectionStatus status;

  /// Whether this link is backed by a credential in the Keychain.
  ///
  /// False for a link made from what is already on this Mac — a signed-in CLI,
  /// a local transcript — which has no secret of its own and never did. The
  /// distinction has to be persisted: on restore, a key-backed link whose key
  /// has gone is genuinely broken, while a keyless one is working exactly as
  /// designed. Judging both by the same missing-key test is what silently
  /// unlinked Codex on every launch.
  final bool usesStoredKey;

  /// Something the user recognises — an organisation or account name reported
  /// by the provider. Never an email guessed by the app.
  final String? accountLabel;

  /// The provider's own identifier for the linked account, when it has one.
  ///
  /// Opaque, and never a credential: its only job is to let a provider tell
  /// "the same account as last time" from "somebody signed in as someone else",
  /// which is not otherwise answerable from figures alone. Persisted, because a
  /// switch that happened while the app was closed still has to be noticed.
  final String? accountId;

  /// When [accountId] was first seen.
  ///
  /// A provider whose figures come from local records uses this as a cut-off:
  /// anything recorded earlier belongs to a previous sign-in and is not this
  /// account's usage.
  final DateTime? accountChangedAt;

  final DateTime? connectedAt;

  /// Why the connection is in this state, when there is something worth saying.
  final String? message;

  factory ProviderConnection.notConnected(String providerId) =>
      ProviderConnection(
        providerId: providerId,
        status: ConnectionStatus.notConnected,
      );

  factory ProviderConnection.unsupported(String providerId) =>
      ProviderConnection(
        providerId: providerId,
        status: ConnectionStatus.unsupported,
      );

  bool get isConnected => status.isHealthy;

  ProviderConnection copyWith({
    ConnectionStatus? status,
    String? accountLabel,
    String? accountId,
    DateTime? accountChangedAt,
    DateTime? connectedAt,
    String? message,
    bool clearMessage = false,
    bool clearAccountLabel = false,
    bool? usesStoredKey,
  }) {
    return ProviderConnection(
      providerId: providerId,
      status: status ?? this.status,
      usesStoredKey: usesStoredKey ?? this.usesStoredKey,
      accountLabel: clearAccountLabel
          ? null
          : (accountLabel ?? this.accountLabel),
      accountId: accountId ?? this.accountId,
      accountChangedAt: accountChangedAt ?? this.accountChangedAt,
      connectedAt: connectedAt ?? this.connectedAt,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'status': status.name,
    'accountLabel': accountLabel,
    'accountId': accountId,
    'accountChangedAt': accountChangedAt?.toIso8601String(),
    'connectedAt': connectedAt?.toIso8601String(),
    'message': message,
    'usesStoredKey': usesStoredKey,
  };

  static ProviderConnection? fromJson(Map<String, dynamic> json) {
    final id = json['providerId'];
    if (id is! String) return null;
    return ProviderConnection(
      providerId: id,
      status: ConnectionStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ConnectionStatus.notConnected,
      ),
      accountLabel: json['accountLabel'] as String?,
      accountId: json['accountId'] as String?,
      accountChangedAt: switch (json['accountChangedAt']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
      connectedAt: switch (json['connectedAt']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
      message: json['message'] as String?,
      // Absent in connections written before this was recorded. False is the
      // safe reading of a missing value: it only ever removes a Keychain
      // requirement, so the worst case is a stale link surviving one launch,
      // not a real key going unchecked.
      usesStoredKey: json['usesStoredKey'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'ProviderConnection($providerId, ${status.name})';

  @override
  bool operator ==(Object other) =>
      other is ProviderConnection &&
      other.providerId == providerId &&
      other.status == status &&
      other.accountLabel == accountLabel &&
      other.accountId == accountId &&
      other.accountChangedAt == accountChangedAt &&
      other.connectedAt == connectedAt &&
      other.message == message &&
      other.usesStoredKey == usesStoredKey;

  @override
  int get hashCode => Object.hash(
    providerId,
    status,
    accountLabel,
    accountId,
    accountChangedAt,
    connectedAt,
    message,
    usesStoredKey,
  );
}
