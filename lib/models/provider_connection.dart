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

  /// No account link is needed; figures are derived from local artifacts this
  /// machine already owns.
  localOnly,

  /// The provider offers no legitimate mechanism for this use case yet.
  unavailable;

  String get callToAction => switch (this) {
    ProviderAuthMethod.browserOAuth => 'Connect',
    ProviderAuthMethod.consoleApiKey => 'Add Admin key',
    ProviderAuthMethod.localOnly => 'Enable',
    ProviderAuthMethod.unavailable => 'Unavailable',
  };

  /// Explains, on the card itself, what clicking the button will do — so the
  /// browser opening is never a surprise.
  String get explanation => switch (this) {
    ProviderAuthMethod.browserOAuth =>
      'Opens the provider’s sign-in page in your browser.',
    ProviderAuthMethod.consoleApiKey =>
      'Opens the signed-in Anthropic Console → Admin keys. This is an API '
          'key, not an account-authorization sign-in.',
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
    this.connectedAt,
    this.message,
  });

  final String providerId;
  final ConnectionStatus status;

  /// Something the user recognises — an organisation or account name reported
  /// by the provider. Never an email guessed by the app.
  final String? accountLabel;

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
    DateTime? connectedAt,
    String? message,
    bool clearMessage = false,
    bool clearAccountLabel = false,
  }) {
    return ProviderConnection(
      providerId: providerId,
      status: status ?? this.status,
      accountLabel: clearAccountLabel
          ? null
          : (accountLabel ?? this.accountLabel),
      connectedAt: connectedAt ?? this.connectedAt,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'status': status.name,
    'accountLabel': accountLabel,
    'connectedAt': connectedAt?.toIso8601String(),
    'message': message,
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
      connectedAt: switch (json['connectedAt']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
      message: json['message'] as String?,
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
      other.connectedAt == connectedAt &&
      other.message == message;

  @override
  int get hashCode =>
      Object.hash(providerId, status, accountLabel, connectedAt, message);
}
