import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// A small text button used for Retry / Open Settings actions.
class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.emphasised = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Filled rather than outlined — used for the primary action in a row.
  final bool emphasised;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.onPressed != null;

    final background = widget.emphasised
        ? (_hovered ? palette.textPrimary : palette.textPrimary.withValues(alpha: 0.9))
        : (_hovered ? palette.surfaceRaised : const Color(0x00000000));

    final foreground = widget.emphasised
        ? palette.surface
        : (enabled ? palette.textSecondary : palette.textTertiary);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMetrics.fadeAnimation,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(7),
            border: widget.emphasised
                ? null
                : Border.all(color: palette.border, width: 1),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w500,
              color: foreground,
              letterSpacing: -0.05,
            ),
          ),
        ),
      ),
    );
  }
}
