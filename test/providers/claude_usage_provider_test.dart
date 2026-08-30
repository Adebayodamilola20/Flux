import 'dart:io';

import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/usage_failure.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/models/usage_window.dart';
import 'package:ai_usage_monitor/providers/claude/claude_admin_api_source.dart';
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
  _StubLocalSource({
    this.available = true,
    this.result,
    this.error,
  });

  final bool available;
  final ClaudeLocalUsage? result;
  final Object? error;
  int loadCount = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<ClaudeLocalUsage> load(AppSettings settings) async {
    loadCount++;
    final err = error;
    if (err != null) throw err;
    return result ?? const ClaudeLocalUsage(windows: []);
  }

  @override
  String get projectsPath => '/stub/projects';
}

/// An API source that returns or throws whatever the test wants.
class _StubApiSource implements ClaudeAdminApiSource {
  _StubApiSource({this.window, this.error});

  final UsageWindow? window;
  final UsageFailure? error;
  int callCount = 0;
  String? seenKey;

  @override
  Future<UsageWindow?> fetchDailyUsage({required String adminKey}) async {
    callCount++;
    seenKey = adminKey;
    final err = error;
    if (err != null) throw err;
    return window;
  }

  @override
  void close() {}
}

UsageWindow localWindow(String id, {int consumed = 100}) => UsageWindow(
      id: id,
      label: id,
      consumed: consumed,
      limit: 1000,
      source: UsageSource.localTracking,
    );

