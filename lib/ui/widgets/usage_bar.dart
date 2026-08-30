import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// A thin quota bar that animates between values.
///
/// When usage ticks from 52% to 53% the fill glides rather than jumping, which
/// is the difference between a utility that feels alive and one that feels
/// like it is redrawing.
class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 4,
    this.indeterminate = false,
  });

  /// Fill amount in `0.0 – 1.0`, or null when the value is unknown.
  final double? fraction;
  final Color color;
  final double height;

  /// Renders a muted, empty track — used while the first fetch is in flight.
  final bool indeterminate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(height);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: palette.track, borderRadius: radius),
        child: indeterminate || fraction == null
            ? null
            : TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction!.clamp(0.0, 1.0)),
                duration: AppMetrics.progressAnimation,
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: color),
                      duration: AppMetrics.progressAnimation,
                      builder: (context, animatedColor, _) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: animatedColor ?? color,
                          borderRadius: radius,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
