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
  /// Two non-Claude slots. Only codex ships unimplemented now that
  /// Antigravity has a real integration, so the other is a stand-in.
  List<UsageProvider> reserved() => [
    ReservedProvider(ProviderCatalog.reserved),
    FakeProvider(id: 'antigravity', displayName: 'Antigravity'),
    FakeProvider(id: 'openrouter', displayName: 'OpenRouter'),
  ];

  group('ProviderCatalog', () {
    test('declares exactly the number of slots the rail is built for', () {
      expect(ProviderCatalog.slots, hasLength(ProviderCatalog.slotCount));
    });

    test('gives every slot a unique id', () {
      final ids = ProviderCatalog.slots.map((s) => s.id).toSet();
      expect(ids, hasLength(ProviderCatalog.slotCount));
    });

    test('names the slots that have a real integration', () {
      final implemented = ProviderCatalog.slots
          .where((s) => s.isImplemented)
          .map((s) => s.id);
      expect(implemented, containsAll(<String>['claude', 'antigravity']));
    });

    test('a slot is reserved only while it has no integration', () {
      // Guards the pairing the composition root depends on: standing a
      // ReservedProvider in front of an implemented slot would silently
      // disable it.
      for (final slot in ProviderCatalog.slots) {
        if (slot.isImplemented) {
          expect(() => ReservedProvider(slot), throwsA(isA<AssertionError>()));
        } else {
          expect(() => ReservedProvider(slot), returnsNormally);
        }
      }
    });
  });

  group('ProviderRegistry', () {
    test('accepts the full set of slots', () {
      final registry = ProviderRegistry([
        FakeProvider(id: 'claude'),
        ...reserved(),
      ]);

      expect(registry.all, hasLength(ProviderCatalog.slotCount));
      expect(registry.primary.id, 'claude');
      expect(registry.byId('antigravity'), isNotNull);
      expect(registry.byId('nope'), isNull);
    });

    test('rejects a build wired with the wrong number of slots', () {
      // The rail's layout is designed around three rings; a mismatch should stop
      // startup rather than render wrong.
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
        ...reserved(),
      ]);

      // FakeProvider declares itself implemented; only the genuinely reserved
      // codex slot is filtered out.
      expect(registry.implemented.map((p) => p.id), isNot(contains('reserved')));
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
