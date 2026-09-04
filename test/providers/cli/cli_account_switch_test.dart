import 'dart:io';

import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/models/usage_window.dart';
import 'package:ai_usage_monitor/providers/antigravity/antigravity_usage_provider.dart';
import 'package:ai_usage_monitor/providers/cli/cli_quota_source.dart';
import 'package:ai_usage_monitor/services/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_native_bridge.dart';

/// Stands in for the pseudo-terminal probe, so these tests never start `agy`.
class _StubQuotaSource implements CliQuotaSource {
  CliQuotaSourceReading? _cached = CliQuotaSourceReading(
    windows: const [
      UsageWindow(
        id: 'weekly',
        label: 'This week',
        consumed: 60,
        limit: 100,
        source: UsageSource.interactiveCli,
      ),
    ],
    observedAt: DateTime.now(),
    accountLabel: 'old@example.com',
  );

  bool? lastAllowedLaunch;
  int invalidations = 0;

  @override
  CliQuotaSourceReading? get cached => _cached;

  @override
  Future<CliQuotaSourceReading> read({
    bool force = false,
    DateTime? staleIfOlderThan,
    bool allowLaunch = true,
  }) async {
    lastAllowedLaunch = allowLaunch;
    return _cached ??
        const CliQuotaSourceReading.failed(CliQuotaFailure.noPanel);
  }

  @override
  Future<bool> get isInstalled async => true;

  @override
  void invalidate() {
    invalidations++;
    _cached = null;
  }

  @override
  String get executable => 'agy';

  @override
  String get usageCommand => '/usage';

  @override
  Duration get ttl => const Duration(minutes: 3);
}

/// Antigravity with its home directory pointed at a scratch folder, so the
/// watch stats files this test wrote and not the developer's own sign-in.
class _SandboxedAntigravity extends AntigravityUsageProvider {
  _SandboxedAntigravity({
    required super.native,
    required super.connectionStore,
    required super.source,
    required this.home,
  });

  final String home;

  @override
  String? get homeDirectory => home;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge native;
  late SharedPreferences preferences;
  late Directory home;

  setUp(() async {
    native = FakeNativeBridge();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    home = Directory.systemTemp.createTempSync('devnotch-home-');
  });

  tearDown(() {
    native.dispose();
    home.deleteSync(recursive: true);
  });

  ({_SandboxedAntigravity provider, _StubQuotaSource source}) build() {
    final source = _StubQuotaSource();
    return (
      provider: _SandboxedAntigravity(
        native: native,
        connectionStore: ConnectionStore(preferences: preferences),
        source: source,
        home: home.path,
      ),
      source: source,
    );
  }

  /// Writes the account file with the given modification time, so the test
  /// controls "when" it changed rather than racing the clock.
  File accountsFile({required DateTime modifiedAt}) {
    final file = File('${home.path}/.gemini/google_accounts.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"active":"someone@example.com","old":[]}')
      ..setLastModifiedSync(modifiedAt);
    return file;
  }

  group('switching account', () {
    test('is noticed without the user opening the CLI', () async {
      // The complaint: sign in to Antigravity as someone else and the rail
      // keeps showing the previous account's figure until the CLI happens to
      // be opened. The sign-in files are the signal that the account changed.
      final now = DateTime.now();
      accountsFile(modifiedAt: now.subtract(const Duration(minutes: 10)));
      final (provider: provider, source: source) = build();

      final events = <DateTime>[];
      final subscription = provider
          .watchCredentials(
            interval: const Duration(milliseconds: 20),
            settle: Duration.zero,
          )
          .listen(events.add);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events, isEmpty, reason: 'nothing changed yet');

      accountsFile(modifiedAt: now.subtract(const Duration(minutes: 1)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await subscription.cancel();

      expect(events, hasLength(1));
      expect(source.invalidations, 1, reason: "the old account's reading is gone");
      expect(source.cached, isNull);
    });

    test('lets the next read start the CLI to fetch the new account', () async {
      final now = DateTime.now();
      accountsFile(modifiedAt: now.subtract(const Duration(minutes: 10)));
      final (provider: provider, source: source) = build();

      // A plain poll may not launch: that is the browser-popup rule.
      await provider.readUsage(const AppSettings());
      expect(source.lastAllowedLaunch, isFalse);

      final subscription = provider
          .watchCredentials(
            interval: const Duration(milliseconds: 20),
            settle: Duration.zero,
          )
          .listen((_) {});
      accountsFile(modifiedAt: now.subtract(const Duration(minutes: 1)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await subscription.cancel();

      // The switch is the user's doing, so the read it triggers may.
      await provider.readUsage(const AppSettings());
      expect(source.lastAllowedLaunch, isTrue);
    });

    test('waits until the sign-in has finished writing', () async {
      // A sign-in touches these files several times as it goes. Starting the
      // CLI in the middle of that would race the sign-in itself, so a change
      // counts only once the files have been quiet for a moment.
      final now = DateTime.now();
      accountsFile(modifiedAt: now.subtract(const Duration(minutes: 10)));
      final (provider: provider, source: _) = build();

      final events = <DateTime>[];
      final subscription = provider
          .watchCredentials(
            interval: const Duration(milliseconds: 20),
            settle: const Duration(minutes: 5),
          )
          .listen(events.add);

      accountsFile(modifiedAt: now.subtract(const Duration(seconds: 5)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await subscription.cancel();

      expect(events, isEmpty, reason: 'written five seconds ago is still settling');
    });
  });

  test('a provider with nothing to watch for sign-in still reports activity', () {
    final (provider: provider, source: _) = build();
    expect(provider.changes, isNotNull);
  });
}
