import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/provider_connection.dart';
import 'package:ai_usage_monitor/services/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late ConnectionStore store;

  Future<void> boot([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    preferences = await SharedPreferences.getInstance();
    store = ConnectionStore(preferences: preferences);
  }

  test('reports an unknown provider as not connected', () async {
    await boot();
    expect(store.load('claude').status, ConnectionStatus.notConnected);
  });

  test('round-trips a connection', () async {
    await boot();
    final connection = ProviderConnection(
      providerId: 'claude',
      status: ConnectionStatus.connected,
      accountLabel: 'Anthropic admin key',
      connectedAt: DateTime(2026, 8, 29, 12),
    );

    await store.save(connection);

    expect(store.load('claude'), connection);
  });

  test('never writes the credential itself', () async {
    await boot();
    await store.save(const ProviderConnection(
      providerId: 'claude',
      status: ConnectionStatus.connected,
      accountLabel: 'Anthropic admin key',
    ));

    // The secret lives in the Keychain; anything readable here must be safe to
    // copy off the machine.
    final stored = preferences.getString('connection.claude')!;
    expect(stored, isNot(contains('sk-ant')));
    expect(stored.toLowerCase(), isNot(contains('secret')));
    expect(stored.toLowerCase(), isNot(contains('password')));
  });

  test('discards an unreadable record rather than failing to start', () async {
    await boot({'flutter.connection.claude': 'not json at all'});
    expect(store.load('claude').status, ConnectionStatus.notConnected);
  });

  test('discards a record that is valid JSON but the wrong shape', () async {
    await boot({'flutter.connection.claude': '["a","b"]'});
    expect(store.load('claude').status, ConnectionStatus.notConnected);
  });

  test('falls back to not-connected for an unrecognised status', () async {
    await boot({
      'flutter.connection.claude':
          '{"providerId":"claude","status":"enlightened"}',
    });
    expect(store.load('claude').status, ConnectionStatus.notConnected);
  });

  test('clear forgets the provider', () async {
    await boot();
    await store.save(const ProviderConnection(
      providerId: 'claude',
      status: ConnectionStatus.limited,
    ));

    await store.clear('claude');

    expect(store.load('claude').status, ConnectionStatus.notConnected);
  });

  test('keeps providers independent of one another', () async {
    await boot();
    await store.save(const ProviderConnection(
      providerId: 'claude',
      status: ConnectionStatus.connected,
    ));
    await store.save(const ProviderConnection(
      providerId: 'codex',
      status: ConnectionStatus.limited,
    ));

    await store.clear('claude');

    expect(store.load('claude').status, ConnectionStatus.notConnected);
    expect(store.load('codex').status, ConnectionStatus.limited);
  });

  group('ConnectionStatus semantics', () {
    test('limited counts as healthy but is not "connected"', () {
      expect(ConnectionStatus.limited.isHealthy, isTrue);
      expect(ConnectionStatus.limited.label, 'Local only');
    });

    test('an unsupported slot is not offered for setup', () {
      expect(ConnectionStatus.unsupported.needsSetup, isFalse);
      expect(ConnectionStatus.unsupported.isHealthy, isFalse);
      expect(ConnectionStatus.unsupported.isReserved, isTrue);
    });

    test('an error asks the user to act', () {
      expect(ConnectionStatus.error.needsSetup, isTrue);
      expect(ConnectionStatus.error.isHealthy, isFalse);
    });
  });
}
