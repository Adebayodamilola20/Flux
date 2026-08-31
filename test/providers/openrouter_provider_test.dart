import 'dart:convert';

import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/usage_failure.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/providers/api/openrouter_provider.dart';
import 'package:ai_usage_monitor/services/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_native_bridge.dart';

/// The documented shape of `GET /api/v1/auth/key`.
String _body({
  Object? usage = 3.25,
  Object? limit = 10,
  bool freeTier = false,
  Map<String, Object?>? rateLimit = const {
    'requests': 200,
    'interval': '10s',
  },
}) {
  return jsonEncode({
    'data': {
      'label': 'my-key',
      'usage': usage,
      'limit': limit,
      'is_free_tier': freeTier,
      if (rateLimit != null) 'rate_limit': rateLimit,
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge native;
  late SharedPreferences preferences;

  setUp(() async {
    native = FakeNativeBridge();
    SharedPreferences.setMockInitialValues({
      'flutter.connection.openrouter':
          '{"providerId":"openrouter","status":"connected"}',
    });
    preferences = await SharedPreferences.getInstance();
  });

  tearDown(() => native.dispose());

  Future<OpenRouterProvider> build(
    http.Response Function(http.Request) handler,
  ) async {
    final provider = OpenRouterProvider(
      native: native,
      connectionStore: ConnectionStore(preferences: preferences),
      httpClient: MockClient((request) async => handler(request)),
    );
    await provider.restore();
    return provider;
  }

  void signIn([String key = 'sk-or-v1-abc']) {
    native.secrets['apikey.openrouter'] = key;
  }

  group('reading usage', () {
    test('turns credits into a real percentage', () async {
      signIn();
      final provider = await build((_) => http.Response(_body(), 200));

      final data = await provider.fetchUsage(const AppSettings());
      final credits = data.windows.firstWhere((w) => w.id == 'credits');

      expect(credits.consumed, 3.25);
      expect(credits.limit, 10);
      expect(credits.percentUsed, 33);
      expect(credits.unit, 'credits');
      // An official documented endpoint — the strongest source this app has.
      expect(credits.source, UsageSource.officialApi);
      expect(data.source.isAuthoritative, isTrue);
    });

    test('sends the key as a bearer token and nothing else', () async {
      signIn('sk-or-v1-secret');
      late http.Request seen;
      final provider = await build((request) {
        seen = request;
        return http.Response(_body(), 200);
      });

      await provider.fetchUsage(const AppSettings());

      expect(seen.headers['authorization'], 'Bearer sk-or-v1-secret');
      expect(seen.url.host, 'openrouter.ai');
      expect(seen.url.path, '/api/v1/auth/key');
      // The key is never smuggled into the URL, where it would land in logs.
      expect(seen.url.toString(), isNot(contains('sk-or-v1')));
    });

    test('reports the rate limit as its own window', () async {
      signIn();
      final provider = await build((_) => http.Response(_body(), 200));

      final data = await provider.fetchUsage(const AppSettings());
      final rate = data.windows.firstWhere((w) => w.id == 'rate_limit');

      expect(rate.limit, 200);
      expect(rate.label, contains('10s'));
      expect(rate.unit, 'requests');
    });

    test('omits the bar for a key with no credit limit', () async {
      signIn();
      final provider = await build(
        (_) => http.Response(_body(limit: null), 200),
      );

      final data = await provider.fetchUsage(const AppSettings());
      final credits = data.windows.firstWhere((w) => w.id == 'credits');

      // Pay-as-you-go has no denominator. Spend is shown as a figure rather
      // than measured against an invented ceiling.
      expect(credits.limit, isNull);
      expect(credits.percentUsed, isNull);
      expect(credits.consumed, 3.25);
    });

    test('notes a free-tier key', () async {
      signIn();
      final provider = await build(
        (_) => http.Response(_body(freeTier: true), 200),
      );

      final data = await provider.fetchUsage(const AppSettings());
      expect(data.notes, contains('Free tier key.'));
    });

    test('reads the account label the provider returns', () async {
      signIn();
      final provider = await build((_) => http.Response(_body(), 200));

      final data = await provider.fetchUsage(const AppSettings());
      expect(data.accountLabel, 'my-key');
    });
  });

  group('failures', () {
    test('a rejected key asks for reconnection', () async {
      signIn();
      final provider = await build((_) => http.Response('{}', 401));

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

    test('a rate-limited response is reported as such', () async {
      signIn();
      final provider = await build((_) => http.Response('{}', 429));

      await expectLater(
        provider.fetchUsage(const AppSettings()),
        throwsA(
          isA<UsageFailure>().having(
            (f) => f.kind,
            'kind',
            UsageFailureKind.rateLimited,
          ),
        ),
      );
    });

    test('an unrecognised shape fails rather than reading zero', () async {
      signIn();
      final provider = await build(
        (_) => http.Response('{"unexpected":true}', 200),
      );

      // The critical guarantee: a changed response must not become a confident
      // 0% on the rail.
      await expectLater(
        provider.fetchUsage(const AppSettings()),
        throwsA(isA<UsageFailure>()),
      );
    });

    test('refuses before the key is connected', () async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final provider = await build((_) => http.Response(_body(), 200));

      await expectLater(
        provider.fetchUsage(const AppSettings()),
        throwsA(isA<UsageFailure>()),
      );
    });
  });

  group('connecting', () {
    test('opens the provider’s own key page', () async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final provider = await build((_) => http.Response(_body(), 200));

      final result = await provider.connect(launchUrl: native.openUrl);

      expect(native.openedUrls.single, contains('openrouter.ai'));
      expect(result.status, ConnectionStatus.connecting);
    });

    test('verifies a pasted key against the live endpoint before storing',
        () async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final provider = await build((_) => http.Response('{}', 401));

      final result = await provider.completeAuthentication('sk-or-v1-bad');

      expect(result.status, ConnectionStatus.error);
      // A key the endpoint refused must never reach the Keychain.
      expect(native.secrets, isEmpty);
    });

    test('stores a verified key in the Keychain', () async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final provider = await build((_) => http.Response(_body(), 200));

      final result =
          await provider.completeAuthentication('  sk-or-v1-good  ');

      expect(result.status, ConnectionStatus.connected);
      expect(native.secrets['apikey.openrouter'], 'sk-or-v1-good');
      // Preferences hold state, never the credential.
      expect(
        preferences.getKeys().any((k) => preferences.get(k).toString().contains('sk-or-v1')),
        isFalse,
      );
    });

    test('disconnect removes the key', () async {
      signIn();
      final provider = await build((_) => http.Response(_body(), 200));

      await provider.disconnect();

      expect(native.secrets, isEmpty);
      expect(provider.connection.status, ConnectionStatus.notConnected);
    });
  });
}
