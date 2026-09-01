import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/models/usage_window.dart';
import 'package:ai_usage_monitor/providers/antigravity/antigravity_usage_provider.dart';
import 'package:ai_usage_monitor/providers/cli/cli_quota_source.dart';
import 'package:ai_usage_monitor/services/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_native_bridge.dart';

UsageWindow _window() => const UsageWindow(
      id: 'weekly',
      label: 'This week',
      consumed: 12,
      limit: 100,
      source: UsageSource.interactiveCli,
    );

/// Stands in for the pseudo-terminal probe, so these tests never start `agy`.
///
/// Mirrors the real source's contract on the one point that matters here: a
/// failed probe does not erase the last good reading.
class _StubQuotaSource implements CliQuotaSource {
  _StubQuotaSource();

  CliQuotaSourceReading? _cached;
  CliQuotaFailure? nextFailure;

  /// Makes the next read succeed with a panel.
  void succeedWith(DateTime at) {
    _cached = CliQuotaSourceReading(
      windows: [_window()],
      observedAt: at,
      planLabel: 'Antigravity Pro',
    );
    nextFailure = null;
  }

  @override
  CliQuotaSourceReading? get cached => _cached;

  @override
  Future<CliQuotaSourceReading> read({
    bool force = false,
    DateTime? staleIfOlderThan,
  }) async {
    final failure = nextFailure;
    if (failure != null) return CliQuotaSourceReading.failed(failure);
    return _cached ??
        const CliQuotaSourceReading.failed(CliQuotaFailure.noPanel);
  }

  @override
  Future<bool> get isInstalled async => true;

  @override
  void invalidate() => _cached = null;

  @override
  String get executable => 'agy';

  @override
  String get usageCommand => '/usage';

  @override
  Duration get ttl => const Duration(minutes: 3);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge native;
  late SharedPreferences preferences;

  setUp(() async {
    native = FakeNativeBridge();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  tearDown(() => native.dispose());

  AntigravityUsageProvider build(_StubQuotaSource source) {
    return AntigravityUsageProvider(
      native: native,
      connectionStore: ConnectionStore(preferences: preferences),
      source: source,
    );
  }

  group('a probe that did not answer', () {
    test('keeps the figure it read earlier', () async {
      // Driving a real CLI under a pseudo-terminal loses to a busy machine
      // often enough that this is the normal case, not the rare one. A figure
      // read correctly ten minutes ago being replaced by "usage unavailable"
      // is what made a working slot look like it broke on its own.
      final source = _StubQuotaSource()
        ..succeedWith(DateTime.now().subtract(const Duration(minutes: 10)));
      final provider = build(source);

      final good = await provider.readUsage(const AppSettings());
      expect(good.hasWindows, isTrue);

      source.nextFailure = CliQuotaFailure.noPanel;
      final stale = await provider.readUsage(const AppSettings());

      expect(stale.hasWindows, isTrue);
      expect(stale.windows.single.consumed, 12);
      // And says plainly that it is not fresh.
      expect(stale.notes.any((n) => n.contains('Last read')), isTrue);
    });

    test('mentions signing in again when that is what went wrong', () async {
      final source = _StubQuotaSource()..succeedWith(DateTime.now());
      final provider = build(source);
      await provider.readUsage(const AppSettings());

      source.nextFailure = CliQuotaFailure.signedOut;
      final stale = await provider.readUsage(const AppSettings());

      expect(stale.hasWindows, isTrue);
      expect(
        stale.notes.any((n) => n.contains('sign in again')),
        isTrue,
        reason: 'a signed-out CLI is something the user can act on',
      );
    });

    test('a tool that is not installed shows nothing, not an old figure',
        () async {
      final source = _StubQuotaSource()..succeedWith(DateTime.now());
      final provider = build(source);
      await provider.readUsage(const AppSettings());

      source.nextFailure = CliQuotaFailure.notInstalled;
      final gone = await provider.readUsage(const AppSettings());

      // The tool being absent is not a slow probe. There is no prospect of it
      // answering, so an old number would be a claim about a machine that no
      // longer has the thing that produced it.
      expect(gone.hasWindows, isFalse);
      expect(gone.isPermanent, isTrue);
    });

    test('nothing was ever read, so there is nothing to fall back to',
        () async {
      final source = _StubQuotaSource()..nextFailure = CliQuotaFailure.noPanel;

      final reading = await build(source).readUsage(const AppSettings());

      expect(reading.hasWindows, isFalse);
      expect(reading.unavailableReason, isNotNull);
    });
  });
}
