import 'dart:convert';
import 'dart:io';

import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/providers/gemini/gemini_code_assist_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Writes the credential file Gemini CLI stores after a sign-in.
void writeCredentials(String home, {DateTime? expiry}) {
  Directory('$home/.gemini').createSync(recursive: true);
  File('$home/.gemini/oauth_creds.json').writeAsStringSync(
    jsonEncode({
      'access_token': 'ya29.test-token',
      'refresh_token': 'refresh',
      if (expiry != null) 'expiry_date': expiry.millisecondsSinceEpoch,
    }),
  );
}

/// The shape `retrieveUserQuota` returns.
String quotaBody() => jsonEncode({
      'buckets': [
        {
          'modelId': 'gemini-3-pro-preview',
          'remainingFraction': 0.42,
          'resetTime': '2026-09-03T18:00:00.000Z',
        },
        {
          'modelId': 'gemini-3-flash',
          'remainingFraction': 0.9,
        },
      ],
    });

String loadBody() => jsonEncode({
      'cloudaicompanionProject': 'projects/12345',
      'currentTier': {'id': 'STANDARD', 'name': 'Google AI Pro'},
    });

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('gemini_quota_test');
  });

  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  test('says nothing is signed in when the CLI has no credentials', () async {
    final source = GeminiCodeAssistSource(
      homeDirectory: home.path,
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(source.isSignedIn, isFalse);
    final (reading, failure) = await source.fetch();
    expect(reading, isNull);
    expect(failure, GeminiQuotaFailure.notSignedIn);
  });

  test('asks Google for the quota without sending a prompt', () async {
    // The correction this whole source rests on: `retrieveUserQuota` is an
    // ordinary request. Gemini CLI only ever calls it after a model response,
    // which made it look like the quota cost an allowance to measure. It does
    // not — nothing here generates content.
    writeCredentials(home.path, expiry: DateTime.now().add(const Duration(hours: 1)));

    final calls = <String>[];
    final source = GeminiCodeAssistSource(
      homeDirectory: home.path,
      client: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path.contains('loadCodeAssist')) {
          return http.Response(loadBody(), 200);
        }
        return http.Response(quotaBody(), 200);
      }),
    );

    final (reading, failure) = await source.fetch();

    expect(failure, isNull);
    expect(calls.any((c) => c.contains('generateContent')), isFalse);
    expect(reading!.tierLabel, 'Google AI Pro');
  });

  test('reports consumption, not what is left', () async {
    writeCredentials(home.path, expiry: DateTime.now().add(const Duration(hours: 1)));
    final source = GeminiCodeAssistSource(
      homeDirectory: home.path,
      client: MockClient((request) async => http.Response(
            request.url.path.contains('loadCodeAssist')
                ? loadBody()
                : quotaBody(),
            200,
          )),
    );

    final (reading, _) = await source.fetch();
    final windows = reading!.windows;

    // 42% remaining is 58% used. Reading the fraction at face value would put
    // the ring at 42% and understate how close the user is to the limit.
    expect(windows.first.label, 'Gemini 3 Pro');
    expect(windows.first.percentUsed, 58);
    expect(windows.last.percentUsed, 10);
    expect(windows.first.source, UsageSource.officialApi);
    expect(windows.first.resetsAt, isNotNull);
  });

  test('discovers the project once and reuses it', () async {
    writeCredentials(home.path, expiry: DateTime.now().add(const Duration(hours: 1)));
    var loads = 0;
    final source = GeminiCodeAssistSource(
      homeDirectory: home.path,
      client: MockClient((request) async {
        if (request.url.path.contains('loadCodeAssist')) {
          loads++;
          return http.Response(loadBody(), 200);
        }
        return http.Response(quotaBody(), 200);
      }),
    );

    await source.fetch();
    await source.fetch();
    await source.fetch();

    // The project does not change between refreshes; asking each time would
    // double the requests for nothing.
    expect(loads, 1);
  });

  test('does not use an expired token', () async {
    writeCredentials(
      home.path,
      expiry: DateTime.now().subtract(const Duration(hours: 1)),
    );
    var requests = 0;
    final source = GeminiCodeAssistSource(
      homeDirectory: home.path,
      client: MockClient((_) async {
        requests++;
        return http.Response(quotaBody(), 200);
      }),
    );

    final (reading, failure) = await source.fetch();

    // Refreshing it would mean presenting Gemini CLI's OAuth client as ours.
    expect(reading, isNull);
    expect(failure, GeminiQuotaFailure.tokenExpired);
    expect(requests, 0);
  });

  test('separates a rejected token from a broken response', () async {
    writeCredentials(home.path, expiry: DateTime.now().add(const Duration(hours: 1)));
    final source = GeminiCodeAssistSource(
      homeDirectory: home.path,
      client: MockClient((_) async => http.Response('nope', 401)),
    );

    final (_, failure) = await source.fetch();
    expect(failure, GeminiQuotaFailure.unauthorized);
  });

  test('reports no project rather than inventing a figure', () async {
    writeCredentials(home.path, expiry: DateTime.now().add(const Duration(hours: 1)));
    final source = GeminiCodeAssistSource(
      homeDirectory: home.path,
      client: MockClient(
        (_) async => http.Response(jsonEncode({'currentTier': {}}), 200),
      ),
    );

    final (reading, failure) = await source.fetch();
    expect(reading, isNull);
    expect(failure, GeminiQuotaFailure.noProject);
  });

  group('model labels', () {
    test('reads as a person would write it', () {
      expect(
        GeminiCodeAssistSource.modelLabel('gemini-3-pro-preview'),
        'Gemini 3 Pro',
      );
      expect(
        GeminiCodeAssistSource.modelLabel('gemini-3-flash'),
        'Gemini 3 Flash',
      );
    });
  });
}
