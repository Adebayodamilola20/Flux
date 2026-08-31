import 'dart:convert';
import 'dart:io';

import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/providers/antigravity/antigravity_usage_provider.dart';
import 'package:ai_usage_monitor/providers/gemini/gemini_cli_account.dart';
import 'package:ai_usage_monitor/providers/gemini/gemini_code_assist_source.dart';
import 'package:ai_usage_monitor/providers/gemini/gemini_usage_provider.dart';
import 'package:ai_usage_monitor/services/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_native_bridge.dart';

/// The `/usage` panel `agy` 1.1.22 draws, captured verbatim.
const agyPanel = '  someone@example.com (Antigravity Starter Quota)\n'
    'GEMINI MODELS\n'
    '  Weekly Limit Remaining\n'
    '    [█████████████████████████████████████████████████░] 98.98%\n'
    '    99% remaining · Refreshes in 145h 16m\n'
    'CLAUDE AND GPT MODELS\n'
    '    [██████████████████████████████████████████████████] 100.00%\n'
    '    Quota available\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge native;
  late SharedPreferences preferences;
  late ConnectionStore connections;
  late Directory home;

  setUp(() async {
    native = FakeNativeBridge();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    connections = ConnectionStore(preferences: preferences);
    home = Directory.systemTemp.createTempSync('cli_provider_test');
  });

  tearDown(() {
    native.dispose();
    home.deleteSync(recursive: true);
  });

  void installAgy({String output = agyPanel}) {
    native.installedClis['agy'] = '/usr/local/bin/agy';
    native.probeResult = {
      'launched': true,
      'timedOut': false,
      'output': output,
    };
  }

  AntigravityUsageProvider buildAntigravity() => AntigravityUsageProvider(
        native: native,
        connectionStore: connections,
      );

  group('a slot turns itself on', () {
    test('adopts the provider when its CLI is installed', () async {
      installAgy();
      final provider = buildAntigravity();

      await provider.restore();
      // Nothing is adopted automatically now — the rail starts empty and the
      // user decides what goes on it. Adding is what connects.
      expect(provider.connection.isConnected, isFalse);

      await provider.enableLocalOnly();

      // And adding is the only click: no browser, no Google consent screen.
      expect(provider.connection.status, ConnectionStatus.connected);
      expect(native.openedUrls, isEmpty);
    });

    test('refuses to connect when the CLI is not installed', () async {
      final provider = buildAntigravity();

      await provider.restore();
      await provider.enableLocalOnly();

      expect(provider.connection.isConnected, isFalse);
    });

    test('remembers being connected across a restart', () async {
      installAgy();

      final first = buildAntigravity();
      await first.restore();
      await first.enableLocalOnly();

      final second = buildAntigravity();
      await second.restore();

      expect(second.connection.isConnected, isTrue);
    });

    test('stays off after a deliberate disconnect', () async {
      installAgy();

      final first = buildAntigravity();
      await first.restore();
      await first.enableLocalOnly();
      await first.disconnect();

      final second = buildAntigravity();
      await second.restore();

      expect(second.connection.isConnected, isFalse);
    });
  });

  group('Antigravity usage', () {
    test('reports the weekly limit per model group', () async {
      installAgy();
      final provider = buildAntigravity();
      await provider.restore();
      await provider.enableLocalOnly();

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.isUsageUnavailable, isFalse);
      expect(data.windows.map((w) => w.label), [
        'Gemini models',
        'Claude and GPT models',
      ]);
      // "98.98% remaining" is 1% used, not 99%.
      expect(data.windows.first.percentUsed, 1);
      expect(data.windows.last.percentUsed, 0);
    });

    test('never opens a browser', () async {
      installAgy();
      final provider = buildAntigravity();

      await provider.restore();
      await provider.connect(launchUrl: (_) async => true);
      await provider.fetchUsage(const AppSettings());

      // Connect and Enable do the same thing now, and neither is a sign-in.
      expect(native.openedUrls, isEmpty);
      expect(provider.connection.status, ConnectionStatus.connected);
    });

    test('says the CLI is signed out rather than "usage unavailable"',
        () async {
      installAgy(output: 'You are currently not signed in.\n');
      final provider = buildAntigravity();
      await provider.restore();
      await provider.enableLocalOnly();

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.usageUnavailableReason, contains('not signed in'));
      // Fixable, so a retry is worth offering.
      expect(data.usageUnavailableIsPermanent, isFalse);
    });

    test('does not call a signed-in session signed out', () async {
      // `agy` opens with "You are currently not signed in." and *then* signs
      // itself in from a stored session. Reading that banner as the verdict
      // told a signed-in user to go and sign in — and because the real cause
      // was a probe that ran out of time, pressing Retry changed nothing.
      installAgy(
        output: 'Welcome to the Antigravity CLI. You are currently not '
            'signed in.\n'
            '  Signing in...\n'
            '  Antigravity CLI 1.1.22\n'
            '  someone@example.com (Antigravity Starter Quota)\n'
            '  > \n',
      );
      final provider = buildAntigravity();
      await provider.restore();
      await provider.enableLocalOnly();

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.usageUnavailableReason, isNot(contains('not signed in')));
      expect(data.usageUnavailableReason, contains('did not show'));
    });

    test('runs the CLI somewhere small, not in the app’s own directory',
        () async {
      // An app launched from Finder has `/` as its working directory. These
      // CLIs treat that as a workspace to index, and `agy` then spends so long
      // starting that the usage command never lands.
      installAgy();
      final provider = buildAntigravity();
      await provider.restore();
      await provider.enableLocalOnly();
      await provider.fetchUsage(const AppSettings());

      final probe = native.probes.single;
      expect(probe.workingDirectory, isNotNull);
      expect(probe.workingDirectory, isNot('/'));
      // And enough time for a CLI that signs itself in before it draws.
      expect(probe.timeout, greaterThanOrEqualTo(40));
    });
  });

  group('Gemini', () {
    GeminiUsageProvider buildGemini({
      required http.Response Function(http.Request) handler,
    }) =>
        GeminiUsageProvider(
          native: native,
          connectionStore: connections,
          accountSource: GeminiCliAccountSource(homeDirectory: home.path),
          quotaSource: GeminiCodeAssistSource(
            homeDirectory: home.path,
            client: MockClient((request) async => handler(request)),
          ),
        );

    void writeAccounts(String? active) {
      Directory('${home.path}/.gemini').createSync(recursive: true);
      File('${home.path}/.gemini/google_accounts.json').writeAsStringSync(
        active == null
            ? '{"active": null, "old": ["someone@example.com"]}'
            : '{"active": "$active", "old": []}',
      );
    }

    void signInCli() {
      Directory('${home.path}/.gemini').createSync(recursive: true);
      File('${home.path}/.gemini/oauth_creds.json').writeAsStringSync(
        jsonEncode({
          'access_token': 'ya29.test',
          'expiry_date':
              DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
        }),
      );
    }

    http.Response quotaHandler(http.Request request) {
      if (request.url.path.contains('loadCodeAssist')) {
        return http.Response(
          jsonEncode({
            'cloudaicompanionProject': 'projects/1',
            'currentTier': {'name': 'Google AI Pro'},
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'buckets': [
            {'modelId': 'gemini-3-pro', 'remainingFraction': 0.25},
          ],
        }),
        200,
      );
    }

    test('shows a real percentage once the CLI is signed in', () async {
      // The slot used to report that no Gemini quota existed at all. It does:
      // `retrieveUserQuota` is an ordinary request, not a by-product of
      // sending a prompt.
      native.installedClis['gemini'] = '/usr/local/bin/gemini';
      writeAccounts('someone@example.com');
      signInCli();

      final provider = buildGemini(handler: quotaHandler);
      await provider.restore();
      await provider.enableLocalOnly();
      final data = await provider.fetchUsage(const AppSettings());

      expect(data.isUsageUnavailable, isFalse);
      expect(data.windows.single.label, 'Gemini 3 Pro');
      // 25% left is 75% used.
      expect(data.windows.single.percentUsed, 75);
      expect(data.accountLabel, 'someone@example.com');
    });

    test('never drives the CLI, because it asks Google directly', () async {
      native.installedClis['gemini'] = '/usr/local/bin/gemini';
      writeAccounts('someone@example.com');
      signInCli();

      final provider = buildGemini(handler: quotaHandler);
      await provider.restore();
      await provider.enableLocalOnly();
      await provider.fetchUsage(const AppSettings());

      // Starting the CLI for half a minute would tell us nothing the request
      // does not.
      expect(native.probes, isEmpty);
    });

    test('says to sign in to the CLI when there is no session', () async {
      native.installedClis['gemini'] = '/usr/local/bin/gemini';
      writeAccounts(null);

      final provider = buildGemini(
        handler: (_) => http.Response('{}', 200),
      );
      await provider.restore();
      await provider.enableLocalOnly();
      final data = await provider.fetchUsage(const AppSettings());

      // Actionable, and true: signing in is what makes the figure appear.
      expect(data.usageUnavailableReason, contains('not signed in'));
      expect(data.usageUnavailableReason, contains('quota appears here'));
      // Fixable, so Retry is worth offering.
      expect(data.usageUnavailableIsPermanent, isFalse);
    });
  });
}
