import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/usage_failure.dart';
import 'package:ai_usage_monitor/providers/provider_catalog.dart';
import 'package:ai_usage_monitor/providers/provider_registry.dart';
import 'package:ai_usage_monitor/providers/reserved_provider.dart';
import 'package:ai_usage_monitor/services/history_service.dart';
import 'package:ai_usage_monitor/services/settings_service.dart';
import 'package:ai_usage_monitor/services/usage_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_native_bridge.dart';
import '../support/fake_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge native;
  late SharedPreferences preferences;
  late SettingsService settings;

  setUp(() async {
    native = FakeNativeBridge();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    settings = SettingsService(preferences: preferences, native: native);
    await settings.load();
  });

  tearDown(() => native.dispose());

  /// A registry with one controllable provider and two reserved slots — the
  /// shape this build actually ships.
  ({UsageController controller, FakeProvider primary}) buildController({
    FakeProvider? provider,
  }) {
    final primary =
        provider ?? FakeProvider(id: 'claude', displayName: 'Claude');
    final registry = ProviderRegistry([
      primary,
      ReservedProvider(ProviderCatalog.codex),
      ReservedProvider(ProviderCatalog.antigravity),
    ]);

    return (
      controller: UsageController(
        registry: registry,
        settingsService: settings,
        historyService: HistoryService(preferences: preferences),
        native: native,
      ),
      primary: primary,
    );
  }

  group('slots', () {
    test('exposes one state per slot before anything is fetched', () {
      final (controller: controller, primary: _) = buildController();

      expect(controller.states, hasLength(ProviderCatalog.slotCount));
      expect(controller.states.first.id, 'claude');
      expect(
        controller.states.map((s) => s.status),
        everyElement(
          anyOf(ConnectionStatus.notConnected, ConnectionStatus.unsupported),
        ),
      );
    });

    test('reports reserved slots as unsupported, never as an error', () {
      final (controller: controller, primary: _) = buildController();
      final reserved = controller.stateFor('codex');

      expect(reserved.status, ConnectionStatus.unsupported);
      expect(reserved.percent, isNull);
      expect(reserved.failure, isNull);
    });
  });

  group('refresh', () {
    test('skips providers that are not connected', () async {
      final (controller: controller, primary: primary) = buildController();

      await controller.refreshAll();

      expect(primary.fetchCount, 0);
      expect(controller.stateFor('claude').data, isNull);
    });

    test('fetches a connected provider and exposes its percentage', () async {
      final provider = FakeProvider(id: 'claude', percent: 52)..seedConnected();
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      await controller.refreshAll();

      expect(provider.fetchCount, 1);
      expect(controller.stateFor('claude').percent, 52);
      expect(controller.stateFor('claude').status, ConnectionStatus.connected);
    });

    test('keeps the previous reading when a later fetch fails', () async {
      final provider = FakeProvider(id: 'claude', percent: 52)..seedConnected();
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      await controller.refresh('claude');
      expect(controller.stateFor('claude').percent, 52);

      provider.failure = const UsageFailure(
        UsageFailureKind.network,
        'offline',
      );
      await controller.refresh('claude');

      final state = controller.stateFor('claude');
      // The last known figure survives so the rail can show it next to
      // "updated 5m ago" rather than blanking out.
      expect(state.percent, 52);
      expect(state.failure?.kind, UsageFailureKind.network);
      expect(state.status, ConnectionStatus.error);
    });

    test('reports an unmeasurable window as unknown, not zero', () async {
      final provider = FakeProvider(id: 'claude', percent: null)
        ..seedConnected();
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      await controller.refresh('claude');

      expect(controller.stateFor('claude').percent, isNull);
    });
  });

  group('connection', () {
    test('connect opens the provider’s own page in the browser', () async {
      final (controller: controller, primary: primary) = buildController();

      final result = await controller.connect('claude');

      expect(native.openedUrls, hasLength(1));
      expect(primary.openedUrl, isNotNull);
      expect(result.status, ConnectionStatus.connecting);
    });

    test('completing authentication connects and fetches', () async {
      final (controller: controller, primary: primary) = buildController();

      await controller.connect('claude');
      final result = await controller.completeAuthentication(
        'claude',
        'sk-ant-admin-x',
      );

      expect(result.status, ConnectionStatus.connected);
      expect(primary.fetchCount, 1);
      expect(controller.hasAnyConnection, isTrue);
    });

    test('an empty credential fails without fetching', () async {
      final (controller: controller, primary: primary) = buildController();

      final result = await controller.completeAuthentication('claude', '');

      expect(result.status, ConnectionStatus.error);
      expect(primary.fetchCount, 0);
    });

    test(
      'local-only adopts a limited link rather than a connected one',
      () async {
        final provider = FakeProvider(id: 'claude', supportsLocalOnly: true);
        final (controller: controller, primary: _) = buildController(
          provider: provider,
        );

        final result = await controller.enableLocalOnly('claude');

        // "limited" is the honest label: real figures, but only what this Mac
        // can see, and not blessed by the provider.
        expect(result.status, ConnectionStatus.limited);
        expect(controller.hasAnyConnection, isTrue);
      },
    );

    test('disconnect clears the slot back to its initial state', () async {
      final provider = FakeProvider(id: 'claude', percent: 52)..seedConnected();
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      await controller.refresh('claude');
      expect(controller.stateFor('claude').percent, 52);

      await controller.disconnect('claude');

      final state = controller.stateFor('claude');
      expect(state.data, isNull);
      expect(state.status, ConnectionStatus.notConnected);
      expect(controller.hasAnyConnection, isFalse);
    });

    test('connecting an unknown slot is a no-op, not a crash', () async {
      final (controller: controller, primary: _) = buildController();
      final result = await controller.connect('nope');
      expect(result.status, ConnectionStatus.notConnected);
    });
  });

  group('menu bar', () {
    test('pushes the first measurable percentage', () async {
      final provider = FakeProvider(id: 'claude', percent: 52)..seedConnected();
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      await controller.refresh('claude');

      expect(native.menuBarUpdates.last.percent, 52);
      expect(native.menuBarUpdates.last.isError, isFalse);
    });

    test('flags an error rather than leaving a stale number', () async {
      final provider = FakeProvider(id: 'claude')
        ..seedConnected()
        ..failure = const UsageFailure(UsageFailureKind.network, 'offline');
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      await controller.refresh('claude');

      expect(native.menuBarUpdates.last.isError, isTrue);
      expect(native.menuBarUpdates.last.percent, isNull);
    });
  });
}
