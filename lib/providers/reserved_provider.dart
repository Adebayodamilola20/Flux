import '../models/app_settings.dart';
import '../models/connection_status.dart';
import '../models/provider_connection.dart';
import '../models/usage_data.dart';
import '../models/usage_failure.dart';
import 'usage_provider.dart';

/// A slot that is part of the product but has no integration in this build.
///
/// It exists so the rail and the connect screen show the real shape of the
/// product — three slots — without any of them pretending to work. Every method
/// refuses honestly: no fabricated usage, no fake "Connected" state, and no
/// browser window opened to a page that cannot complete anything.
///
/// Replacing one of these with a real integration is a single line in the
/// composition root.
class ReservedProvider implements UsageProvider {
  ReservedProvider(this.descriptor)
    : assert(
        !descriptor.isImplemented,
        'ReservedProvider must not stand in for an implemented slot',
      );

  @override
  final ProviderDescriptor descriptor;

  @override
  String get id => descriptor.id;

  @override
  String get displayName => descriptor.displayName;

  @override
  String get sourceDescription =>
      '${descriptor.displayName} is not integrated in this version. No usage '
      'is collected for it.';

  @override
  ProviderConnection get connection =>
      ProviderConnection.unsupported(descriptor.id);

  @override
  Future<void> restore() async {}

  @override
  Future<bool> isAvailable() async => false;

  @override
  bool get supportsLocalOnly => false;

  @override
  Future<ProviderConnection> enableLocalOnly() async => connection;

  @override
  Future<ProviderConnection> connect({required UrlLauncher launchUrl}) async {
    // Deliberately does not open a browser: there is nothing on the other end
    // to authenticate against yet.
    return connection;
  }

  @override
  Future<ProviderConnection> completeAuthentication(String payload) async =>
      connection;

  @override
  Future<void> disconnect() async {}

  @override
  Future<UsageData> fetchUsage(AppSettings settings) {
    throw UsageFailure(
      UsageFailureKind.notConfigured,
      '${descriptor.displayName} is not available in this version.',
    );
  }

  @override
  Future<void> dispose() async {}
}

/// Convenience for the connection state a reserved slot always reports.
extension ReservedProviderStatus on ReservedProvider {
  ConnectionStatus get status => ConnectionStatus.unsupported;
}
