import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/provider_connection.dart';
import 'package:ai_usage_monitor/models/usage_data.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/models/usage_window.dart';
import 'package:ai_usage_monitor/providers/provider_catalog.dart';
import 'package:ai_usage_monitor/services/native/native_bridge.dart';
import 'package:ai_usage_monitor/services/usage_controller.dart';
import 'package:ai_usage_monitor/ui/rail/rail_callout.dart';
import 'package:ai_usage_monitor/ui/rail/rail_column.dart';
import 'package:ai_usage_monitor/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the product shot from the app's own widgets.
///
/// Not a mock-up and not a redrawing: the rail and the card below are the same
/// `RailColumn` and `RailCallout` the app builds at runtime, given real
/// `ProviderState`s. Every ring, glyph, percentage, weight and spacing is
/// therefore the shipped design by construction rather than by resemblance —
/// which is the one thing a generated image cannot promise.
const double kWidth = 2560;
const double kHeight = 1440; // 16:9

/// The rail at presentation size. Same proportions the app derives from a
/// display; only the multiplier is ours, so the UI is crisp at this width.
const double kScale = 2.4;

RailMetrics metrics() => RailMetrics(
      collapsedWidth: 46 * kScale,
      expandedWidth: 280 * kScale,
      slotHeight: 66 * kScale,
      collapsedVerticalPadding: 28 * kScale,
      shadowPadding: 26 * kScale,
      settingsButtonSize: 34 * kScale,
      settingsButtonGap: -4 * kScale,
      edgeInset: 0,
      windowWidth: 332 * kScale,
      windowHeight: 344 * kScale,
      slots: 3,
      scale: kScale,
    );

ProviderState provider(
  String id, {
  required List<UsageWindow> windows,
  String? accountLabel,
  List<String> notes = const [],
}) {
  return ProviderState(
    descriptor: ProviderCatalog.available.firstWhere((s) => s.id == id),
    connection: ProviderConnection(
      providerId: id,
      status: ConnectionStatus.connected,
      accountLabel: accountLabel,
    ),
    data: UsageData(
      providerId: id,
      providerName: id,
      connection: ConnectionStatus.connected,
      fetchedAt: DateTime.now(),
      accountLabel: accountLabel,
      windows: windows,
      notes: notes,
    ),
  );
}

UsageWindow window(
  String id,
  String label,
  num used, {
  Duration? resetsIn,
}) {
  return UsageWindow(
    id: id,
    label: label,
    consumed: used,
    limit: 100,
    unit: 'percent',
    resetsAt: resetsIn == null ? null : DateTime.now().add(resetsIn),
    source: UsageSource.officialApi,
  );
}

/// A soft, deep wallpaper. Two washes of light over a dark base, the way a
/// desktop picture lights a screen — enough to sit the notch against without
/// competing with it.
class _Wallpaper extends StatelessWidget {
  const _Wallpaper();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1E2233),
                Color(0xFF2A3350),
                Color(0xFF141826),
              ],
              stops: [0, 0.5, 1],
            ),
          ),
        ),
        // Warm light from the upper left, cool from the lower right. Kept very
        // low in opacity: the point of the composition is the notch.
        Align(
          alignment: const Alignment(-0.75, -0.85),
          child: _Glow(color: const Color(0xFFFF8A5C), size: kWidth * 0.62),
        ),
        Align(
          alignment: const Alignment(0.55, 0.95),
          child: _Glow(color: const Color(0xFF4C7DFF), size: kWidth * 0.70),
        ),
        Align(
          alignment: const Alignment(0.95, -0.25),
          child: _Glow(color: const Color(0xFF29C7A8), size: kWidth * 0.42),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('product shot', (tester) async {
    // Real type rather than the test binding's placeholder font, which draws
    // every glyph as a filled box — the percentages have to be readable.
    for (final entry in const {
      'Marketing': '/System/Library/Fonts/Supplemental/Arial.ttf',
      'MarketingBold': '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
    }.entries) {
      final file = File(entry.value);
      if (!file.existsSync()) continue;
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
      await loader.load();
    }

    tester.view.physicalSize = const Size(kWidth, kHeight);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final m = metrics();

    final claude = provider(
      'claude',
      accountLabel: 'Claude Pro',
      windows: [
        window('five_hour', 'Current session', 53,
            resetsIn: const Duration(hours: 2, minutes: 40)),
        window('seven_day', 'This week', 36,
            resetsIn: const Duration(days: 3, hours: 5)),
      ],
      notes: const ['Claude Pro', 'Live from Anthropic, just now.'],
    );
    final codex = provider(
      'chatgpt',
      windows: [window('codex', 'Codex allowance', 6)],
    );
    final opencode = provider(
      'opencode',
      windows: [window('context', 'big-pickle', 34)],
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(kWidth, kHeight)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: AppTheme.of(Brightness.dark).copyWith(
              textTheme: AppTheme.of(Brightness.dark)
                  .textTheme
                  .apply(fontFamily: 'Marketing'),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(fontFamily: 'Marketing'),
              child: RepaintBoundary(
                key: const Key('shot'),
                child: SizedBox(
                  width: kWidth,
                  height: kHeight,
                  child: Stack(
                    children: [
                      const _Wallpaper(),

                      // The card, centred on the ring it describes. Placed
                      // first so the rail paints over its tail rather than the
                      // other way round.
                      Align(
                        // Close enough that the tail reads as pointing at the
                        // ring rather than floating between the two.
                        alignment: const Alignment(0.78, 0),
                        child: SizedBox(
                          // The card's own width in the app. Wider stretches
                          // the rows and turns a compact readout into a banner.
                          width: 236 * kScale,
                          child: RailCallout(
                            state: claude,
                            onRightEdge: true,
                            onConnect: () {},
                            onRetry: () {},
                          ),
                        ),
                      ),

                      // The rail, flush against the right edge — no gap, the
                      // way it sits against the bezel in use.
                      Align(
                        alignment: Alignment.centerRight,
                        child: RailColumn(
                          states: [claude, codex, opencode],
                          metrics: m,
                          hoveredId: 'claude',
                          onRightEdge: true,
                          onHoverSlot: (_) {},
                          onOpenDetail: (_) {},
                          onAddToSlot: (_) {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Fixed pumps rather than pumpAndSettle: the ring's own value tween and
    // the hover spring never fully quiesce inside a test binding, and waiting
    // for them stalls the run rather than improving the frame.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('shot')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/private/tmp/claude-501/-Users-macmini-Developer-ai-usage-monitor/3bc95a88-852b-40bd-881e-4e77bcf57492/scratchpad/sidenotch_shot.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
