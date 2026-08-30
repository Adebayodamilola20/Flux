import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../providers/provider_catalog.dart';
import 'spark_icon.dart';

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
  });

  final String providerId;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (providerId == ProviderCatalog.claude.id) {
      return SparkIcon(color: color, size: size);
    }

    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _PolygonGlyphPainter(
          color: color,
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
