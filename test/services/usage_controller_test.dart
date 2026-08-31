import 'package:ai_usage_monitor/models/active_session.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/usage_failure.dart';
import 'package:ai_usage_monitor/providers/provider_catalog.dart';
import 'package:ai_usage_monitor/providers/provider_registry.dart';
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

  /// A registry with one controllable provider and the other two rail slots --
  /// shape this build actually ships.
  ({UsageController controller, FakeProvider primary}) buildController({
    FakeProvider? provider,
    Duration? refreshInterval,
  }) {
    final primary =
        provider ?? FakeProvider(id: 'claude', displayName: 'Claude');
    final registry = ProviderRegistry([
      primary,
      FakeProvider(id: 'chatgpt', displayName: 'Codex'),
      FakeProvider(id: 'gemini', displayName: 'Gemini'),
    ]);

    // Applied before the controller reads it, so its first schedule already
    // uses the interval the test asked for.
    if (refreshInterval != null) {
      settings.update(
        settings.settings.copyWith(refreshInterval: refreshInterval),
      );
    }

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

  /// Waits out [UsageController.changeDebounce], plus enough slack for the
  /// fetch it schedules to run.
  Future<void> afterDebounce() => Future<void>.delayed(
    UsageController.changeDebounce + const Duration(milliseconds: 60),
  );

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

    test('reports disconnected slots as not connected before fetch', () {
      final (controller: controller, primary: _) = buildController();
      final codex = controller.stateFor('chatgpt');

      expect(codex.status, ConnectionStatus.notConnected);
      expect(codex.percent, isNull);
      expect(codex.failure, isNull);
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
      // A network blip does not un-connect the account. The user signed in
      // successfully and has nothing to fix, so the slot stays connected and
      // reports the usage as unavailable instead.
      expect(state.status, ConnectionStatus.connected);
      expect(state.isUsageUnavailable, isTrue);
    });

    test('an expired sign-in does downgrade the slot', () async {
      final provider = FakeProvider(id: 'claude', percent: 52)..seedConnected();
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      provider.failure = const UsageFailure(
        UsageFailureKind.authentication,
        'sign-in expired',
      );
      await controller.refresh('claude');

      // This one the user *does* have to fix, so it is not dressed up as a
      // usage problem.
      final state = controller.stateFor('claude');
      expect(state.status, ConnectionStatus.error);
      expect(state.isUsageUnavailable, isFalse);
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

  group('local activity', () {
    test('is observed for slots that were never connected', () async {
      final provider = FakeProvider(id: 'claude', displayName: 'Claude')
        ..sessions = const [
          ActiveSession(
            title: 'ai_usage_monitor',
            host: 'Terminal',
            command: 'Claude Code',
            isBusy: true,
          ),
        ];
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      await controller.refreshAll();

      // Nothing is connected, so no usage was fetched — and the running
      // session still shows. This is the whole point of keeping the two apart.
      expect(controller.hasAnyConnection, isFalse);
      expect(provider.fetchCount, 0);

      final state = controller.stateFor('claude');
      expect(state.sessions, hasLength(1));
      expect(state.sessions.single.command, 'Claude Code');
      expect(state.activity, ActivityStatus.working);
      expect(controller.hasActivity, isTrue);
    });

    test('survives a provider whose usage fetch failed', () async {
      final provider = FakeProvider(id: 'claude')
        ..seedConnected()
        ..sessions = const [ActiveSession(title: 'demo', isBusy: true)]
        ..failure = const UsageFailure(UsageFailureKind.network, 'offline');
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      await controller.refreshAll();

      expect(controller.stateFor('claude').sessions, hasLength(1));
    });

    test('reports idle when nothing is running', () async {
      final (controller: controller, primary: _) = buildController();

      await controller.refreshAll();

      expect(controller.stateFor('claude').activity, ActivityStatus.idle);
      expect(controller.hasActivity, isFalse);
    });
  });

  group('live updates', () {
    test('refreshes a slot the moment its data changes', () async {
      final provider = FakeProvider(id: 'claude', percent: 10)..seedConnected();
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );
      await controller.start();
      expect(provider.fetchCount, 1);

      // Standing in for Claude Code rewriting its config: the rail should not
      // wait out the refresh interval to show the new figure.
      provider.percent = 42;
      provider.changeSignal.add(null);
      await afterDebounce();

      expect(provider.fetchCount, 2);
      expect(controller.stateFor('claude').percent, 42);
    });

    test('collapses a burst of changes into one fetch', () async {
      final provider = FakeProvider(id: 'claude', percent: 10)..seedConnected();
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );
      await controller.start();
      expect(provider.fetchCount, 1);

      // A tool rewriting its state file several times in a second is normal —
      // once per streamed response, say. Fetching for each would leave the rail
      // refreshing more than it shows a number.
      provider.percent = 42;
      for (var i = 0; i < 5; i++) {
        provider.changeSignal.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await afterDebounce();

      expect(provider.fetchCount, 2);
      expect(controller.stateFor('claude').percent, 42);
    });

    test('polls a provider that asks for a faster cadence', () async {
      final provider = FakeProvider(id: 'claude', percent: 10)
        ..seedConnected()
        ..preferredRefreshInterval = const Duration(milliseconds: 40);
      final (controller: controller, primary: _) = buildController(
        provider: provider,
        // The user's own interval, far longer than the provider's preference.
        refreshInterval: const Duration(minutes: 30),
      );
      await controller.start();
      final afterStart = provider.fetchCount;

      await Future<void>.delayed(const Duration(milliseconds: 140));

      // A figure that moves with every prompt must not sit for half an hour.
      expect(provider.fetchCount, greaterThan(afterStart));
    });

    test('never polls more slowly than the user asked', () async {
      final provider = FakeProvider(id: 'claude', percent: 10)
        ..seedConnected()
        // Longer than the user's interval: a preference is a floor, not a way
        // for a provider to opt out of being refreshed.
        ..preferredRefreshInterval = const Duration(hours: 1);
      final (controller: controller, primary: _) = buildController(
        provider: provider,
        refreshInterval: const Duration(milliseconds: 40),
      );
      await controller.start();
      final afterStart = provider.fetchCount;

      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(provider.fetchCount, greaterThan(afterStart));
    });

    test('ignores changes for a slot that is not connected', () async {
      final provider = FakeProvider(id: 'claude');
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );
      await controller.start();

      provider.changeSignal.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(provider.fetchCount, 0);
    });
  });

  group('retry is offered only when it can help', () {
    test('a network failure is retryable', () async {
      final provider = FakeProvider(id: 'claude')
        ..seedConnected()
        ..failure = const UsageFailure(UsageFailureKind.network, 'offline');
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      await controller.refresh('claude');

      expect(controller.stateFor('claude').canRetryUsage, isTrue);
    });

    test('a provider with no such endpoint is not', () async {
      final provider = FakeProvider(id: 'claude')
        ..seedConnected()
        ..permanentlyUnavailable = 'no endpoint exists';
      final (controller: controller, primary: _) = buildController(
        provider: provider,
      );

      await controller.refresh('claude');

      final state = controller.stateFor('claude');
      expect(state.isUsageUnavailable, isTrue);
      expect(state.canRetryUsage, isFalse);
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
