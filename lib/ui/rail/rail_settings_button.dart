import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/rail_placement.dart';
import '../theme/app_theme.dart';

class RailSettingsButton extends StatefulWidget {
  const RailSettingsButton({
    super.key,
    required this.railExpanded,
    required this.onRightEdge,
    required this.appearance,
    required this.onPressed,
    this.scale = 1,
  });

  final bool railExpanded;
  final bool onRightEdge;

  /// Follows the rail's own scale, from the display it is on.
  ///
  /// Without this the control keeps one fixed size while everything above it
  /// grows or shrinks, which reads as a gear that belongs to a different
  /// widget rather than the foot of this one.
  final double scale;

  /// Solid or frosted, following the rail. The control sits against the rail
  /// and reads as part of it, so a solid black disc beside a frosted rail
  /// looks like a separate widget that happened to land there.
  final RailAppearance appearance;

  final VoidCallback onPressed;

  static const autoFoldDelay = Duration(seconds: 5);

  @visibleForTesting
  static const foldedKey = ValueKey('rail-settings-folded');

  @visibleForTesting
  static const revealedKey = ValueKey('rail-settings-revealed');

  @override
  State<RailSettingsButton> createState() => _RailSettingsButtonState();
}

class _RailSettingsButtonState extends State<RailSettingsButton>
    with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 240),
  );

  late final AnimationController _roll = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 860),
  );

  Timer? _foldTimer;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.railExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showTemporarily();
      });
    }
  }

  @override
  void didUpdateWidget(RailSettingsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.railExpanded && !oldWidget.railExpanded) {
      _showTemporarily();
    } else if (!widget.railExpanded && oldWidget.railExpanded) {
      _foldNow();
    }
  }

  @override
  void dispose() {
    _foldTimer?.cancel();
    _reveal.dispose();
    _roll.dispose();
    super.dispose();
  }

  void _showTemporarily() {
    _show();
    _scheduleFold();
  }

  void _show() {
    _reveal.forward();
    _roll.forward(from: 0);
  }

  void _scheduleFold() {
    _foldTimer?.cancel();
    _foldTimer = Timer(RailSettingsButton.autoFoldDelay, () {
      if (!mounted || _hovered) return;
      _reveal.reverse();
    });
  }

  void _foldNow() {
    _foldTimer?.cancel();
    _hovered = false;
    _reveal.reverse();
  }

  void _handleEnter() {
    if (!widget.railExpanded) return;
    _hovered = true;
    _foldTimer?.cancel();
    _show();
  }

  void _handleExit() {
    _hovered = false;
    _reveal.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isGlass = widget.appearance == RailAppearance.glass;
    // Thinned to the same degree as the rail's own fill, so the two read as
    // one material rather than two greys.
    final fill = isGlass
        ? palette.railFill.withValues(alpha: 0.28)
        : palette.railFill;

    // No tooltip: the control sits against the rail, and a light label
    // appearing beside a dark widget was louder than the thing it described.
    // The gear itself says what it is, and it carries a Semantics label for
    // anyone who cannot see it.
    return MouseRegion(
      cursor: widget.railExpanded
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => _handleEnter(),
      onExit: (_) => _handleExit(),
      child: GestureDetector(
        onTap: widget.railExpanded ? widget.onPressed : null,
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          button: true,
          label: 'Settings',
          child: SizedBox(
            width: 42 * widget.scale,
            height: 42 * widget.scale,
            child: AnimatedBuilder(
              animation: Listenable.merge([_reveal, _roll]),
              builder: (context, _) {
                final reveal = Curves.easeOutCubic.transform(_reveal.value);
                final foldedOpacity = 1 - reveal;
                final turn = _rollingTurn(widget.onRightEdge);
                final scale = _jellyScale();

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      key: RailSettingsButton.foldedKey,
                      opacity: foldedOpacity,
                      child: CustomPaint(
                        size: Size(34 * widget.scale, 34 * widget.scale),
                        painter: _FoldedSettingsPainter(
                          color: fill,
                          shadow: isGlass
                              ? const Color(0x00000000)
                              : palette.railShadow,
                          onRightEdge: widget.onRightEdge,
                        ),
                      ),
                    ),
                    Opacity(
                      key: RailSettingsButton.revealedKey,
                      opacity: reveal,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.diagonal3Values(
                          scale.$1,
                          scale.$2,
                          1,
                        ),
                        child: Container(
                          width: 34 * widget.scale,
                          height: 34 * widget.scale,
                          decoration: BoxDecoration(
                            color: fill,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isGlass
                                  ? palette.textTertiary.withValues(alpha: 0.28)
                                  : palette.railBorder,
                              width: 1 * widget.scale,
                            ),
                            // No drop shadow on glass: the material is meant to
                            // sit in the desktop, and a shadow under it puts it
                            // back on top as a separate object.
                            boxShadow: isGlass
                                ? null
                                : [
                                    BoxShadow(
                                      color: palette.railShadow,
                                      blurRadius: 12,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                          ),
                          child: Center(
                            child: Transform.rotate(
                              angle: turn * math.pi * 2,
                              child: Icon(
                                Icons.settings_outlined,
                                size: 18 * widget.scale,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  double _rollingTurn(bool onRightEdge) {
    final direction = onRightEdge ? -1.0 : 1.0;
    final t = _roll.value;
    if (t < 0.78) {
      return direction * Curves.easeOutCubic.transform(t / 0.78);
    }
    final settle = Curves.elasticOut.transform((t - 0.78) / 0.22);
    return direction * (1 + (1 - settle) * 0.06);
  }

  (double, double) _jellyScale() {
    final t = _roll.value;
    if (t == 0 || t == 1) return (1, 1);
    final wave = math.sin(t * math.pi * 4) * (1 - t);
    return (1 + wave * 0.13, 1 - wave * 0.09);
  }
}

class _FoldedSettingsPainter extends CustomPainter {
  const _FoldedSettingsPainter({
    required this.color,
    required this.shadow,
    required this.onRightEdge,
  });

  final Color color;
  final Color shadow;
  final bool onRightEdge;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (onRightEdge) {
      path
        ..moveTo(size.width * 0.82, size.height * 0.18)
        ..cubicTo(
          size.width * 0.34,
          size.height * 0.18,
          size.width * 0.18,
          size.height * 0.34,
          size.width * 0.18,
          size.height * 0.82,
        );
    } else {
      path
        ..moveTo(size.width * 0.18, size.height * 0.18)
        ..cubicTo(
          size.width * 0.66,
          size.height * 0.18,
          size.width * 0.82,
          size.height * 0.34,
          size.width * 0.82,
          size.height * 0.82,
        );
    }

    canvas.drawPath(
      path.shift(const Offset(0, 2)),
      Paint()
        ..color = shadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_FoldedSettingsPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.shadow != shadow ||
      oldDelegate.onRightEdge != onRightEdge;
}
