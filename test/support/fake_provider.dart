import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/provider_connection.dart';
import 'package:ai_usage_monitor/models/usage_data.dart';
import 'package:ai_usage_monitor/models/usage_failure.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/models/usage_window.dart';
import 'package:ai_usage_monitor/providers/usage_provider.dart';

/// A provider whose every outcome is set by the test.
///
/// Lets the controller tests drive connect, disconnect, success, and failure
/// paths without touching a network, a Keychain, or a filesystem.
class FakeProvider implements UsageProvider {
  FakeProvider({
    required String id,
    String? displayName,
    ProviderAuthMethod authMethod = ProviderAuthMethod.consoleApiKey,
    bool isImplemented = true,
    this.supportsLocalOnly = false,
    this.percent = 40,
    this.failure,
  })  : descriptor = ProviderDescriptor(
          id: id,
          displayName: displayName ?? id,
          tagline: '$id tagline',
          authMethod: authMethod,
          accent: 0xFF888888,
          isImplemented: isImplemented,
        ),
        _connection = ProviderConnection.notConnected(id);

  @override
  final ProviderDescriptor descriptor;

  @override
  final bool supportsLocalOnly;

  /// Percentage the next successful fetch reports. Null omits the window
  /// entirely, which is how a provider says "I could not measure this".
  int? percent;

  /// When set, the next fetch throws this instead of returning data.
  UsageFailure? failure;

  /// Number of times [fetchUsage] was called.
  int fetchCount = 0;

  /// Whether [connect] opened a URL.
  Uri? openedUrl;

  ProviderConnection _connection;

  @override
  String get id => descriptor.id;

  @override
  String get displayName => descriptor.displayName;

  @override
  String get sourceDescription => 'fake';

  @override
  ProviderConnection get connection => _connection;

  /// Puts the provider straight into a connected state, skipping the flow.
  void seedConnected([ConnectionStatus status = ConnectionStatus.connected]) {
    _connection = ProviderConnection(providerId: id, status: status);
  }

  @override
  Future<void> restore() async {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProviderConnection> connect({required UrlLauncher launchUrl}) async {
    final url = Uri.parse('https://example.com/$id/authorize');
    await launchUrl(url);
    openedUrl = url;
    _connection = ProviderConnection(
      providerId: id,
      status: ConnectionStatus.connecting,
    );
    return _connection;
  }

  @override
  Future<ProviderConnection> completeAuthentication(String payload) async {
    _connection = ProviderConnection(
      providerId: id,
      status: payload.isEmpty
          ? ConnectionStatus.error
          : ConnectionStatus.connected,
      connectedAt: DateTime(2026),
    );
    return _connection;
  }

  @override
  Future<ProviderConnection> enableLocalOnly() async {
    _connection = ProviderConnection(
      providerId: id,
      status: ConnectionStatus.limited,
    );
    return _connection;
  }

  @override
  Future<void> disconnect() async {
    _connection = ProviderConnection.notConnected(id);
  }

  @override
  Future<UsageData> fetchUsage(AppSettings settings) async {
    fetchCount++;
    final f = failure;
    if (f != null) throw f;

    return UsageData(
      providerId: id,
      providerName: displayName,
      windows: [
        if (percent != null)
          UsageWindow(
            id: 'session',
            label: 'Current session',
            consumed: percent!,
            limit: 100,
            source: UsageSource.localTracking,
          ),
      ],
      connection: _connection.status,
      fetchedAt: DateTime.now(),
    );
  }

  @override
  Future<void> dispose() async {}
}
