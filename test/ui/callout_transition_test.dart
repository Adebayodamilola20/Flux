import 'package:ai_usage_monitor/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the structure `_CalloutLayer` builds, so the transition between two
/// rings can be measured without standing up the whole shell.
///
/// The defect this guards: the layer used to wrap its child in an
/// `AnimatedSwitcher` while an `AnimatedPositioned` moved it. The switcher
/// keeps the outgoing card mounted for the length of its transition, and its
/// Stack centres children in a box sized to the tallest — so two cards of
/// different heights were both on screen *and* visibly apart. Moving the
/// pointer down the rail showed a card for a ring it had already left sitting
/// beside the card for the ring it was on.
class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.slotCenterY});

  final double Function(int) slotCenterY;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int slot = 0;

  /// Different heights on purpose: that is what turned an overlap into two
  /// cards with a gap between them.
  static const _heights = {0: 140.0, 2: 80.0};

  void moveTo(int next) => setState(() => slot = next);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedPositioned(
          duration: AppMetrics.calloutMove,
          curve: Curves.easeOutCubic,
          top: widget.slotCenterY(slot),
          right: 40,
          child: FractionalTranslation(
            translation: const Offset(0, -0.5),
            // One card, swapped in place — no switcher holding the old one.
            child: SizedBox(
              key: ValueKey(slot),
              width: 200,
              height: _heights[slot],
              child: ColoredBox(
                color: slot == 0 ? Colors.red : Colors.blue,
                child: Text('card $slot'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void main() {
  double centreOf(int slot) => 60.0 + slot * 66.0;

  testWidgets('only ever one card, however fast the pointer moves',
      (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(Brightness.dark),
        home: Scaffold(body: _Harness(key: key, slotCenterY: centreOf)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('card '), findsOneWidget);

    key.currentState!.moveTo(2);

    // Sampled right through the move, because the defect was only visible
    // mid-flight — at rest there was always exactly one card, which is why it
    // survived review and only showed up in a screenshot.
    for (final elapsed in const [0, 40, 90, 150, 240]) {
      await tester.pump(Duration(milliseconds: elapsed));
      expect(
        find.textContaining('card '),
        findsOneWidget,
        reason: 'more than one card was on screen ${elapsed}ms into the move',
      );
    }

    await tester.pumpAndSettle();
    expect(find.text('card 2'), findsOneWidget);
  });
}
