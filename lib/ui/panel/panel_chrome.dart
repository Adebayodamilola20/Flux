import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/hover_icon_button.dart';

/// The window chrome shared by every panel surface.
///
/// The native window is borderless, so the rounded corners, border, shadow, and
/// close affordance are all drawn here. The header doubles as the drag handle —
/// the window is `isMovableByWindowBackground`, so anything that is not an
/// interactive control moves it.
class PanelChrome extends StatelessWidget {
  const PanelChrome({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.onClose,
    this.onBack,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Omitted on first-run onboarding, where there is nothing to go back to and
  /// dismissing without connecting anything would leave a widget with no
  /// content.
  final VoidCallback? onClose;

  final VoidCallback? onBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      // Room for the shadow to fall outside the card without being clipped.
      padding: const EdgeInsets.all(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppMetrics.cardRadius + 2),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: title,
              subtitle: subtitle,
              onClose: onClose,
              onBack: onBack,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
                child: child,
              ),
            ),
            if (footer != null) ...[
              Container(height: 1, color: palette.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: footer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.onBack,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null) ...[
            HoverIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 19,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: palette.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onClose != null)
            HoverIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}
