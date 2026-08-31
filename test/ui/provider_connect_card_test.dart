import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/provider_connection.dart';
import 'package:ai_usage_monitor/providers/provider_catalog.dart';
import 'package:ai_usage_monitor/providers/usage_provider.dart';
import 'package:ai_usage_monitor/services/usage_controller.dart';
import 'package:ai_usage_monitor/ui/panel/provider_connect_card.dart';
import 'package:ai_usage_monitor/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What each of the card's actions did, so a test can assert which one the
/// prominent button is wired to.
class CardCalls {
  int connect = 0;
  int useLocalOnly = 0;
  String? submitted;
}

Future<CardCalls> pumpCard(
  WidgetTester tester,
  ProviderDescriptor descriptor, {
  bool supportsLocalOnly = true,
  ConnectionStatus status = ConnectionStatus.notConnected,
}) async {
  final calls = CardCalls();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.of(Brightness.dark),
      home: Scaffold(
        body: SizedBox(
          width: 340,
          height: 320,
          child: ProviderConnectCard(
            state: ProviderState(
              descriptor: descriptor,
              connection: ProviderConnection(
                providerId: descriptor.id,
                status: status,
              ),
            ),
            supportsLocalOnly: supportsLocalOnly,
            onConnect: () async {
              calls.connect++;
              // What a key flow does: opens the browser and waits for a paste.
              return ProviderConnection(
                providerId: descriptor.id,
                status: ConnectionStatus.connecting,
              );
            },
            onSubmitCredential: (value) async {
              calls.submitted = value;
              return ProviderConnection(
                providerId: descriptor.id,
                status: ConnectionStatus.connected,
              );
            },
            onUseLocalOnly: () async {
              calls.useLocalOnly++;
              return ProviderConnection(
                providerId: descriptor.id,
                status: ConnectionStatus.connected,
              );
            },
            onDisconnect: () async {},
            onOpenUsage: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return calls;
}

void main() {
  group('a provider that needs no credential', () {
    test('Codex is one', () {
      // If this changes, the card below stops being the thing under test.
      expect(
        ProviderCatalog.chatgpt.authMethod,
        ProviderAuthMethod.localOnly,
      );
      expect(ProviderCatalog.chatgpt.displayName, 'Codex');
    });

    testWidgets('does not ask for a key up front', (tester) async {
      await pumpCard(tester, ProviderCatalog.chatgpt);

      // The bug this pins: the emphasised action opened OpenAI's key page and
      // put a "Paste your key" box on the card, for a figure that needs no key
      // at all — Codex has already signed in.
      expect(find.text('Paste the key you just created'), findsNothing);
      expect(find.textContaining('Paste your'), findsNothing);
    });

    testWidgets('the prominent action adopts the signed-in account',
        (tester) async {
      final calls = await pumpCard(tester, ProviderCatalog.chatgpt);

      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();

      expect(calls.useLocalOnly, 1);
      expect(calls.connect, 0);
    });

    testWidgets('offers exactly one Enable, not two', (tester) async {
      // Previously the emphasised button took its label from the auth method
      // ("Enable") and the secondary button was also labelled "Enable" — two
      // identical buttons doing different things.
      await pumpCard(tester, ProviderCatalog.chatgpt);

      expect(find.text('Enable'), findsOneWidget);
    });

    testWidgets('keeps the key available as a secondary action',
        (tester) async {
      final calls = await pumpCard(tester, ProviderCatalog.chatgpt);

      // Optional, not gone: a key still adds API spend reporting.
      await tester.tap(find.text('Add API key'));
      await tester.pumpAndSettle();

      expect(calls.connect, 1);
      // And *that* action is the one that ends in a paste box.
      expect(find.text('Paste the key you just created'), findsOneWidget);
    });

    testWidgets('Claude behaves the same way', (tester) async {
      final calls = await pumpCard(tester, ProviderCatalog.claude);

      expect(find.textContaining('Paste'), findsNothing);
      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();

      expect(calls.useLocalOnly, 1);
      expect(calls.connect, 0);
    });
  });

  group('a provider whose only way in is a key', () {
    testWidgets('still leads with the key flow', (tester) async {
      final calls = await pumpCard(
        tester,
        ProviderCatalog.openRouter,
        supportsLocalOnly: false,
      );

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(calls.connect, 1);
      // Named, because for this provider the key really is the OpenRouter key.
      expect(find.text('Paste your OpenRouter key'), findsOneWidget);
    });
  });
}
