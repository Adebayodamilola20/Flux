import 'dart:convert';

import 'package:ai_usage_monitor/services/auth/oauth_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The file Google hands you for a Desktop app client.
String _installedClient({
  String clientId = '937871002031-abc.apps.googleusercontent.com',
  String? secret = 'GOCSPX-example',
}) {
  return jsonEncode({
    'installed': {
      'client_id': clientId,
      'project_id': 'example-project',
      'auth_uri': 'https://accounts.google.com/o/oauth2/auth',
      'token_uri': 'https://oauth2.googleapis.com/token',
      if (secret != null) 'client_secret': secret,
      'redirect_uris': ['http://localhost'],
    },
  });
}

/// The file you get if you pick the wrong client type.
String _webClient() {
  return jsonEncode({
    'web': {
      'client_id': 'web-client.apps.googleusercontent.com',
      'client_secret': 'GOCSPX-web',
      'redirect_uris': ['https://example.com/callback'],
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late OAuthRegistry registry;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    registry = OAuthRegistry(preferences: preferences);
  });

  group('client configuration', () {
    test('is unconfigured until a client is set', () {
      expect(registry.isConfigured('antigravity'), isFalse);
      expect(registry.configFor('antigravity')!.isConfigured, isFalse);
    });

    test('has no OAuth definition for providers that do not use it', () {
      expect(registry.supports('claude'), isFalse);
      expect(registry.configFor('claude'), isNull);
    });
  });

  group('importing Google’s client file', () {
    test('accepts a Desktop app client', () async {
      final id = await registry.importGoogleClientFile(
        _installedClient(),
        'antigravity',
      );

      expect(id, '937871002031-abc.apps.googleusercontent.com');
      expect(registry.isConfigured('antigravity'), isTrue);
      expect(registry.configFor('antigravity')!.clientSecret, 'GOCSPX-example');
    });

    test('rejects a Web client with an explanation', () async {
      final contents = _webClient();

      final id = await registry.importGoogleClientFile(contents, 'antigravity');

      // A web client cannot use the loopback redirect, and accepting it would
      // fail later as an opaque redirect_uri_mismatch in the browser.
      expect(id, isNull);
      expect(registry.isConfigured('antigravity'), isFalse);
      expect(
        OAuthRegistry.importRejectionReason(contents),
        contains('Desktop app'),
      );
    });

    test('rejects a file that is not JSON', () async {
      expect(
        await registry.importGoogleClientFile('not json', 'antigravity'),
        isNull,
      );
      expect(
        OAuthRegistry.importRejectionReason('not json'),
        contains('valid JSON'),
      );
    });

    test('rejects JSON that is not a client file', () async {
      expect(
        await registry.importGoogleClientFile('{"hello":true}', 'antigravity'),
        isNull,
      );
    });

    test('accepts a client with no secret', () async {
      final id = await registry.importGoogleClientFile(
        _installedClient(secret: null),
        'antigravity',
      );

      expect(id, isNotNull);
      expect(registry.configFor('antigravity')!.clientSecret, isNull);
    });

    test('configures only the provider it was imported for', () async {
      await registry.importGoogleClientFile(_installedClient(), 'antigravity');

      expect(registry.isConfigured('antigravity'), isTrue);
      // A provider with no OAuth definition is unaffected by any import —
      // these are per-provider clients, not one shared credential.
      expect(registry.supports('opencode'), isFalse);
      expect(registry.isConfigured('opencode'), isFalse);
    });
  });

  group('scopes', () {
    test('asks only for what the app actually calls', () {
      final scopes = registry.configFor('antigravity')!.scopes;

      // Requesting a broad scope the app never uses drags the user through
      // Google's unverified-app warning for nothing.
      expect(scopes, ['openid', 'email']);
      expect(scopes.any((s) => s.contains('cloud-platform')), isFalse);
    });

    test('requests offline access so the link survives an hour', () {
      final extra = registry.configFor('antigravity')!.extraAuthParameters;
      expect(extra['access_type'], 'offline');
    });
  });
}
