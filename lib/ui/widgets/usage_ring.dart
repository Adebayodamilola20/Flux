import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// A circular quota gauge: a track, an arc for the fraction used, and whatever
/// glyph identifies the provider at its centre.
///
/// The arc animates between values so a refresh reads as a change rather than
/// a redraw. An unknown fraction draws the track alone — never a full or empty
/// ring, either of which would be a claim the app cannot support.
class UsageRing extends StatelessWidget {
  const UsageRing({
    super.key,
    required this.fraction,
    required this.color,
    required this.child,
    this.diameter = AppMetrics.ringDiameter,
    this.stroke = AppMetrics.ringStroke,
    this.trackColor,
    this.dimmed = false,
  });

  /// Fill amount in `0.0 – 1.0`, or null when unknown.
  final double? fraction;

  final Color color;

  /// Drawn at the centre — a provider glyph.
  final Widget child;

  final double diameter;
  final double stroke;
  final Color? trackColor;

  /// Renders the glyph muted, for a slot that is not connected.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox.square(
      dimension: diameter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (fraction ?? 0).clamp(0.0, 1.0)),
        duration: AppMetrics.progressAnimation,
        curve: Curves.easeOutCubic,
        builder: (context, value, glyph) {
          return CustomPaint(
            painter: _RingPainter(
              fraction: fraction == null ? null : value,
              color: color,
              track: trackColor ?? palette.track,
              stroke: stroke,
            ),
            child: Center(
              child: Opacity(opacity: dimmed ? 0.45 : 1, child: glyph),
            ),
          );
        },
        child: child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double? fraction;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - stroke) / 2;
    if (radius <= 0) return;

    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    final value = fraction;
    if (value == null || value <= 0) return;

    canvas.drawArc(
      rect,
      // Start at twelve o'clock and fill clockwise, the way a gauge is read.
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.track != track ||
      oldDelegate.stroke != stroke;
}
