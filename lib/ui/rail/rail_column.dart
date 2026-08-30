import 'package:flutter/widgets.dart';

import '../../models/connection_status.dart';
import '../../services/native/native_bridge.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/provider_glyph.dart';
import '../widgets/usage_ring.dart';
import 'rail_shapes.dart';

/// The rail itself: a stack of provider rings inside a tab that grows out of
/// the screen edge.
///
/// Only shown while the pointer is on the rail. At rest the widget is a
/// [RailNub] instead.
class RailColumn extends StatelessWidget {
  const RailColumn({
    super.key,
    required this.states,
    required this.metrics,
    required this.hoveredId,
    required this.onHoverSlot,
    required this.onOpenDetail,
    required this.onRightEdge,
  });

  final List<ProviderState> states;
  final RailMetrics metrics;

  /// The slot the pointer is on, if any.
  final String? hoveredId;

  final ValueChanged<String?> onHoverSlot;
  final ValueChanged<String> onOpenDetail;
  final bool onRightEdge;

  @override
  Widget build(BuildContext context) {
    return NotchShape(
      // The rail is a hardware-like edge notch, not a themed panel.
      fill: const Color(0xFF000000),
      borderColor: const Color(0xFF000000),
      shadowColor: const Color(0x99000000),
      onRightEdge: onRightEdge,
      child: SizedBox(
        width: metrics.collapsedWidth,
        height: metrics.collapsedHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: metrics.collapsedVerticalPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final state in states)
                _RailSlot(
                  state: state,
                  height: metrics.slotHeight,
                  isHovered: state.id == hoveredId,
                  onEnter: () => onHoverSlot(state.id),
                  onTap: () => onOpenDetail(state.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One provider: a ring, its percentage, and an activity dot.
class _RailSlot extends StatelessWidget {
  const _RailSlot({
    required this.state,
    required this.height,
    required this.isHovered,
    required this.onEnter,
    required this.onTap,
  });

  final ProviderState state;
  final double height;
  final bool isHovered;
  final VoidCallback onEnter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final window = state.data?.primaryWindow;
    final fraction = window?.fractionUsed;
    final isReserved = state.status == ConnectionStatus.unsupported;
    final isLive = state.isLive;
    final isUnconnected = !state.connection.isConnected;

    // A slot with no usable figure keeps the provider's own accent rather than
    // borrowing the quota colour scale, so a grey ring never reads as "safe".
    final ringColor = isLive
        ? palette.accentFor(fraction)
        : Color(state.descriptor.accent).withValues(alpha: 0.5);

    return MouseRegion(
      onEnter: (_) => onEnter(),
      cursor: isReserved ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isReserved ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  AnimatedScale(
                    // A small lift on hover confirms which ring the card
                    // belongs to, alongside the tail pointing at it.
                    scale: isHovered ? 1.08 : 1,
                    duration: AppMetrics.fadeAnimation,
                    curve: Curves.easeOut,
                    child: UsageRing(
                      fraction: fraction,
                      color: ringColor,
                      dimmed: !isLive,
                      child: isUnconnected
                          ? Text(
                              '+',
                              style: TextStyle(
                                fontSize: 17,
                                height: 1,
                                fontWeight: FontWeight.w400,
                                color: palette.textTertiary,
                              ),
                            )
                          : ProviderGlyph(
                              providerId: state.id,
                              color: isLive
                                  ? palette.textPrimary
                                  : palette.textTertiary,
                              size: 13,
                            ),
                    ),
                  ),
                  if (state.activity == ActivityStatus.working)
                    Positioned(
                      right: 0,
                      top: 1,
                      child: _ActivityDot(color: palette.accentPositive),
                    ),
                ],
              ),
              if (_label(state) case final label?) ...[
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Only actual measured percentages earn a text label. Empty slots are
  /// represented by their plus sign alone, without a dash or error marker.
  static String? _label(ProviderState state) {
    final percent = state.percent;
    return percent == null ? null : '$percent%';
  }
}

/// The resting state: a sliver flush against the screen edge.
///
/// It is a pure-black hint that the rail is available. Keeping it neutral
/// avoids drawing attention away from the work behind it.
class RailNub extends StatelessWidget {
  const RailNub({super.key, required this.onRightEdge});

  final bool onRightEdge;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(AppMetrics.nubRadius);

    return Container(
      width: AppMetrics.nubWidth,
      height: AppMetrics.nubHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        // Rounded on the inward side only; the edge side is flat against the
        // bezel, the same rule the full rail follows.
        borderRadius: BorderRadius.horizontal(
          left: onRightEdge ? radius : Radius.zero,
          right: onRightEdge ? Radius.zero : radius,
        ),
      ),
    );
  }
}

/// A small filled dot marking a provider that is doing something right now.
class _ActivityDot extends StatefulWidget {
  const _ActivityDot({required this.color});

  final Color color;

  @override
  State<_ActivityDot> createState() => _ActivityDotState();
}

class _ActivityDotState extends State<_ActivityDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      // A slow breath rather than a blink: it should register in peripheral
      // vision without demanding attention.
      opacity: Tween<double>(
        begin: 0.45,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: 5.5,
        height: 5.5,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
