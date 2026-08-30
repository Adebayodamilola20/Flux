import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The app's mark: an eight-point sparkle drawn from primitives.
///
/// Deliberately generated rather than shipped as an asset, so no third-party
/// artwork is bundled. The same shape is drawn natively for the status item.
class SparkIcon extends StatelessWidget {
  const SparkIcon({
    super.key,
    required this.color,
    this.size = 13,
    this.points = 8,
  });

  final Color color;
  final double size;

  /// Number of spokes. Eight reads as an asterisk; four as a twinkle.
  final int points;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SparkPainter(color: color, points: points),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({required this.color, required this.points});

  final Color color;
  final int points;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;

    // Each spoke is a tapered wedge: wide at the hub, pointed at the tip. That
    // taper is what makes it read as a sparkle rather than a plus sign.
    final hubRadius = outer * 0.26;
    final path = Path();

    for (var i = 0; i < points; i++) {
      final angle = (2 * math.pi / points) * i - math.pi / 2;
      final spread = math.pi / points * 0.5;

      final tip = center + Offset(math.cos(angle), math.sin(angle)) * outer;
      final left = center +
          Offset(math.cos(angle - spread), math.sin(angle - spread)) *
              hubRadius;
      final right = center +
          Offset(math.cos(angle + spread), math.sin(angle + spread)) *
              hubRadius;

      path
        ..moveTo(left.dx, left.dy)
        ..quadraticBezierTo(
          center.dx + math.cos(angle) * hubRadius * 1.6,
          center.dy + math.sin(angle) * hubRadius * 1.6,
          tip.dx,
          tip.dy,
        )
        ..quadraticBezierTo(
          center.dx + math.cos(angle) * hubRadius * 1.6,
          center.dy + math.sin(angle) * hubRadius * 1.6,
          right.dx,
          right.dy,
        )
        ..close();
    }

    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(center, hubRadius * 0.9, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.points != points;
}
