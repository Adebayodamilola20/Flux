import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/usage_failure.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/models/usage_window.dart';
import 'package:ai_usage_monitor/providers/claude/claude_account_source.dart';
import 'package:ai_usage_monitor/providers/claude/claude_admin_api_source.dart';
import 'package:ai_usage_monitor/providers/claude/claude_live_source.dart';
import 'package:ai_usage_monitor/providers/claude/claude_local_source.dart';
import 'package:ai_usage_monitor/providers/claude/claude_usage_provider.dart';
import 'package:ai_usage_monitor/providers/claude/transcript_scanner.dart';
import 'package:ai_usage_monitor/services/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_native_bridge.dart';

/// A local source with scripted results, so provider composition can be tested
/// without touching the filesystem.
class _StubLocalSource implements ClaudeLocalSource {
  _StubLocalSource({this.available = true, this.result});

  final bool available;
  final ClaudeLocalUsage? result;
  int loadCount = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<ClaudeLocalUsage> load(AppSettings settings) async {
    loadCount++;
    return result ?? const ClaudeLocalUsage(windows: []);
  }

  @override
  String get projectsPath => '/stub/projects';
}

/// An API source that returns or throws whatever the test wants.
class _StubApiSource implements ClaudeAdminApiSource {
  _StubApiSource({this.window});

  final UsageWindow? window;
  int callCount = 0;
  String? seenKey;

  @override
  Future<UsageWindow?> fetchDailyUsage({required String adminKey}) async {
    callCount++;
    seenKey = adminKey;
    return window;
  }

  @override
  void close() {}
}

UsageWindow apiWindow({int consumed = 4200}) => UsageWindow(
      id: ClaudeAdminApiSource.windowId,
      label: 'API usage today',
      consumed: consumed,
      source: UsageSource.officialApi,
    );

/// A stubbed live-usage fetch, so provider composition can be tested without
/// reading the real `~/.claude/.credentials.json` or hitting the network.
class _StubLiveSource implements ClaudeLiveUsageSource {
  _StubLiveSource({
    this.reading,
    this.failure = ClaudeLiveFailure.noCredentials,
  });

  ClaudeLiveReading? reading;
  ClaudeLiveFailure? failure;
  int fetchCount = 0;

  @override
  bool get isAvailable => reading != null;

  @override
  String get credentialsPath => '/stub/.credentials.json';

  @override
  Future<(ClaudeLiveReading?, ClaudeLiveFailure?)> fetch() async {
    fetchCount++;
    if (reading != null) return (reading, null);
    return (null, failure);
  }

  /// Counts deliberate refreshes, which is how the provider tells the source to
  /// consult the Keychain again rather than reuse the token it holds.
  int resetCount = 0;

  @override
  void reset() => resetCount++;

  @override
  void close() {}
}

ClaudeLiveReading liveReading({num fiveHour = 7, num sevenDay = 63}) {
  return ClaudeLiveReading(
    windows: [
      UsageWindow(
        id: 'five_hour',
        label: 'Current session',
        consumed: fiveHour,
        limit: 100,
        unit: '%',
        source: UsageSource.officialApi,
      ),
      UsageWindow(
        id: 'seven_day',
        label: 'This week',
        consumed: sevenDay,
        limit: 100,
        unit: '%',
        source: UsageSource.officialApi,
      ),
    ],
    fetchedAt: DateTime.now(),
  );
}

/// A stubbed read of Claude Code's local account state.
class _StubAccount implements ClaudeAccountSource {
  _StubAccount(this.reading);

  ClaudeAccountReading reading;
  bool available = true;
  int reads = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<ClaudeAccountReading> read() async {
    reads++;
    return reading;
  }

  @override
  String get configPath => '/stub/.claude.json';

  /// No file to watch in a test; the provider only listens to this.
  @override
  Stream<DateTime> watch({Duration interval = const Duration(seconds: 5)}) =>
      const Stream<DateTime>.empty();
}

