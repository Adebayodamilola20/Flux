import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/usage_failure.dart';
import 'package:ai_usage_monitor/providers/provider_catalog.dart';
import 'package:ai_usage_monitor/providers/provider_registry.dart';
import 'package:ai_usage_monitor/providers/reserved_provider.dart';
import 'package:ai_usage_monitor/providers/usage_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_provider.dart';

void main() {
  List<UsageProvider> railProviders() => [
    FakeProvider(id: 'claude', displayName: 'Claude'),
    FakeProvider(id: 'chatgpt', displayName: 'Codex'),
    FakeProvider(id: 'opencode', displayName: 'OpenCode'),
  ];

  group('ProviderCatalog', () {
    test('offers more providers than the rail has positions', () {
      // The two numbers are deliberately different. Equal, every position
      // would have a provider attached to it by default, which is what made
      // an unfilled plus describe a provider the user had never chosen.
      expect(
        ProviderCatalog.available.length,
        greaterThan(ProviderCatalog.slotCount),
      );
    });

    test('gives every provider a unique id', () {
      final ids = ProviderCatalog.available.map((s) => s.id).toSet();
      expect(ids, hasLength(ProviderCatalog.available.length));
    });

    test('names the providers that have a real integration', () {
      final implemented = ProviderCatalog.available
          .where((s) => s.isImplemented)
          .map((s) => s.id);
      expect(implemented, [
        'claude',
        'chatgpt',
        'opencode',
        'kilocode',
        'antigravity',
        'hermes',
        'openrouter',
      ]);
    });

    test('a provider is reserved only while it has no integration', () {
      // Guards the pairing the composition root depends on: standing a
      // ReservedProvider in front of an implemented slot would silently
      // disable it.
      for (final slot in ProviderCatalog.available) {
        if (slot.isImplemented) {
          expect(() => ReservedProvider(slot), throwsA(isA<AssertionError>()));
        } else {
          expect(() => ReservedProvider(slot), returnsNormally);
        }
      }
    });
  });

  group('ProviderRegistry', () {
    test('accepts a build with more providers than rail positions', () {
      final registry = ProviderRegistry([
        ...railProviders(),
        FakeProvider(id: 'hermes', displayName: 'Hermes'),
      ]);

      expect(registry.all, hasLength(ProviderCatalog.slotCount + 1));
      expect(registry.primary.id, 'claude');
      expect(registry.byId('opencode'), isNotNull);
      expect(registry.byId('nope'), isNull);
    });

    test('rejects a build with too few to fill the rail', () {
      // Fewer providers than positions would leave a plus that can never be
      // filled, which should stop startup rather than render.
      expect(
        () => ProviderRegistry([FakeProvider(id: 'claude')]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects duplicate provider ids', () {
      expect(
        () => ProviderRegistry([
          FakeProvider(id: 'claude'),
          FakeProvider(id: 'claude'),
          FakeProvider(id: 'a'),
        ]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('lists only the slots with a real integration', () {
      final registry = ProviderRegistry([
        FakeProvider(id: 'claude'),
        ReservedProvider(ProviderCatalog.reserved),
        FakeProvider(id: 'opencode', displayName: 'OpenCode'),
      ]);

      // FakeProvider declares itself implemented; only the genuinely reserved
      // slot is filtered out.
      expect(
        registry.implemented.map((p) => p.id),
        isNot(contains('reserved')),
      );
    });
  });

  group('ReservedProvider', () {
    test('reports itself as unsupported rather than disconnected', () {
      final provider = ReservedProvider(ProviderCatalog.reserved);
      expect(provider.connection.status, ConnectionStatus.unsupported);
      expect(provider.connection.status.isReserved, isTrue);
    });

    test('refuses to fetch instead of returning a fabricated figure', () {
      final provider = ReservedProvider(ProviderCatalog.reserved);
      expect(
        () => provider.fetchUsage(const AppSettings()),
        throwsA(
          isA<UsageFailure>().having(
            (f) => f.kind,
            'kind',
            UsageFailureKind.notConfigured,
          ),
        ),
      );
    });

    test('does not open a browser for a flow that cannot complete', () async {
      final provider = ReservedProvider(ProviderCatalog.reserved);
      var launched = 0;

      final result = await provider.connect(
        launchUrl: (_) async {
          launched++;
          return true;
        },
      );

      expect(launched, 0);
      expect(result.status, ConnectionStatus.unsupported);
    });

    test('cannot stand in for a slot that is implemented', () {
      expect(
        () => ReservedProvider(ProviderCatalog.claude),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
