import 'package:ai_usage_monitor/services/native/native_bridge.dart';
import 'package:ai_usage_monitor/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rail is sized from the display it is on, so what Flutter draws inside it
/// has to come from the same number the window was built with. A ring left at a
/// fixed size inside a window that scaled is worse than either size alone.
void main() {
  RailMetrics at(double scale) => RailMetrics(
        collapsedWidth: 46 * scale,
        expandedWidth: 280 * scale,
        slotHeight: 66 * scale,
        collapsedVerticalPadding: 28 * scale,
        shadowPadding: 26 * scale,
        settingsButtonSize: 34 * scale,
        settingsButtonGap: -4 * scale,
        edgeInset: 0,
        windowWidth: 332 * scale,
        windowHeight: 344 * scale,
        slots: 3,
        scale: scale,
      );

  test('everything drawn inside the rail follows its scale', () {
    final laptop = at(0.88);
    final desktop = at(1.3);

    expect(laptop.ringDiameter, lessThan(desktop.ringDiameter));
    expect(laptop.nubHeight, lessThan(desktop.nubHeight));
    expect(laptop.slotLabelSize, lessThan(desktop.slotLabelSize));
  });

  test('the base scale is the size the design was drawn at', () {
    final base = at(1);

    expect(base.ringDiameter, 32);
    expect(base.nubWidth, 11);
    expect(base.nubHeight, 84);
    expect(base.slotLabelSize, 12);
  });

  test('the gauge never thins to a hairline on a small display', () {
    // Shrinking the stroke with everything else eventually stops it reading as
    // a ring at all, so it has a floor the rest of the geometry does not.
    expect(at(0.5).ringStroke, greaterThanOrEqualTo(2.0));
    expect(at(1).ringStroke, closeTo(2.8, 0.001));
  });

  test('a payload without a scale falls back rather than collapsing', () {
    // Older native builds, and the path taken under `flutter test` where there
    // is no native side at all. A missing scale must not become zero.
    final parsed = RailMetrics.fromMap(const {
      'collapsedWidth': 46.0,
      'expandedWidth': 280.0,
      'slotHeight': 66.0,
      'collapsedVerticalPadding': 28.0,
      'shadowPadding': 26.0,
      'edgeInset': 0.0,
      'windowWidth': 332.0,
      'windowHeight': 344.0,
      'slots': 3,
    });

    expect(parsed, isNotNull);
    expect(parsed!.scale, 1);
    expect(parsed.ringDiameter, 32);
  });

  test('a scale sent by the native side is used', () {
    final parsed = RailMetrics.fromMap(const {
      'collapsedWidth': 60.0,
      'expandedWidth': 364.0,
      'slotHeight': 86.0,
      'collapsedVerticalPadding': 36.0,
      'shadowPadding': 34.0,
      'edgeInset': 0.0,
      'windowWidth': 432.0,
      'windowHeight': 447.0,
      'slots': 3,
      'scale': 1.3,
    });

    expect(parsed!.scale, 1.3);
    expect(parsed.ringDiameter, closeTo(41.6, 0.001));
  });

  test('the card sits the same distance off a side rail as it always did', () {
    // The inset moved into RailMetrics so a top rail could measure off its own
    // thickness. The side rail's spacing must not have changed on the way —
    // and the gap is duplicated across a UI/service boundary, so it is checked
    // rather than trusted.
    const m = RailMetrics.fallback;

    expect(
      m.calloutInset(false),
      m.shadowPadding + m.collapsedWidth + AppMetrics.calloutGap,
    );
    // A top rail is deeper, so its card sits further out.
    expect(m.calloutInset(true), greaterThan(m.calloutInset(false)));
  });
}
