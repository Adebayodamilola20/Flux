import 'package:ai_usage_monitor/models/rail_placement.dart';
import 'package:ai_usage_monitor/services/native/native_bridge.dart';
import 'package:ai_usage_monitor/ui/rail/rail_shapes.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The top notch is the same shape turned through ninety degrees, and the ways
/// that go wrong are silent: an outline that curves the wrong way still draws,
/// and a card anchored on the wrong axis still appears — just not where the
/// ring is.
void main() {
  group('the edge model', () {
    test('knows which way the rail runs', () {
      expect(RailEdge.top.isHorizontal, isTrue);
      expect(RailEdge.left.isHorizontal, isFalse);
      expect(RailEdge.right.isHorizontal, isFalse);
    });

    test('only a side rail has a flat right', () {
      expect(RailEdge.right.isRightEdge, isTrue);
      // Asked by everything that draws a side; the top has no answer, and
      // false keeps those callers on their existing default.
      expect(RailEdge.top.isRightEdge, isFalse);
    });

    test('is offered in settings without anything listing it by hand', () {
      // The dropdown builds from `values`, so a new edge appears there by
      // existing rather than by being remembered.
      expect(RailEdge.values, contains(RailEdge.top));
      expect(RailEdge.top.label, 'Top centre');
    });
  });

  group('the outline', () {
    const size = Size(240, 60);

    Path build({required bool fromTop}) => NotchPathBuilder.build(
          size: size,
          onRightEdge: true,
          cornerRadius: 28,
          filletRadius: 21,
          fromTop: fromTop,
        );

    test('sits flat on the bezel between its two reverse curves', () {
      final path = build(fromTop: true);

      // The middle of the top edge is on the screen edge, which is what makes
      // the notch grow out of the display rather than float below it.
      expect(path.contains(Offset(size.width / 2, 1)), isTrue);

      // The extreme corners are carved away — that reverse curve is the whole
      // trick, and a shape that filled them would be a rectangle taped to the
      // bezel.
      expect(path.contains(const Offset(1, 1)), isFalse);
      expect(path.contains(Offset(size.width - 1, 1)), isFalse);
    });

    test('is rounded along its lower corners', () {
      final path = build(fromTop: true);

      expect(path.contains(const Offset(2, 58)), isFalse);
      expect(path.contains(Offset(size.width - 2, 58)), isFalse);
      // But the lower edge between them is solid.
      expect(path.contains(Offset(size.width / 2, 58)), isTrue);
    });

    test('is not the side outline wearing a different flag', () {
      // The discriminator is which edge is flat. A side rail's flat side is
      // the right, so the middle of its *top* is outside the shape; the top
      // rail's is inside. If the two ever agree here, one of them is drawing
      // the wrong silhouette.
      final middleOfTop = Offset(size.width / 2, 1);

      expect(build(fromTop: true).contains(middleOfTop), isTrue);
      expect(build(fromTop: false).contains(middleOfTop), isFalse);
    });
  });

  group('where the card is anchored', () {
    const metrics = RailMetrics.fallback;

    test('a top rail measures along the other axis', () {
      // Each slot's centre steps along the row, and the first is not at the
      // window's edge — the rail is centred in a window wider than itself.
      final first = metrics.slotCenterX(0);
      final second = metrics.slotCenterX(1);

      expect(second - first, metrics.slotHeight);
      expect(first, greaterThan(0));
    });

    test('and the two axes do not share a helper by accident', () {
      // The window is not square, so these must not agree — if they do, one
      // of them is measuring the wrong dimension.
      expect(metrics.slotCenterX(0), isNot(metrics.slotCenterY(0)));
    });
  });
}
