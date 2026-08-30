import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// A percentage that counts to its new value instead of snapping.
class AnimatedPercent extends StatelessWidget {
  const AnimatedPercent({
    super.key,
    required this.percent,
    required this.style,
    this.suffix = '% Used',
    this.unknownLabel = '—',
  });

  /// Whole percent in `0 – 100`, or null when unknown.
  final int? percent;
  final TextStyle style;
  final String suffix;

  /// Shown in place of a number when [percent] is null, so the UI never
  /// invents a figure it does not have.
  final String unknownLabel;

  @override
  Widget build(BuildContext context) {
    final value = percent;
    if (value == null) {
      return Text(unknownLabel, style: style);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value.toDouble(), end: value.toDouble()),
      duration: AppMetrics.progressAnimation,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) =>
          Text('${animated.round()}$suffix', style: style),
    );
  }
}
