import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'provider_logos.dart';

/// The mark that identifies a provider inside its usage ring.
///
/// Every glyph is drawn from primitives rather than bundled as artwork: this
/// app ships no third-party logos, and a shape it draws itself scales cleanly
/// to any Retina factor without a set of raster assets.
class ProviderGlyph extends StatelessWidget {
  const ProviderGlyph({
    super.key,
    required this.providerId,
    required this.color,
    this.size = 14,
    this.isEmpty = false,
  });

  final String providerId;
  final Color color;
  final double size;

  /// Draws a plus instead of the provider's mark.
  ///
  /// An empty slot has nothing to identify yet, and a silhouette in a ring
  /// reads as "a tool that is at 0%" rather than "a tool you have not added".
  /// A plus is the one glyph that says the slot is an invitation.
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PlusGlyphPainter(color: color)),
      );
    }

    // Each provider's own mark in its brand colour, so the rail does not turn
    // every app into the surrounding text colour.
    final markColor = ProviderLogos.brandColorFor(providerId) ?? color;
    final logo = ProviderLogos.painterFor(providerId, markColor);
    if (logo != null) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: logo),
      );
    }

    // A provider with no drawn mark yet still needs something distinct.
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _PolygonGlyphPainter(
          color: markColor,
          sides: _sidesFor(providerId),
        ),
      ),
    );
  }

  /// A distinct silhouette per slot, so the three rings stay tellable apart at
  /// a glance even before their colours register.
  static int _sidesFor(String providerId) => switch (providerId) {
    'codex' => 6,
    'antigravity' => 4,
    _ => 5,
  };
}

/// A plus, for a slot with nothing in it yet.
class _PlusGlyphPainter extends CustomPainter {
  const _PlusGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final arm = size.shortestSide / 2;
    if (arm <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas
      ..drawLine(
        Offset(center.dx - arm, center.dy),
        Offset(center.dx + arm, center.dy),
        paint,
      )
      ..drawLine(
        Offset(center.dx, center.dy - arm),
        Offset(center.dx, center.dy + arm),
        paint,
      );
  }

  @override
  bool shouldRepaint(_PlusGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _PolygonGlyphPainter extends CustomPainter {
  const _PolygonGlyphPainter({required this.color, required this.sides});

  final Color color;
  final int sides;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    if (radius <= 0) return;

    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = (2 * math.pi / sides) * i - math.pi / 2;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PolygonGlyphPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.sides != sides;
}
