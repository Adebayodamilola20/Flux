import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// A circular quota gauge: a track, an arc for the fraction used, and whatever
/// glyph identifies the provider at its centre.
///
/// The arc animates between values so a refresh reads as a change rather than
/// a redraw. An unknown fraction draws the track alone — never a full or empty
/// ring, either of which would be a claim the app cannot support.
class UsageRing extends StatefulWidget {
  const UsageRing({
    super.key,
    required this.fraction,
    required this.color,
    required this.child,
    this.diameter = AppMetrics.ringDiameter,
    this.stroke = AppMetrics.ringStroke,
    this.trackColor,
    this.dimmed = false,
    this.isReaching = false,
  });

  /// The figure could not be reached and another attempt is coming.
  ///
  /// Draws a short arc sweeping inside the ring, over whatever the last known
  /// fraction was. A stale number with nothing to mark it is indistinguishable
  /// from a current one — which is how the rail sat on an old percentage while
  /// the provider's own app showed a different figure, with nothing on screen
  /// to say which to believe.
  final bool isReaching;

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
  State<UsageRing> createState() => _UsageRingState();
}

class _UsageRingState extends State<UsageRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _syncSweep();
  }

  @override
  void didUpdateWidget(UsageRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isReaching != widget.isReaching) _syncSweep();
  }

  /// Runs the sweep only while it is on screen. A repeating controller left
  /// spinning under a ring nobody is looking at is a frame every 16ms for
  /// nothing.
  void _syncSweep() {
    if (widget.isReaching) {
      _sweep.repeat();
    } else {
      _sweep.stop();
      _sweep.value = 0;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox.square(
      dimension: widget.diameter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (widget.fraction ?? 0).clamp(0.0, 1.0)),
        duration: AppMetrics.progressAnimation,
        curve: Curves.easeOutCubic,
        builder: (context, value, glyph) {
          return AnimatedBuilder(
            animation: _sweep,
            builder: (context, _) {
              return CustomPaint(
                painter: _RingPainter(
                  fraction: widget.fraction == null ? null : value,
                  color: widget.color,
                  track: widget.trackColor ?? palette.track,
                  stroke: widget.stroke,
                  sweep: widget.isReaching ? _sweep.value : null,
                  sweepColor: palette.textSecondary,
                ),
                child: Center(
                  child: Opacity(
                    opacity: widget.dimmed ? 0.45 : 1,
                    child: glyph,
                  ),
                ),
              );
            },
          );
        },
        child: widget.child,
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
    required this.sweep,
    required this.sweepColor,
  });

  final double? fraction;
  final Color color;
  final Color track;
  final double stroke;

  /// Position of the reaching arc in `0.0 – 1.0`, or null when not reaching.
  final double? sweep;
  final Color sweepColor;

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
    if (value != null && value > 0) {
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

    final position = sweep;
    if (position == null) return;

    // A short arc travelling just inside the gauge, so it never competes with
    // the fraction for the same line. Inside rather than over it: the last
    // known percentage stays readable while the app is trying to better it.
    final inner = radius - stroke * 1.6;
    if (inner <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: inner),
      -math.pi / 2 + 2 * math.pi * position,
      math.pi * 0.55,
      false,
      Paint()
        ..color = sweepColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.track != track ||
      oldDelegate.stroke != stroke ||
      oldDelegate.sweep != sweep ||
      oldDelegate.sweepColor != sweepColor;
}