/// The shape Claude Code actually writes to `~/.claude.json`.
Map<String, dynamic> claudeConfig({
  String? email = 'someone@example.com',
  num fiveHour = 2,
  num sevenDay = 51,
  bool extraEnabled = false,
  DateTime? fetchedAt,
  DateTime? fiveHourResetsAt,
  DateTime? sevenDayResetsAt,
}) {
  // Relative to now, not a fixed date. A cached window whose reset has already
  // passed is deliberately dropped by the provider, so a hard-coded date here
  // would quietly turn every cache-fallback test into a test of that instead.
  final now = DateTime.now().toUtc();
  final fiveHourReset = fiveHourResetsAt ?? now.add(const Duration(hours: 3));
  final sevenDayReset = sevenDayResetsAt ?? now.add(const Duration(days: 3));
  return {
    'oauthAccount': {
      if (email != null) 'emailAddress': email,
      'displayName': 'Stephen',
      'organizationType': 'claude_pro',
    },
    'cachedUsageUtilization': {
      'fetchedAtMs':
          (fetchedAt ?? DateTime(2026, 8, 30, 13, 49)).millisecondsSinceEpoch,
      'utilization': {
        'five_hour': {
          'utilization': fiveHour,
          'resets_at': fiveHourReset.toIso8601String(),
        },
        'seven_day': {
          'utilization': sevenDay,
          'resets_at': sevenDayReset.toIso8601String(),
        },
        'seven_day_opus': null,
        'extra_usage': {
          'is_enabled': extraEnabled,
          'monthly_limit': 4000,
          'used_credits': 4024,
        },
      },
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge native;
  late SharedPreferences preferences;
  late _StubAccount account;

  setUp(() async {
    native = FakeNativeBridge();
    SharedPreferences.setMockInitialValues({
      'flutter.connection.claude':
          '{"providerId":"claude","status":"connected"}',
    });
    preferences = await SharedPreferences.getInstance();
    account = _StubAccount(
      ClaudeAccountSource.parse(claudeConfig()),
    );
  });

  tearDown(() => native.dispose());

  Future<ClaudeUsageProvider> build({
    ClaudeLocalSource? local,
    ClaudeLiveUsageSource? live,
  }) async {
    final provider = ClaudeUsageProvider(
      native: native,
      connectionStore: ConnectionStore(preferences: preferences),
      accountSource: account,
      // Defaults to "no live credentials", so tests that care only about the
      // cache path fall back to it exactly as they did before the live source
      // existed. Tests exercising the live path pass their own stub.
      liveSource: live ?? _StubLiveSource(),
      localSource: local ?? _StubLocalSource(available: false),
      apiSource: _StubApiSource(window: apiWindow()),
    );
    await provider.restore();
    return provider;
  }

  group('reading the account', () {
    test('parses Anthropic’s own utilization figures', () {
      final reading = ClaudeAccountSource.parse(claudeConfig());

      expect(reading.email, 'someone@example.com');
      expect(reading.plan, 'claude_pro');
      expect(ClaudeAccountSource.planLabel(reading.plan), 'Claude Pro');

      final session = reading.windows.firstWhere((w) => w.id == 'five_hour');
      final week = reading.windows.firstWhere((w) => w.id == 'seven_day');

      // Anthropic reports whole percentages. They are used verbatim rather
      // than recomputed from anything.
      expect(session.percentUsed, 2);
      expect(week.percentUsed, 51);
      expect(session.resetsAt, isNotNull);
    });

    test('marks the figures as provider-reported', () {
      final reading = ClaudeAccountSource.parse(claudeConfig());
      expect(
        reading.windows.every((w) => w.source == UsageSource.officialApi),
        isTrue,
      );
    });

    test('records when Claude Code last refreshed them', () {
      final at = DateTime(2026, 8, 30, 13, 49);
      final reading = ClaudeAccountSource.parse(claudeConfig(fetchedAt: at));

      // This is a cache, so the age has to be available to show.
      expect(reading.fetchedAt, at);
    });

    test('skips codenamed buckets that mean nothing to a person', () {
      final ids = ClaudeAccountSource.parse(claudeConfig()).windows.map(
            (w) => w.id,
          );
      expect(ids, isNot(contains('seven_day_opus')));
    });

    test('reports the session and the week and nothing else', () {
      // Extra usage is denominated in credits, not percent, so it never
      // belonged beside two windows a person reads as "how much is left".
      // It stays out even when the account has it switched on.
      for (final enabled in [false, true]) {
        final ids = ClaudeAccountSource.parse(
          claudeConfig(extraEnabled: enabled),
        ).windows.map((w) => w.id);
        expect(ids, ['five_hour', 'seven_day']);
      }
    });

    test('handles a config with no account', () {
      final reading = ClaudeAccountSource.parse(claudeConfig(email: null));
      expect(reading.isSignedIn, isFalse);
    });

    test('handles a config with no usage block', () {
      final reading = ClaudeAccountSource.parse({
        'oauthAccount': {'emailAddress': 'a@b.com'},
      });
      expect(reading.isSignedIn, isTrue);
      expect(reading.hasUsage, isFalse);
    });
  });

  group('connecting', () {
    test('adopts the account Claude Code is signed in as', () async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final provider = await build();

      final result = await provider.enableLocalOnly();

      // Anthropic's own figures for a real account, so this is connected
      // rather than a lesser "limited" state.
      expect(result.status, ConnectionStatus.connected);
      expect(result.accountLabel, 'someone@example.com');
      // No browser, no key, no terminal — the session already exists.
      expect(native.openedUrls, isEmpty);
      expect(native.secrets, isEmpty);
    });

    test('says so when no Claude account is signed in here', () async {
      account.reading = ClaudeAccountSource.parse(claudeConfig(email: null));
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final provider = await build();

      final result = await provider.enableLocalOnly();

      expect(result.status, ConnectionStatus.error);
      expect(result.message, contains('No signed-in Claude account'));
    });
  });

  group('usage', () {
    test('reports the subscription percentages, not token counts', () async {
      final provider = await build();

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.windows.map((w) => w.id), ['five_hour', 'seven_day']);
      expect(data.windows.first.percentUsed, 2);
      expect(data.windows.last.percentUsed, 51);
      // Nothing derived from transcripts, and no token window at all.
      expect(data.windows.any((w) => w.unit == 'tokens'), isFalse);
      expect(data.accountLabel, 'someone@example.com');
    });

    test('names the plan and says how fresh the figures are', () async {
      final provider = await build();

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.notes, contains('Claude Pro'));
      expect(data.notes.join(), contains('Reported by Anthropic'));
    });

    test('prefers the live figure over the cached one', () async {
      // Cache says 2%/51%; the live endpoint says 7%/63%. The live figure is
      // the one the user should see, and it is labelled as live.
      final provider = await build(live: _StubLiveSource(reading: liveReading()));

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.windows.first.percentUsed, 7);
      expect(data.windows.last.percentUsed, 63);
      expect(data.notes.join(), contains('Live from Anthropic'));
      // The live path must not claim to be a cache read.
      expect(data.notes.join(), isNot(contains('Reported by Anthropic')));
      // Identity still comes from the local account file.
      expect(data.accountLabel, 'someone@example.com');
      expect(data.notes, contains('Claude Pro'));
    });

    test('falls back to the cache when the session token is expired', () async {
      // The token exists but is stale. Refreshing it would log the user out of
      // Claude Code, so the provider uses the cached figure instead — and says
      // it is a cache, not live.
      final provider = await build(
        live: _StubLiveSource(failure: ClaudeLiveFailure.tokenExpired),
      );

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.windows.first.percentUsed, 2);
      expect(data.windows.last.percentUsed, 51);
      expect(data.notes.join(), contains('Reported by Anthropic'));
      expect(data.notes.join(), isNot(contains('Live from Anthropic')));
    });

    group('what the percentage cost', () {
    test('carries this Mac’s token totals alongside Anthropic’s share',
        () async {
      // Anthropic reports a share of the plan limit and never a token count,
      // so "38%" says how close the ceiling is and nothing about what was
      // spent reaching it. The transcripts on this Mac do have real totals for
      // the same two periods.
      final provider = await build(
        live: _StubLiveSource(reading: liveReading()),
        local: _StubLocalSource(
          result: const ClaudeLocalUsage(
            windows: [
              UsageWindow(
                id: 'session',
                label: 'Current session',
                consumed: 1200000,
                source: UsageSource.localTracking,
              ),
              UsageWindow(
                id: 'weekly',
                label: 'All models',
                consumed: 48000000,
                source: UsageSource.localTracking,
              ),
            ],
          ),
        ),
      );

      final data = await provider.fetchUsage(const AppSettings());
      final session = data.windows.firstWhere((w) => w.id == 'five_hour');
      final week = data.windows.firstWhere((w) => w.id == 'seven_day');

      expect(session.tokensUsed, 1200000);
      expect(week.tokensUsed, 48000000);
      // The percentage is untouched — it is Anthropic's figure and stays so.
      expect(session.unit, isNot('tokens'));
    });

    test('is absent rather than invented when nothing local is known',
        () async {
      // There is no published token ceiling to multiply the percentage by, so
      // a number derived that way would look exact and mean nothing.
      final provider = await build(
        live: _StubLiveSource(reading: liveReading()),
        local: _StubLocalSource(available: false),
      );

      final data = await provider.fetchUsage(const AppSettings());

      expect(
        data.windows.every((w) => w.tokensUsed == null),
        isTrue,
      );
    });
  });

  group('a cached window that has already reset', () {
      test('is not reported as the current figure', () async {
        // The bug this fixes, with the real numbers: the cache was written at
        // 9:37 saying "66% used, resets 9:40". By 11:03 the window had rolled
        // over and the count had restarted — the CLI on another machine read
        // 14% — but the rail still showed 66% beside a reset time an hour and
        // a half in the past.
        account.reading = ClaudeAccountSource.parse(claudeConfig(
          fiveHour: 66,
          fiveHourResetsAt: DateTime.now().toUtc().subtract(
                const Duration(hours: 1, minutes: 23),
              ),
        ));
        final provider = await build(
          live: _StubLiveSource(failure: ClaudeLiveFailure.tokenExpired),
        );

        final data = await provider.fetchUsage(const AppSettings());

        // The dead window is gone; the weekly one, which has not reset, stays.
        expect(data.windows.map((w) => w.id), isNot(contains('five_hour')));
        expect(data.windows.map((w) => w.id), contains('seven_day'));
      });

      test('reports nothing rather than a dead number when all have reset',
          () async {
        final now = DateTime.now().toUtc();
        account.reading = ClaudeAccountSource.parse(claudeConfig(
          fiveHour: 66,
          fiveHourResetsAt: now.subtract(const Duration(hours: 2)),
          sevenDayResetsAt: now.subtract(const Duration(days: 1)),
        ));

        final provider = await build(
          live: _StubLiveSource(failure: ClaudeLiveFailure.keychainDenied),
        );

        final data = await provider.fetchUsage(const AppSettings());

        expect(data.windows, isEmpty);
        expect(data.isUsageUnavailable, isTrue);
        // And it says why, rather than leaving a blank slot.
        expect(data.usageUnavailableReason, contains('already reset'));
        // The account itself is fine — this is not a sign-in problem.
        expect(data.connection, ConnectionStatus.connected);
      });

      test('a live reading is never second-guessed this way', () async {
        // Live figures are current by construction, so the filter must not
        // touch them — not even when the cache sitting beside them is entirely
        // made of windows that have rolled over.
        final now = DateTime.now().toUtc();
        account.reading = ClaudeAccountSource.parse(claudeConfig(
          fiveHour: 66,
          fiveHourResetsAt: now.subtract(const Duration(hours: 2)),
          sevenDayResetsAt: now.subtract(const Duration(days: 1)),
        ));
        final provider = await build(
          live: _StubLiveSource(reading: liveReading()),
        );

        final data = await provider.fetchUsage(const AppSettings());

        expect(data.windows.first.percentUsed, 7);
        expect(data.notes.join(), contains('Live from Anthropic'));
      });
    });

    test('falls back to the cache when the live call fails on the network',
        () async {
      final provider = await build(
        live: _StubLiveSource(failure: ClaudeLiveFailure.network),
      );

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.windows.first.percentUsed, 2);
      expect(data.notes.join(), contains('Reported by Anthropic'));
    });

    test('stays connected but reports nothing when usage is absent', () async {
      account.reading = ClaudeAccountSource.parse({
        'oauthAccount': {'emailAddress': 'a@b.com'},
      });
      final provider = await build();

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.connection, ConnectionStatus.connected);
      expect(data.isUsageUnavailable, isTrue);
      expect(data.windows, isEmpty);
    });

    test('asks for reconnection when the account signed out', () async {
      account.reading = ClaudeAccountSource.parse(claudeConfig(email: null));
      final provider = await build();

      await expectLater(
        provider.fetchUsage(const AppSettings()),
        throwsA(
          isA<UsageFailure>().having(
            (f) => f.kind,
            'kind',
            UsageFailureKind.authentication,
          ),
        ),
      );
    });

    test('refuses before the user has added it', () async {
      // The rail starts empty and nothing adopts itself: a provider reports
      // usage once the user puts it on the rail, not because the tool happens
      // to be installed.
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final provider = await build();

      expect(provider.connection.isConnected, isFalse);
      await expectLater(
        provider.fetchUsage(const AppSettings()),
        throwsA(isA<UsageFailure>()),
      );
    });

    test('adding is the only click', () async {
      // No browser, no key: Claude Code has already signed in, so putting it
      // on the rail is enough to produce a figure.
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final provider = await build();

      await provider.enableLocalOnly();

      expect(provider.connection.isConnected, isTrue);
      final data = await provider.fetchUsage(const AppSettings());
      expect(data.windows, isNotEmpty);
    });
  });

  group('local activity stays separate from usage', () {
    test('names a running session after its working directory', () async {
      native.processes = [
        {'pid': 42, 'name': 'claude', 'host': 'Terminal'},
      ];
      final provider = await build(
        local: _StubLocalSource(
          available: true,
          result: ClaudeLocalUsage(
            windows: const [],
            latestEvent: TranscriptEvent(
              id: 'e1',
              timestamp: DateTime.now(),
              tokens: 10,
              workingDirectory: '/Users/test/usage-notch',
            ),
          ),
        ),
      );

      final sessions = await provider.detectActivity();

      expect(sessions.single.title, 'usage-notch');
      expect(sessions.single.command, 'Claude Code');
    });

    test('reports nothing when no CLI is running', () async {
      final provider = await build(
        local: _StubLocalSource(available: true),
      );
      expect(await provider.detectActivity(), isEmpty);
    });
  });

  group('a cached figure is never passed off as a live one', () {
    // Reported by a user as "the app is not accurate": their terminal read
    // 24% while the card read 0%, three days old, with nothing on it to say
    // why. The number was Claude Code's cache, shown in silence and with no
    // age attached, so the rail drew it as confidently as a live reading.
    test('carries the age it was measured at, so the ring shows it', () async {
      final provider = await build();
      await provider.enableLocalOnly();

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.windows, isNotEmpty);
      for (final window in data.windows) {
        expect(
          window.observedAt,
          isNotNull,
          reason: 'an unstamped window can never read as stale',
        );
      }
    });

    test('says why it is not live, even with no credentials at all', () async {
      // `noCredentials` used to fall through to no note whatsoever, which is
      // precisely the case the user hit.
      final provider = await build();
      await provider.enableLocalOnly();

      final data = await provider.fetchUsage(const AppSettings());

      expect(
        data.notes.any((n) => n.contains('cached') || n.contains('live')),
        isTrue,
        reason: 'the card must say the figure is not a live reading',
      );
    });
  });
}
