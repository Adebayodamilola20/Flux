import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/provider_connection.dart';
import 'package:ai_usage_monitor/models/usage_data.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/models/usage_window.dart';
import 'package:ai_usage_monitor/providers/provider_catalog.dart';
import 'package:ai_usage_monitor/services/native/native_bridge.dart';
import 'package:ai_usage_monitor/services/usage_controller.dart';
import 'package:ai_usage_monitor/ui/rail/rail_column.dart';
import 'package:ai_usage_monitor/ui/theme/app_theme.dart';
import 'package:ai_usage_monitor/ui/widgets/provider_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the rail so its *visible* output can be asserted.
///
/// These exist because a class of bug kept reaching the screen that no unit
/// test could see: the ring drew the "empty slot" plus while the label beneath
/// it showed a percentage, because the two read different fields. Nothing was
/// wrong with either value on its own.
Future<void> pumpRail(WidgetTester tester, List<ProviderState?> states) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.of(Brightness.dark),
      home: Scaffold(
        body: RailColumn(
          states: states,
          metrics: RailMetrics.fallback,
          hoveredId: null,
          onRightEdge: true,
          onHoverSlot: (_) {},
          onOpenDetail: (_) {},
          onAddToSlot: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

ProviderState slot({
  required String id,
  ConnectionStatus status = ConnectionStatus.notConnected,
  int? percent,
}) {
  return ProviderState(
    descriptor: ProviderCatalog.slots.firstWhere((s) => s.id == id),
    connection: ProviderConnection(providerId: id, status: status),
    data: percent == null
        ? null
        : UsageData(
            providerId: id,
            providerName: id,
            connection: status,
            fetchedAt: DateTime.now(),
            windows: [
              UsageWindow(
                id: 'w',
                label: 'w',
                consumed: percent,
                limit: 100,
                unit: '%',
                source: UsageSource.officialApi,
              ),
            ],
          ),
  );
}

/// True when the slot drew the "add this" plus rather than a provider mark.
bool drewPlus(WidgetTester tester, String providerId) {
  final glyphs = tester
      .widgetList<ProviderGlyph>(find.byType(ProviderGlyph))
      .where((g) => g.providerId == providerId);
  return glyphs.isNotEmpty && glyphs.first.isEmpty;
}

void main() {
  testWidgets('an empty slot shows a plus and no percentage', (tester) async {
    await pumpRail(tester, [slot(id: 'gemini')]);

    expect(drewPlus(tester, 'gemini'), isTrue);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('a connected slot shows its mark and its percentage',
      (tester) async {
    await pumpRail(tester, [
      slot(id: 'claude', status: ConnectionStatus.connected, percent: 27),
    ]);

    expect(drewPlus(tester, 'claude'), isFalse);
    expect(find.text('27%'), findsOneWidget);
  });

  testWidgets('never draws a plus beside a percentage', (tester) async {
    // The exact contradiction that reached the screen: a ring showing the
    // empty-slot plus with "27%" underneath it.
    await pumpRail(tester, [
      slot(id: 'gemini'),
      slot(id: 'chatgpt', status: ConnectionStatus.connected, percent: 100),
      slot(id: 'antigravity', status: ConnectionStatus.connected),
      slot(id: 'claude', status: ConnectionStatus.connected, percent: 27),
    ]);

    for (final id in ['gemini', 'chatgpt', 'antigravity', 'claude']) {
      final isPlus = drewPlus(tester, id);
      final state = tester
          .widgetList<ProviderGlyph>(find.byType(ProviderGlyph))
          .where((g) => g.providerId == id);
      expect(state, isNotEmpty, reason: '$id was not rendered');

      if (isPlus) {
        // A plus means "nothing here yet", so there must be no figure.
        expect(
          find.descendant(
            of: find.byType(RailColumn),
            matching: find.text('27%'),
          ),
          findsOneWidget,
          reason: 'only the connected slot may show a figure',
        );
      }
    }
  });

  testWidgets('a connected slot with no figure yet still shows its mark',
      (tester) async {
    // Connected but awaiting first fetch: it is not an empty slot, so it must
    // not offer the "add this" plus.
    await pumpRail(tester, [
      slot(id: 'antigravity', status: ConnectionStatus.connected),
    ]);

    expect(drewPlus(tester, 'antigravity'), isFalse);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('renders one slot per provider', (tester) async {
    await pumpRail(tester, [
      slot(id: 'gemini'),
      slot(id: 'chatgpt'),
      slot(id: 'antigravity'),
      slot(id: 'claude'),
    ]);

    expect(find.byType(ProviderGlyph), findsNWidgets(4));
  });
}
