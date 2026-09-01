import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/connection_status.dart';
import '../../models/rail_placement.dart';
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
    required this.onAddToSlot,
    required this.onRightEdge,
    this.appearance = RailAppearance.solid,
  });

  /// What each rail position holds. A null entry is an empty slot, drawn as a
  /// plus for the user to fill.
  final List<ProviderState?> states;
  final RailMetrics metrics;

  /// The slot the pointer is on, if any.
  final String? hoveredId;

  final ValueChanged<String?> onHoverSlot;
  final ValueChanged<String> onOpenDetail;

  /// Asks to fill the empty slot at this index.
  final ValueChanged<int> onAddToSlot;
  final bool onRightEdge;

  /// Solid or frosted. Glass thins the fill so the material behind it — drawn
  /// natively, because only AppKit can blur the desktop — actually shows.
  final RailAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isGlass = appearance == RailAppearance.glass;

    return NotchShape(
      // Denser than a floating panel — the rail sits flush against the bezel
      // and reads as part of the display — but still themed. A black bar on a
      // light desktop reads as a bug.
      // Glass keeps a thin wash of the theme colour over the frost. Fully
      // transparent would leave the rings floating on a blur with nothing to
      // separate them from a busy desktop.
      //
      // The wash is deliberately light. At the weight this used to carry, the
      // frost underneath barely showed and the result read as a dark panel
      // rather than as glass — the whole point of the setting is that you can
      // see the desktop moving behind it.
      fill: isGlass
          ? palette.railFill.withValues(alpha: 0.14)
          : palette.railFill,
      // A bright hairline rather than a grey one. Catching the light along its
      // edge is what separates a pane of glass from a translucent rectangle.
      borderColor: isGlass
          ? const Color(0xFFFFFFFF).withValues(alpha: 0.30)
          : palette.railBorder,
      // No drop shadow under glass: a shadow says the panel is floating above
      // the desktop, which contradicts a material that is meant to be lit by
      // what is behind it.
      shadowColor: isGlass ? null : palette.railShadow,
      onRightEdge: onRightEdge,
      cornerRadius: 20,
      filletRadius: 13,
      child: SizedBox(
        width: metrics.collapsedWidth,
        // Sized from what is actually rendered, not from the slot count the
        // metrics were built with. The two can drift — a provider added to the
        // catalog without the native side agreeing — and the symptom is a
        // clipped ring rather than anything that names the cause.
        height:
            metrics.collapsedVerticalPadding * 2 +
            states.length * metrics.slotHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: metrics.collapsedVerticalPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < states.length; index++)
                if (states[index] case final state?)
                  _RailSlot(
                    state: state,
                    height: metrics.slotHeight,
                    isHovered: state.id == hoveredId,
                    onEnter: () => onHoverSlot(state.id),
                    onTap: () => onOpenDetail(state.id),
                  )
                else
                  _EmptySlot(
                    height: metrics.slotHeight,
                    // Clears the card on the way in. An empty position has no
                    // provider to describe, and without this the previous
                    // ring's card stays up — so a plus appeared to be claimed
                    // by whichever provider the pointer passed over last.
                    onEnter: () => onHoverSlot(null),
                    onTap: () => onAddToSlot(index),
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

    // One source of truth for the whole slot. Deriving the glyph from the
    // connection and the label from the data let them disagree — a ring could
    // draw the "empty slot" plus *and* a percentage next to it, which says two
    // contradictory things at once. A slot is empty only when it has nothing
    // to show at all.
    final isEmpty = !isLive && !state.connection.isConnected;

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
                      // Drawn rather than typeset: a "+" from the system font
                      // sits off-centre in a ring and changes weight with the
                      // user's text settings.
                      child: ProviderGlyph(
                        providerId: state.id,
                        isEmpty: isEmpty,
                        color: isEmpty
                            ? palette.textTertiary
                            : palette.textPrimary,
                        size: isEmpty ? 11 : 15,
                        useBrandColor: false,
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
              if (isEmpty ? null : _label(state) case final label?) ...[
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
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

  /// Only actual measured percentages earn a text label.
  ///
  /// An empty slot is its plus sign alone — no dash, no error marker, and
  /// never a percentage, which would contradict the plus above it.
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
  const RailNub({
    super.key,
    required this.onRightEdge,
    this.appearance = RailAppearance.solid,
  });

  final bool onRightEdge;

  /// Follows the rail's own setting.
  ///
  /// It has to: the frost the native side draws is sized to the *open* rail
  /// and is not on screen while the rail rests, so a solid fill here was a
  /// black bar sitting against the bezel in a mode the user had explicitly set
  /// to glass. The sliver is the only thing visible most of the time, so it is
  /// the one that most has to look right.
  final RailAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = Radius.circular(AppMetrics.nubRadius);
    final isGlass = appearance == RailAppearance.glass;

    final corners = BorderRadius.horizontal(
      // Rounded on the inward side only; the edge side is flat against the
      // bezel, the same rule the full rail follows.
      left: onRightEdge ? radius : Radius.zero,
      right: onRightEdge ? Radius.zero : radius,
    );

    final nub = Container(
      width: AppMetrics.nubWidth,
      height: AppMetrics.nubHeight,
      decoration: BoxDecoration(
        color: isGlass
            ? palette.railFill.withValues(alpha: 0.30)
            : palette.railFill,
        borderRadius: corners,
        border: isGlass
            ? Border.all(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.22),
                width: 0.5,
              )
            : null,
      ),
    );

    if (!isGlass) return nub;

    // Blurs whatever the transparent window is sitting on. Unlike the open
    // rail, the sliver is small enough that a Flutter-side blur is honest
    // here — there is no large transparent area for it to frost by mistake.
    return ClipRRect(
      borderRadius: corners,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: nub,
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

/// A rail position with nothing in it.
///
/// The rail starts as four of these. Filling one is the user's decision, and
/// any provider can go in any position — a plus that always meant "connect the
/// provider we chose for this row" would not be a choice.
class _EmptySlot extends StatefulWidget {
  const _EmptySlot({
    required this.height,
    required this.onTap,
    required this.onEnter,
  });

  final double height;
  final VoidCallback onTap;

  /// Told when the pointer arrives, so the rail can drop whatever card it was
  /// showing.
  final VoidCallback onEnter;

  @override
  State<_EmptySlot> createState() => _EmptySlotState();
}

class _EmptySlotState extends State<_EmptySlot> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onEnter();
      },
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: widget.height,
          child: Center(
            child: AnimatedContainer(
              duration: AppMetrics.fadeAnimation,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _hovered
                      ? palette.textSecondary.withValues(alpha: 0.7)
                      : palette.textTertiary.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 14,
                color: _hovered ? palette.textSecondary : palette.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