UsageWindow apiWindow({int consumed = 4200}) => UsageWindow(
      id: ClaudeAdminApiSource.windowId,
      label: 'API usage today',
      consumed: consumed,
      source: UsageSource.providerReported,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge native;
  late SharedPreferences preferences;

  setUp(() async {
    native = FakeNativeBridge();
    // A settled connection. Refusing to fetch for a provider the user has
    // never connected is a separate case, tested on its own below.
    SharedPreferences.setMockInitialValues({
      'flutter.connection.claude':
          '{"providerId":"claude","status":"connected"}',
    });
    preferences = await SharedPreferences.getInstance();
  });

  tearDown(() => native.dispose());

  Future<ClaudeUsageProvider> build({
    ClaudeLocalSource? local,
    ClaudeAdminApiSource? api,
  }) async {
    final provider = ClaudeUsageProvider(
      native: native,
      connectionStore: ConnectionStore(preferences: preferences),
      localSource: local ?? _StubLocalSource(available: false),
      apiSource: api ?? _StubApiSource(window: apiWindow()),
    );
    await provider.restore();
    return provider;
  }

  void signIn([String key = 'sk-ant-admin-key']) {
    native.secrets[ClaudeUsageProvider.adminKeyKeychainId] = key;
  }

  group('identity', () {
    test('exposes a stable id and a human name', () async {
      final provider = await build();
      expect(provider.id, 'claude');
      expect(provider.displayName, 'Claude');
      expect(provider.sourceDescription, isNotEmpty);
    });

    test('offers no signed-out path', () async {
      final provider = await build(local: _StubLocalSource(available: true));

      // Local transcripts exist, but they are not a usage source: the number
      // they produce is this app's arithmetic, not Anthropic's.
      expect(provider.supportsLocalOnly, isFalse);

      final result = await provider.enableLocalOnly();
      expect(result.status, ConnectionStatus.error);
      expect(result.message, contains('signing in'));
    });
  });

  group('availability', () {
    test('is available when local transcripts exist', () async {
      final provider = await build(local: _StubLocalSource(available: true));
      expect(await provider.isAvailable(), isTrue);
    });

    test('is available when a key is stored', () async {
      signIn();
      final provider = await build();
      expect(await provider.isAvailable(), isTrue);
    });
  });

  group('connect', () {
    test('sends the user to Anthropic’s own console', () async {
      final provider = await build();
      Uri? opened;

      final result = await provider.connect(launchUrl: (url) async {
        opened = url;
        return true;
      });

      expect(opened, ClaudeUsageProvider.consoleUrl);
      expect(opened!.host, 'console.anthropic.com');
      // The flow finishes in the browser and comes back as a pasted key.
      expect(result.status, ConnectionStatus.connecting);
    });

    test('says so when the browser could not be opened', () async {
      final provider = await build();

      final result = await provider.connect(launchUrl: (_) async => false);

      expect(result.status, ConnectionStatus.error);
      expect(result.message, contains('browser'));
    });

    test('verifies a key against the real API before storing it', () async {
      final api = _StubApiSource(
        error: const UsageFailure(
          UsageFailureKind.authentication,
          'The Anthropic admin key was rejected.',
        ),
      );
      final provider = await build(api: api);

      final result = await provider.completeAuthentication('sk-ant-wrong');

      expect(result.status, ConnectionStatus.error);
      expect(api.callCount, 1);
      // A rejected key must never reach the Keychain.
      expect(native.secrets, isEmpty);
    });

    test('stores a verified key in the Keychain', () async {
      final provider = await build(api: _StubApiSource(window: apiWindow()));

      final result = await provider.completeAuthentication(' sk-ant-good  ');

      expect(result.status, ConnectionStatus.connected);
      expect(
        native.secrets[ClaudeUsageProvider.adminKeyKeychainId],
        'sk-ant-good',
      );
    });

    test('rejects an empty credential without calling the API', () async {
      final api = _StubApiSource(window: apiWindow());
      final provider = await build(api: api);

      final result = await provider.completeAuthentication('   ');

      expect(result.status, ConnectionStatus.error);
      expect(api.callCount, 0);
    });

    test('disconnect removes the key', () async {
      signIn();
      final provider = await build();

      await provider.disconnect();

      expect(native.secrets, isEmpty);
      expect(provider.connection.status, ConnectionStatus.notConnected);
    });

    test('a stored connection with no key is downgraded on restore', () async {
      // The user revoked the key in Keychain Access; the app must not keep
      // claiming to be connected.
      final provider = ClaudeUsageProvider(
        native: native,
        connectionStore: ConnectionStore(preferences: preferences),
        localSource: _StubLocalSource(available: false),
        apiSource: _StubApiSource(window: apiWindow()),
      );

      await provider.restore();

      expect(provider.connection.status, ConnectionStatus.notConnected);
    });
  });

  group('fetchUsage', () {
    test('refuses when the user has not signed in', () async {
      final provider = await build(local: _StubLocalSource(available: true));

      // Local transcripts are present and would happily yield a number; the
      // provider still refuses, because that number is not Anthropic's.
      await expectLater(
        provider.fetchUsage(const AppSettings()),
        throwsA(isA<UsageFailure>()),
      );
      expect(provider.connection.isConnected, isFalse);
    });

    test('a signed-in link survives restore', () async {
      signIn();
      final provider = await build();
      expect(provider.connection.status, ConnectionStatus.connected);
    });

    test('reports only provider-reported figures', () async {
      signIn();
      final local = _StubLocalSource(
        available: true,
        result: ClaudeLocalUsage(windows: [localWindow('session')]),
      );
      final provider = await build(local: local);

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.windows, hasLength(1));
      expect(data.windows.single.source, UsageSource.providerReported);
      expect(data.source, UsageSource.providerReported);
      expect(data.connection, ConnectionStatus.connected);
    });

    test('passes the trimmed key to the API', () async {
      signIn('  sk-ant-admin-spaced  ');
      final api = _StubApiSource(window: apiWindow());
      final provider = await build(api: api);

      await provider.fetchUsage(const AppSettings());

      expect(api.seenKey, 'sk-ant-admin-spaced');
    });

    test('treats a blank stored key as signed out', () async {
      signIn('   ');
      final api = _StubApiSource(window: apiWindow());
      final provider = await build(api: api);

      await expectLater(
        provider.fetchUsage(const AppSettings()),
        throwsA(isA<UsageFailure>()),
      );
      expect(api.callCount, 0);
    });

    test('surfaces an API failure rather than substituting a figure', () async {
      signIn();
      final provider = await build(
        local: _StubLocalSource(
          available: true,
          result: ClaudeLocalUsage(windows: [localWindow('session')]),
        ),
        api: _StubApiSource(
          error: const UsageFailure(UsageFailureKind.network, 'offline'),
        ),
      );

      await expectLater(
        provider.fetchUsage(const AppSettings()),
        throwsA(
          isA<UsageFailure>()
              .having((f) => f.kind, 'kind', UsageFailureKind.network),
        ),
      );
    });

    test('refuses when the account has no reported usage', () async {
      signIn();
      final provider = await build(api: _StubApiSource());

      await expectLater(
        provider.fetchUsage(const AppSettings()),
        throwsA(
          isA<UsageFailure>().having(
            (f) => f.kind,
            'kind',
            UsageFailureKind.notConfigured,
          ),
        ),
      );
    });
  });

  group('active session', () {
    test('reports no session when no CLI process is running', () async {
      signIn();
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

      final data = await provider.fetchUsage(const AppSettings());

      // A transcript with nothing running is history, not activity.
      expect(data.sessions, isEmpty);
      expect(data.activity, ActivityStatus.idle);
    });

    test('names a running session after its working directory', () async {
      signIn();
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

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.activeSession?.title, 'usage-notch');
      expect(data.activeSession?.host, 'Terminal');
      expect(data.activeSession?.command, 'Claude Code');
      expect(data.activeSession?.pid, 42);
      expect(data.activity, ActivityStatus.working);
    });

    test('marks a session busy only while it is recently active', () async {
      signIn();
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
              timestamp: DateTime.now().subtract(const Duration(hours: 1)),
              tokens: 10,
              workingDirectory: '/Users/test/usage-notch',
            ),
          ),
        ),
      );

      final data = await provider.fetchUsage(const AppSettings());

      // Still running, but sitting at a prompt rather than working.
      expect(data.activeSession?.isBusy, isFalse);
      expect(data.activity, ActivityStatus.waiting);
    });

    test('keeps the usage when the transcript scan fails', () async {
      signIn();
      native.processes = [
        {'pid': 42, 'name': 'claude', 'host': 'Terminal'},
      ];
      final provider = await build(
        local: _StubLocalSource(
          available: true,
          error: const FileSystemException('unreadable'),
        ),
      );

      final data = await provider.fetchUsage(const AppSettings());

      // Losing the session row must not lose the figures the user signed in
      // for.
      expect(data.windows, hasLength(1));
      expect(data.sessions, isEmpty);
    });
  });
}
