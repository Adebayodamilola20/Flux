import 'package:http/http.dart' as http;

import '../../core/logger.dart';
import '../../models/active_session.dart';
import '../../models/app_settings.dart';
import '../../models/connection_status.dart';
import '../../models/provider_connection.dart';
import '../../models/usage_data.dart';
import '../../models/usage_failure.dart';
import '../../models/usage_window.dart';
import '../../services/connection_store.dart';
import '../../services/native/native_bridge.dart';
import '../usage_provider.dart';

/// What one integration's usage endpoint reported.
class ApiUsageReading {
  const ApiUsageReading({
    required this.windows,
    this.accountLabel,
    this.notes = const [],
    this.unavailableReason,
  });

  /// The account is reachable but publishes no usage figure.
  const ApiUsageReading.unavailable(String reason, {this.accountLabel})
      : windows = const [],
        notes = const [],
        unavailableReason = reason;

  final List<UsageWindow> windows;
  final String? accountLabel;
  final List<String> notes;
  final String? unavailableReason;

  bool get hasWindows => windows.isNotEmpty;
}

/// A provider whose account is linked with a key the user creates on the
/// provider's own site.
///
/// For developer platforms this **is** the official account credential, not a
/// workaround: OpenRouter, OpenAI, Anthropic and the rest issue keys precisely
/// so tools can read usage on the user's behalf. What this app refuses is
/// asking for a *password*, or presenting another application's OAuth client
/// as its own. A key the user deliberately creates and pastes is neither.
///
/// The flow is still browser-first — Connect opens the provider's key page,
/// the user creates a key there, and pastes it back once. No terminal, no CLI,
/// nothing to install.
abstract class ApiKeyUsageProvider implements UsageProvider {
  ApiKeyUsageProvider({
    required NativeBridge native,
    required ConnectionStore connectionStore,
    http.Client? httpClient,
    Logger? logger,
  })  : _native = native,
        _connections = connectionStore,
        client = httpClient ?? http.Client(),
        log = logger ?? const Logger('api.provider') {
    _connection = ProviderConnection.notConnected(descriptor.id);
  }

  final NativeBridge _native;
  final ConnectionStore _connections;

  /// Shared HTTP client, available to subclasses for their usage call.
  final http.Client client;
  final Logger log;

  late ProviderConnection _connection;

  // MARK: - What subclasses define

  /// Where the user creates the key. Opened in their browser on Connect.
  Uri get keyUrl;

  /// Shape hint shown in the paste field, e.g. `sk-or-v1-…`.
  String get keyHint;

  /// Reads usage for [apiKey].
  ///
  /// Throws [UsageFailure] for real problems — a rejected key, a network
  /// error. Return [ApiUsageReading.unavailable] when the call succeeded but
  /// the provider publishes no figure.
  Future<ApiUsageReading> readUsage(String apiKey, AppSettings settings);

  /// Usage available without a key, when this provider has such a source.
  ///
  /// Returns null when there is none, which is the default: most integrations
  /// need the key.
  Future<ApiUsageReading?> readUsageWithoutKey(AppSettings settings) async =>
      null;

  /// Executables whose presence indicates local activity. Optional.
  List<String> get processNames => const [];

  /// How a detected process is labelled.
  String get activityLabel => descriptor.displayName;

  // MARK: - UsageProvider

  @override
  String get id => descriptor.id;

  @override
  String get displayName => descriptor.displayName;

  @override
  ProviderConnection get connection => _connection;

  @override
  bool get supportsLocalOnly => false;

  @override
  Future<ProviderConnection> enableLocalOnly() async => _connection;

  /// Keychain entry holding this integration's key.
  String get keychainId => 'apikey.$id';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> restore() async {
    final stored = _connections.load(id);
    if (stored.status == ConnectionStatus.notConnected) {
      _connection = stored;
      return;
    }

    // A stored connection is only real while its key is still in the Keychain.
    if (await _apiKey() == null) {
      _connection = stored.copyWith(
        status: ConnectionStatus.notConnected,
        message: 'The saved key is no longer in your Keychain.',
      );
      await _connections.save(_connection);
      return;
    }

    _connection = stored;
  }

  @override
  Future<ProviderConnection> connect({required UrlLauncher launchUrl}) async {
    final opened = await launchUrl(keyUrl);
    if (!opened) {
      return _update(_connection.copyWith(
        status: ConnectionStatus.error,
        message: 'Could not open your browser. Visit ${keyUrl.host} to create '
            'a key.',
      ));
    }

    return _update(_connection.copyWith(
      status: ConnectionStatus.connecting,
      message: 'Create a key on ${keyUrl.host}, then paste it here.',
      clearAccountLabel: true,
    ));
  }

