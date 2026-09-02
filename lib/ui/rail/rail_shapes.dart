import 'package:flutter/widgets.dart';

/// The rail's silhouette: a tab that grows out of the screen edge.
///
/// This is what makes it read as part of the display rather than a window
/// parked near it. The edge-facing side is perfectly flat and sits flush
/// against the bezel; the inward side is rounded; and where the two meet, the
/// outline curves *back* into the edge instead of stopping at a corner. Those
/// two reverse curves are the whole trick — a plain rounded rectangle pushed
/// against the edge still looks like a floating box, because the eye reads its
/// corners as belonging to the box rather than to the screen.
class NotchShape extends StatelessWidget {
  const NotchShape({
    super.key,
    required this.child,
    required this.fill,
    required this.onRightEdge,
    this.borderColor,
    this.cornerRadius = 18,
    this.filletRadius = 12,
    this.shadowColor,
    this.fromTop = false,
  });

  final Widget child;
  final Color fill;

  /// Which side is flush against the screen. Ignored when [fromTop].
  final bool onRightEdge;

  /// Draws the rail hanging from the top of the screen instead of a side.
  final bool fromTop;

  final Color? borderColor;

  /// Radius of the two inward-facing corners.
  final double cornerRadius;

  /// Radius of the reverse curves that blend into the screen edge.
  final double filletRadius;

  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NotchPainter(
        fill: fill,
        border: borderColor,
        onRightEdge: onRightEdge,
        cornerRadius: cornerRadius,
        filletRadius: filletRadius,
        shadow: shadowColor,
        fromTop: fromTop,
      ),
      child: child,
    );
  }
}

class _NotchPainter extends CustomPainter {
  const _NotchPainter({
    required this.fill,
    required this.border,
    required this.onRightEdge,
    required this.cornerRadius,
    required this.filletRadius,
    required this.shadow,
    required this.fromTop,
  });

  final Color fill;
  final Color? border;
  final bool onRightEdge;
  final double cornerRadius;
  final double filletRadius;
  final Color? shadow;
  final bool fromTop;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final path = NotchPathBuilder.build(
      size: size,
      onRightEdge: onRightEdge,
      cornerRadius: cornerRadius,
      filletRadius: filletRadius,
      fromTop: fromTop,
    );

    if (shadow != null) {
      canvas.drawShadow(path, shadow!, 14, false);
    }
    canvas.drawPath(path, Paint()..color = fill);

    if (border != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = border!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_NotchPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.border != border ||
      oldDelegate.onRightEdge != onRightEdge ||
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.filletRadius != filletRadius ||
      oldDelegate.shadow != shadow ||
      oldDelegate.fromTop != fromTop;
}

/// Builds the rail's outline.
///
/// Separate from the painter so tests can assert on exactly the shape that
/// gets drawn — the difference between this and a rounded rectangle is the
/// entire design, and it is not something a screenshot review reliably catches.
abstract final class NotchPathBuilder {
  static Path build({
    required Size size,
    required bool onRightEdge,
    required double cornerRadius,
    required double filletRadius,
    bool fromTop = false,
  }) {
    if (fromTop) {
      return _fromTop(
        size: size,
        cornerRadius: cornerRadius,
        filletRadius: filletRadius,
      );
    }

    final w = size.width;
    final h = size.height;

    // The reverse curves eat into the top and bottom, so they cannot be larger
    // than half the height, and the inward corners cannot exceed what is left.
    final f = filletRadius.clamp(0.0, h / 2);
    final r = cornerRadius.clamp(0.0, (h - f * 2) / 2);

    final path = Path();

    if (onRightEdge) {
      path
        ..moveTo(w, 0)
        // Reverse curve: leaves the screen edge and sweeps inward.
        ..quadraticBezierTo(w, f, w - f, f)
        ..lineTo(r, f)
        ..quadraticBezierTo(0, f, 0, f + r)
        ..lineTo(0, h - f - r)
        ..quadraticBezierTo(0, h - f, r, h - f)
        ..lineTo(w - f, h - f)
        // Reverse curve back out to the screen edge.
        ..quadraticBezierTo(w, h - f, w, h)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..quadraticBezierTo(0, f, f, f)
        ..lineTo(w - r, f)
        ..quadraticBezierTo(w, f, w, f + r)
        ..lineTo(w, h - f - r)
        ..quadraticBezierTo(w, h - f, w - r, h - f)
        ..lineTo(f, h - f)
        ..quadraticBezierTo(0, h - f, 0, h)
        ..close();
    }

    return path;
  }

