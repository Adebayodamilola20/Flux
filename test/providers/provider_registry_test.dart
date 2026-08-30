import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/usage_failure.dart';
import 'package:ai_usage_monitor/providers/provider_catalog.dart';
import 'package:ai_usage_monitor/providers/provider_registry.dart';
import 'package:ai_usage_monitor/providers/reserved_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_provider.dart';

void main() {
  List<ReservedProvider> reserved() => [
    ReservedProvider(ProviderCatalog.codex),
    ReservedProvider(ProviderCatalog.antigravity),
  ];

  group('ProviderCatalog', () {
    test('declares exactly the number of slots the rail is built for', () {
      expect(ProviderCatalog.slots, hasLength(ProviderCatalog.slotCount));
    });

    test('gives every slot a unique id', () {
      final ids = ProviderCatalog.slots.map((s) => s.id).toSet();
      expect(ids, hasLength(ProviderCatalog.slotCount));
    });

    test('ships exactly one implemented slot in this build', () {
      final implemented = ProviderCatalog.slots
          .where((s) => s.isImplemented)
          .toList();
      expect(implemented, hasLength(1));
      expect(implemented.single.id, 'claude');
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

      expect(registry.implemented.map((p) => p.id), ['claude']);
    });
  });

  group('ReservedProvider', () {
    test('reports itself as unsupported rather than disconnected', () {
      final provider = ReservedProvider(ProviderCatalog.codex);
      expect(provider.connection.status, ConnectionStatus.unsupported);
      expect(provider.connection.status.isReserved, isTrue);
    });

    test('refuses to fetch instead of returning a fabricated figure', () {
      final provider = ReservedProvider(ProviderCatalog.antigravity);
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
      final provider = ReservedProvider(ProviderCatalog.codex);
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
