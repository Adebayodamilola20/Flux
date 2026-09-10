import 'dart:convert';
import 'dart:io';

import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/usage_failure.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/providers/api/chatgpt_provider.dart';
import 'package:ai_usage_monitor/providers/chatgpt/codex_usage_source.dart';
import 'package:ai_usage_monitor/services/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_native_bridge.dart';

/// The documented shape of `GET /v1/organization/costs`.
String _costs(List<double> amounts) {
  return jsonEncode({
    'data': [
      for (final amount in amounts)
        {
          'object': 'bucket',
          'results': [
            {
              'object': 'organization.costs.result',
              'amount': {'value': amount, 'currency': 'usd'},
            },
          ],
        },
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge native;
  late SharedPreferences preferences;
  late Directory emptyHome;

  setUp(() async {
    emptyHome = Directory.systemTemp.createTempSync('chatgpt_provider_test');
    native = FakeNativeBridge();
    SharedPreferences.setMockInitialValues({
      'flutter.connection.chatgpt':
          '{"providerId":"chatgpt","status":"connected"}',
    });
    preferences = await SharedPreferences.getInstance();
  });

  tearDown(() {
    native.dispose();
    emptyHome.deleteSync(recursive: true);
  });

  Future<ChatGptProvider> build(
    http.Response Function(http.Request) handler,
  ) async {
    final provider = ChatGptProvider(
      native: native,
      connectionStore: ConnectionStore(preferences: preferences),
      httpClient: MockClient((request) async => handler(request)),
      // Pointed at an empty home so these tests measure the spend endpoint
      // alone. Left at its default it would read the developer's own Codex
      // transcripts, and the suite would pass or fail depending on whose
      // machine it ran on.
      codexSource: CodexUsageSource(homeDirectory: emptyHome.path),
    );
    await provider.restore();
    return provider;
  }

  void signIn([String key = 'sk-admin-abc']) {
    native.secrets['apikey.chatgpt'] = key;
  }

  test('sums the month’s daily buckets into a spend figure', () async {
    signIn();
    final provider = await build(
      (_) => http.Response(_costs([1.20, 0.55, 2.25]), 200),
    );

    final data = await provider.fetchUsage(const AppSettings());
    final spend = data.windows.single;

    expect(spend.consumed, 4.0);
    expect(spend.unit, 'USD');
    expect(spend.source, UsageSource.officialApi);
  });

  test('reports spend with no invented budget', () async {
    signIn();
    final provider = await build((_) => http.Response(_costs([3.0]), 200));

    final spend = (await provider.fetchUsage(const AppSettings())).windows.single;

    // OpenAI reports spend, not an allowance. A bar here would need a ceiling
    // this app made up.
    expect(spend.limit, isNull);
    expect(spend.percentUsed, isNull);
  });

  test('says plainly that this is API usage, not ChatGPT Plus', () async {
    signIn();
    final provider = await build((_) => http.Response(_costs([1.0]), 200));

    final data = await provider.fetchUsage(const AppSettings());
    expect(data.notes.join(), contains('not ChatGPT Plus'));
  });

  test('a month with no spend is zero, not an error', () async {
    signIn();
    final provider = await build((_) => http.Response(_costs([]), 200));

    final data = await provider.fetchUsage(const AppSettings());
    expect(data.windows.single.consumed, 0);
  });

  test('sends the key as a bearer token', () async {
    signIn('sk-admin-secret');
    late http.Request seen;
    final provider = await build((request) {
      seen = request;
      return http.Response(_costs([1.0]), 200);
    });

    await provider.fetchUsage(const AppSettings());

    expect(seen.headers['authorization'], 'Bearer sk-admin-secret');
    expect(seen.url.host, 'api.openai.com');
    expect(seen.url.toString(), isNot(contains('sk-admin')));
  });

  test('a key without permission explains what is needed', () async {
    signIn();
    final provider = await build((_) => http.Response('{}', 403));

    await expectLater(
      provider.fetchUsage(const AppSettings()),
      throwsA(
        isA<UsageFailure>().having(
          (f) => f.hint,
          'hint',
          contains('admin key'),
        ),
      ),
    );
  });

  test('an unrecognised shape fails rather than reading zero', () async {
    signIn();
    final provider = await build(
      (_) => http.Response(
        jsonEncode({
          'data': [
            {'results': [{'unexpected': true}]},
          ],
        }),
        200,
      ),
    );

    await expectLater(
      provider.fetchUsage(const AppSettings()),
      throwsA(isA<UsageFailure>()),
    );
  });

  group('a link that never had a key', () {
    // Codex is adopted from the account it is already signed in as, so there is
    // no secret behind the connection. Restore used to test every stored link
    // against the Keychain, find nothing, and write `notConnected` back to
    // disk — which is why the slot emptied itself and had to be re-added by
    // hand after every launch.
    test('survives a restart with nothing in the Keychain', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.connection.chatgpt':
            '{"providerId":"chatgpt","status":"connected",'
            '"usesStoredKey":false}',
      });
      preferences = await SharedPreferences.getInstance();

      final provider = await build((_) => http.Response(_costs([1.0]), 200));

      expect(native.secrets, isEmpty);
      expect(provider.connection.status, ConnectionStatus.connected);
    });

    test('and is still dropped when it did have one', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.connection.chatgpt':
            '{"providerId":"chatgpt","status":"connected",'
            '"usesStoredKey":true}',
      });
      preferences = await SharedPreferences.getInstance();

      final provider = await build((_) => http.Response(_costs([1.0]), 200));

      // The key this link rested on is gone, so the link really is broken.
      expect(provider.connection.status, ConnectionStatus.notConnected);
    });

    test('connecting with a key records that it rests on one', () async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final provider = await build((_) => http.Response(_costs([1.0]), 200));

      final result = await provider.completeAuthentication('sk-abc');

      expect(result.status, ConnectionStatus.connected);
      expect(result.usesStoredKey, isTrue);
    });
  });

  test('opens OpenAI’s own key page on connect', () async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    final provider = await build((_) => http.Response(_costs([1.0]), 200));

    final result = await provider.connect(launchUrl: native.openUrl);

    expect(native.openedUrls.single, contains('platform.openai.com'));
    expect(result.status, ConnectionStatus.connecting);
  });

  group('an empty allowance event never blanks a real figure', () {
    // Taken from a real transcript. OpenAI writes an allowance event after
    // every turn and some arrive with both windows null — a different limit
    // reported under the same roof. The app reported nothing while the CLI
    // showed a real percentage.
    String event({
      required String at,
      required String limitId,
      String primary = 'null',
    }) =>
        jsonEncode({
          'timestamp': at,
          'payload': {
            'rate_limits': {
              'limit_id': limitId,
              'primary': primary == 'null' ? null : jsonDecode(primary),
              'secondary': null,
            },
          },
        });

    test('a later null-window event does not erase an earlier figure',
        () async {
      final dir = Directory('${emptyHome.path}/.codex/sessions')
        ..createSync(recursive: true);
      File('${dir.path}/rollout.jsonl').writeAsStringSync([
        event(
          at: '2026-09-05T09:00:00Z',
          limitId: 'codex',
          primary: '{"used_percent":24.0,"window_minutes":43200}',
        ),
        // The turn that followed reported no window at all.
        event(at: '2026-09-05T09:05:00Z', limitId: 'codex'),
      ].join('\n'));

      final source = CodexUsageSource(homeDirectory: emptyHome.path);
      final reading = await source.read();

      expect(reading.hasUsage, isTrue);
      expect(reading.windows.first.consumed, 24);
    });

    test('a transcript with only empty events is not the final answer',
        () async {
      final dir = Directory('${emptyHome.path}/.codex/sessions/2026/09/05')
        ..createSync(recursive: true);
      // Newest file, allowance mentioned but no figure in it.
      File('${dir.path}/new.jsonl').writeAsStringSync(
        event(at: '2026-09-05T10:00:00Z', limitId: 'codex'),
      );
      final older = File('${emptyHome.path}/.codex/sessions/old.jsonl')
        ..writeAsStringSync(event(
          at: '2026-09-04T10:00:00Z',
          limitId: 'codex',
          primary: '{"used_percent":61.0,"window_minutes":43200}',
        ));
      older.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));

      final source = CodexUsageSource(homeDirectory: emptyHome.path);
      final reading = await source.read();

      expect(reading.hasUsage, isTrue,
          reason: 'the scan must keep going back until a figure turns up');
      expect(reading.windows.first.consumed, 61);
    });
  });
}