  /// The same silhouette hanging from the top of the screen.
  ///
  /// Not a rotation of the side rail — the fillets have to sweep *outwards*
  /// into the top bezel rather than inwards, or the shape reads as a tab
  /// floating below the edge instead of growing out of it. Flat along the top,
  /// rounded at the two lower corners, with a reverse curve at each upper
  /// corner returning to the screen edge.
  static Path _fromTop({
    required Size size,
    required double cornerRadius,
    required double filletRadius,
  }) {
    final w = size.width;
    final h = size.height;

    // The reverse curves eat into the left and right, so they cannot be larger
    // than half the width, and the lower corners cannot exceed what is left.
    final f = filletRadius.clamp(0.0, w / 2);
    final r = cornerRadius.clamp(0.0, (w - f * 2) / 2);

    return Path()
      ..moveTo(0, 0)
      // Leaves the top edge and sweeps down.
      ..quadraticBezierTo(f, 0, f, f)
      ..lineTo(f, h - r)
      ..quadraticBezierTo(f, h, f + r, h)
      ..lineTo(w - f - r, h)
      ..quadraticBezierTo(w - f, h, w - f, h - r)
      ..lineTo(w - f, f)
      // Reverse curve back up to the top edge.
      ..quadraticBezierTo(w - f, 0, w, 0)
      ..close();
  }
}

/// The hover card, with a tail that points back at the ring it describes.
///
/// The tail is what ties the card to a specific provider. Without it the card
/// is just a panel that appeared nearby, and with three rings stacked together
/// there is nothing to say which one it belongs to.
class CalloutShape extends StatelessWidget {
  const CalloutShape({
    super.key,
    required this.child,
    required this.fill,
    required this.tailOnRight,
    this.borderColor,
    this.shadowColor,
    this.radius = 12,
    this.tailWidth = 9,
    this.tailHeight = 16,
    this.tailOnTop = false,
  });

  final Widget child;
  final Color fill;

  /// Which side the tail leaves from — the side the rail is on.
  final bool tailOnRight;

  /// The tail leaves from the card's top edge instead, pointing back up at a
  /// rail hanging from the top of the screen.
  final bool tailOnTop;

  final Color? borderColor;
  final Color? shadowColor;
  final double radius;

  /// How far the tail protrudes.
  final double tailWidth;

  /// The tail's base, along the card's edge.
  final double tailHeight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CalloutPainter(
        fill: fill,
        border: borderColor,
        shadow: shadowColor,
        tailOnRight: tailOnRight,
        tailOnTop: tailOnTop,
        radius: radius,
        tailWidth: tailWidth,
        tailHeight: tailHeight,
      ),
      child: Padding(
        // Reserve the tail's depth so content never runs underneath it.
        padding: tailOnTop
            ? EdgeInsets.only(top: tailWidth)
            : EdgeInsets.only(
                left: tailOnRight ? 0 : tailWidth,
                right: tailOnRight ? tailWidth : 0,
              ),
        child: child,
      ),
    );
  }
}

class _CalloutPainter extends CustomPainter {
  const _CalloutPainter({
    required this.fill,
    required this.border,
    required this.shadow,
    required this.tailOnRight,
    required this.tailOnTop,
    required this.radius,
    required this.tailWidth,
    required this.tailHeight,
  });

  final Color fill;
  final Color? border;
  final Color? shadow;
  final bool tailOnRight;
  final bool tailOnTop;
  final double radius;
  final double tailWidth;
  final double tailHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= tailWidth || size.width <= 0) return;
    if (!tailOnTop && size.width <= tailWidth) return;

    final bodyRect = tailOnTop
        ? Rect.fromLTWH(0, tailWidth, size.width, size.height - tailWidth)
        : Rect.fromLTWH(
            tailOnRight ? 0 : tailWidth,
            0,
            size.width - tailWidth,
            size.height,
          );

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(bodyRect, Radius.circular(radius)));

    if (tailOnTop) {
      // Points back up at the ring, which the caller has aligned with the
      // card's horizontal centre.
      final midX = size.width / 2;
      final halfBase = (tailHeight / 2).clamp(0.0, size.width / 2);
      path
        ..moveTo(midX - halfBase, bodyRect.top)
        ..lineTo(midX, 0)
        ..lineTo(midX + halfBase, bodyRect.top)
        ..close();
    } else {
      // The tail points at the ring, which the caller has aligned with the
      // card's vertical centre.
      final midY = size.height / 2;
      final halfBase = (tailHeight / 2).clamp(0.0, size.height / 2);
      final tip = tailOnRight ? size.width : 0.0;
      final base = tailOnRight ? bodyRect.right : bodyRect.left;

      path
        ..moveTo(base, midY - halfBase)
        ..lineTo(tip, midY)
        ..lineTo(base, midY + halfBase)
        ..close();
    }

    if (shadow != null) {
      canvas.drawShadow(path, shadow!, 18, false);
    }
    canvas.drawPath(path, Paint()..color = fill);

    if (border != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = border!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_CalloutPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.border != border ||
      oldDelegate.shadow != shadow ||
      oldDelegate.tailOnRight != tailOnRight ||
      oldDelegate.tailOnTop != tailOnTop ||
      oldDelegate.radius != radius ||
      oldDelegate.tailWidth != tailWidth ||
      oldDelegate.tailHeight != tailHeight;
}
