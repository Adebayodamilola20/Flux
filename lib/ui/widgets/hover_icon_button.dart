import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A compact, keyboard-reachable icon button sized for the popover's header.
class HoverIconButton extends StatefulWidget {
  const HoverIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.spinning = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  /// Rotates the icon continuously — used for the refresh affordance while a
  /// fetch is in flight.
  final bool spinning;

  @override
  State<HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<HoverIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _spin.repeat();
  }

  @override
  void didUpdateWidget(HoverIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.spinning && _spin.isAnimating) {
      // Finish the current revolution so the icon settles upright.
      _spin.animateTo(1, duration: const Duration(milliseconds: 300)).then((_) {
        if (mounted) _spin.value = 0;
      });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.onPressed != null;

    Widget icon = Icon(
      widget.icon,
      size: 13,
      color: enabled
          ? (_hovered ? palette.textPrimary : palette.textSecondary)
          : palette.textTertiary,
    );

    if (widget.spinning || _spin.isAnimating) {
      icon = RotationTransition(turns: _spin, child: icon);
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Focus(
        canRequestFocus: enabled,
        child: MouseRegion(
          cursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: AppMetrics.fadeAnimation,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _hovered && enabled
                    ? palette.surfaceRaised
                    : const Color(0x00000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }
}