  @override
  Future<ProviderConnection> completeAuthentication(String payload) async {
    final key = payload.trim();
    if (key.isEmpty) {
      return _update(_connection.copyWith(
        status: ConnectionStatus.error,
        message: 'No key was entered.',
      ));
    }

    // Verified against the live endpoint before it is stored, so a bad paste
    // fails here rather than as an empty rail ten minutes later.
    ApiUsageReading reading;
    try {
      reading = await readUsage(key, const AppSettings());
    } on UsageFailure catch (e) {
      return _update(_connection.copyWith(
        status: ConnectionStatus.error,
        message: e.message,
      ));
    }

    if (!await _native.writeSecret(keychainId, key)) {
      return _update(_connection.copyWith(
        status: ConnectionStatus.error,
        message: 'The key could not be saved to your Keychain.',
      ));
    }

    return _update(ProviderConnection(
      providerId: id,
      status: ConnectionStatus.connected,
      connectedAt: DateTime.now(),
      accountLabel: reading.accountLabel,
    ));
  }

  @override
  Future<void> disconnect() async {
    await _native.writeSecret(keychainId, null);
    // A record, not an erasure: an absent record means "never set up", which is
    // what lets a provider adopt itself on first run.
    await _connections.markDisconnected(id);
    _connection = ProviderConnection.notConnected(id);
  }

  /// Nothing local to watch: these figures come from a network call, so
  /// the refresh timer is the only signal there is.
  @override
  Stream<void>? get changes => null;

  /// The user's interval, unless a subclass has a cheaper local source and
  /// says otherwise.
  @override
  Duration? get preferredRefreshInterval => null;

  /// Nothing cached beyond the key itself, which a refresh should not discard.
  @override
  void invalidateCaches() {}

  @override
  Future<List<ActiveSession>> detectActivity() async {
    if (processNames.isEmpty) return const [];
    final processes = await _native.findProcesses(processNames);
    return [
      for (final process in processes)
        ActiveSession(
          title: descriptor.displayName,
          host: process.host,
          command: activityLabel,
          pid: process.pid,
          isBusy: true,
        ),
    ];
  }

  @override
  Future<UsageData> fetchUsage(AppSettings settings) async {
    if (!_connection.isConnected) {
      throw UsageFailure(
        UsageFailureKind.notConfigured,
        '${descriptor.displayName} is not connected.',
        hint: 'Connect ${descriptor.displayName} to see your usage.',
      );
    }

    final key = await _apiKey();

    // A provider may have a second, key-free source — an allowance its own
    // desktop tool already recorded. That path is tried before insisting on a
    // key the user may never have created.
    ApiUsageReading? reading;
    if (key == null) {
      reading = await readUsageWithoutKey(settings);
      if (reading == null) {
        await _update(_connection.copyWith(
          status: ConnectionStatus.notConnected,
          message: 'The saved key is no longer in your Keychain.',
        ));
        throw UsageFailure(
          UsageFailureKind.authentication,
          'The ${descriptor.displayName} key is missing.',
          hint: 'Reconnect ${descriptor.displayName}.',
        );
      }
    } else {
      reading = await readUsage(key, settings);
    }

    if (reading.accountLabel != null &&
        reading.accountLabel != _connection.accountLabel) {
      await _update(_connection.copyWith(accountLabel: reading.accountLabel));
    }

    return UsageData(
      providerId: id,
      providerName: displayName,
      windows: reading.windows,
      connection: ConnectionStatus.connected,
      fetchedAt: DateTime.now(),
      accountLabel: reading.accountLabel ?? _connection.accountLabel,
      notes: reading.notes,
      usageUnavailableReason: reading.hasWindows
          ? null
          : (reading.unavailableReason ??
              'No usage is available for ${descriptor.displayName}.'),
    );
  }

  /// Records a new connection state, persisting settled ones.
  ///
  /// Available to subclasses so a provider with a second, key-free way to link
  /// an account can use the same bookkeeping.
  Future<ProviderConnection> updateConnection(ProviderConnection next) =>
      _update(next);

  Future<ProviderConnection> _update(ProviderConnection next) async {
    _connection = next;
    if (next.status != ConnectionStatus.connecting) {
      await _connections.save(next);
    }
    return next;
  }

  /// True when the user has already made a decision about this slot.
  ///
  /// Available to subclasses that adopt themselves on first run, so adoption
  /// can be skipped for a provider the user deliberately switched off.
  bool connectionsHaveRecordFor(String providerId) =>
      _connections.isDismissed(providerId);

  Future<String?> _apiKey() async {
    final key = await _native.readSecret(keychainId);
    if (key == null || key.trim().isEmpty) return null;
    return key.trim();
  }

  @override
  Future<void> dispose() async {
    client.close();
  }
}
