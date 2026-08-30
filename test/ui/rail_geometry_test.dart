import 'package:ai_usage_monitor/services/native/native_bridge.dart';
import 'package:ai_usage_monitor/ui/rail/rail_shapes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RailMetrics slot positions', () {
    const metrics = RailMetrics.fallback;

    test('centres the ring stack in the window', () {
      final first = metrics.slotCenterY(0);
      final last = metrics.slotCenterY(metrics.slots - 1);

      // The stack's midpoint is the window's midpoint, which is what lets the
      // rail line up with the middle of the screen edge.
      expect((first + last) / 2, closeTo(metrics.windowHeight / 2, 0.01));
    });

    test('spaces rings by exactly one slot', () {
      for (var i = 1; i < metrics.slots; i++) {
        expect(
          metrics.slotCenterY(i) - metrics.slotCenterY(i - 1),
          closeTo(metrics.slotHeight, 0.01),
        );
      }
    });

    test('keeps every ring inside the window', () {
      for (var i = 0; i < metrics.slots; i++) {
        final y = metrics.slotCenterY(i);
        expect(y, greaterThan(0));
        expect(y, lessThan(metrics.windowHeight));
      }
    });

    test('derives the open height from the slot count', () {
      expect(
        metrics.collapsedHeight,
        metrics.slots * metrics.slotHeight +
            metrics.collapsedVerticalPadding * 2,
      );
    });

    test('leaves room for the card beside the rail', () {
      // The card and the rail have to fit side by side in the expanded width,
      // or the card would be drawn underneath the rings.
      expect(
        metrics.expandedWidth - metrics.collapsedWidth,
        greaterThan(180),
      );
    });
  });

  group('NotchShape outline', () {
    const size = Size(52, 264);

    Path pathFor({bool onRightEdge = true}) => NotchPathBuilder.build(
          size: size,
          onRightEdge: onRightEdge,
          cornerRadius: 18,
          filletRadius: 12,
        );

    test('stays flush against the screen edge for its whole height', () {
      final path = pathFor();
      // Any gap here and the rail stops looking like part of the display.
      // The strip narrows as the reverse curves pull in at the ends, so the
      // sample points near the top and bottom sit closer to the edge.
      expect(path.contains(const Offset(51.5, 132)), isTrue);
      expect(path.contains(const Offset(51.9, 4)), isTrue);
      expect(path.contains(const Offset(51.9, 260)), isTrue);
    });

    test('is carved away at the top and bottom, away from the edge', () {
      final path = pathFor();
      // This is the whole difference from a rounded rectangle pushed against
      // the edge: near the top, only the strip beside the bezel is filled, so
      // the outline appears to grow out of the screen rather than sit on it.
      expect(path.contains(const Offset(26, 2)), isFalse);
      expect(path.contains(const Offset(26, 262)), isFalse);
    });

    test('fills the body of the tab', () {
      final path = pathFor();
      expect(path.contains(const Offset(26, 132)), isTrue);
      expect(path.contains(const Offset(26, 30)), isTrue);
      expect(path.contains(const Offset(26, 234)), isTrue);
    });

    test('rounds the inward-facing corners', () {
      final path = pathFor();
      // The corner diagonally inside the tab is cut away by the radius.
      expect(path.contains(const Offset(1, 13)), isFalse);
      expect(path.contains(const Offset(20, 13)), isTrue);
    });

    test('mirrors for the left edge', () {
      final path = pathFor(onRightEdge: false);
      expect(path.contains(const Offset(0.5, 132)), isTrue);
      expect(path.contains(const Offset(0.1, 4)), isTrue);
      expect(path.contains(const Offset(26, 2)), isFalse);
      expect(path.contains(const Offset(26, 132)), isTrue);
    });

    test('survives a height too small for its own curves', () {
      // Clamping rather than producing an inverted, self-intersecting path.
      final tiny = NotchPathBuilder.build(
        size: const Size(52, 10),
        onRightEdge: true,
        cornerRadius: 18,
        filletRadius: 12,
      );
      expect(tiny.getBounds().height, lessThanOrEqualTo(10));
      expect(tiny.getBounds().isEmpty, isFalse);
    });
  });
}
