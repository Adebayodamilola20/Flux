import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Each provider's own mark, drawn as vector paths.
///
/// Drawn rather than bundled as image assets for two reasons: a path stays
/// crisp at any size on any Retina factor without shipping several rasters
/// each, and it can be tinted to suit light or dark mode. The shapes follow
/// each company's published mark so the card is recognisably theirs.
///
/// These are trademarks of their respective owners, used here only to identify
/// the service a card connects to.
abstract final class ProviderLogos {
  /// Returns the mark for a provider, or null when there is no drawn logo.
  static CustomPainter? painterFor(String providerId, Color color) {
    return switch (providerId) {
      'claude' => _AnthropicBurst(color),
      'chatgpt' => _OpenAiKnot(color),
      'gemini' => _GeminiSpark(color),
      'antigravity' => _AntigravityMark(color),
      _ => null,
    };
  }
}

/// Anthropic's burst: radiating tapered spokes around a small hub.
class _AnthropicBurst extends CustomPainter {
  const _AnthropicBurst(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    if (outer <= 0) return;

    // Anthropic's mark reads as a starburst: spokes that are wide where they
    // meet the centre and taper to a point.
    const spokes = 8;
    final hub = outer * 0.18;
    final path = Path();

    for (var i = 0; i < spokes; i++) {
      final angle = (2 * math.pi / spokes) * i - math.pi / 2;
      final spread = math.pi / spokes * 0.42;

      final tip = center + Offset(math.cos(angle), math.sin(angle)) * outer;
      final left = center +
          Offset(math.cos(angle - spread), math.sin(angle - spread)) * hub;
      final right = center +
          Offset(math.cos(angle + spread), math.sin(angle + spread)) * hub;

      path
        ..moveTo(left.dx, left.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
    }

    canvas
      ..drawPath(path, Paint()..color = color)
      ..drawCircle(center, hub * 1.05, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AnthropicBurst old) => old.color != color;
}

/// OpenAI's knot: six lobes rotated around a centre, drawn as a stroked
/// hexafoil rather than the exact interlace, which is unreadable at 16pt.
class _OpenAiKnot extends CustomPainter {
  const _OpenAiKnot(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    if (radius <= 0) return;

    final stroke = radius * 0.24;
    final lobe = radius * 0.56;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Six overlapping arcs on a ring produce the interlocking-petal silhouette
    // the mark is known for, and survives being drawn 16 points wide.
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (2 * math.pi / 6) * i - math.pi / 2;
      final at = center + Offset(math.cos(angle), math.sin(angle)) * (radius - lobe);
      path.addArc(
        Rect.fromCircle(center: at, radius: lobe),
        angle - math.pi * 0.62,
        math.pi * 1.24,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_OpenAiKnot old) => old.color != color;
}

/// Gemini's spark: a four-pointed star with concave sides.
class _GeminiSpark extends CustomPainter {
  const _GeminiSpark(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    if (r <= 0) return;

    // The defining feature is the *concave* waist between points: straight
    // edges would read as a plain diamond.
    final waist = r * 0.14;
    final path = Path()..moveTo(center.dx, center.dy - r);

    for (var i = 0; i < 4; i++) {
      final from = (math.pi / 2) * i - math.pi / 2;
      final to = from + math.pi / 2;
      final tip = center + Offset(math.cos(to), math.sin(to)) * r;
      final mid = from + math.pi / 4;
      final control = center + Offset(math.cos(mid), math.sin(mid)) * waist;

      path.quadraticBezierTo(control.dx, control.dy, tip.dx, tip.dy);
    }

    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GeminiSpark old) => old.color != color;
}

/// Antigravity's mark: an upward chevron over a base, drawn as an outline.
class _AntigravityMark extends CustomPainter {
  const _AntigravityMark(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // A rising chevron: the "anti-gravity" idea, and distinct at a glance from
    // the other three marks in the stack.
    canvas
      ..drawPath(
        Path()
          ..moveTo(w * 0.16, h * 0.56)
          ..lineTo(w * 0.5, h * 0.16)
          ..lineTo(w * 0.84, h * 0.56),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(w * 0.16, h * 0.86)
          ..lineTo(w * 0.5, h * 0.46)
          ..lineTo(w * 0.84, h * 0.86),
        paint,
      );
  }

  @override
  bool shouldRepaint(_AntigravityMark old) => old.color != color;
}
