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
    this.fromTop = false,
    this.entrance,
    this.appearance = RailAppearance.solid,
  });

  /// The rail's open animation, so each ring can arrive on its own.
  ///
  /// Null where the rail is drawn already open — the widget tests, and any
  /// surface that shows it without the reveal — in which case the slots
  /// simply render in place.
  final Animation<double>? entrance;

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

  /// Laid out across the screen, hanging from the top bezel.
  final bool fromTop;

  /// Solid or frosted. Glass thins the fill so the material behind it — drawn
  /// natively, because only AppKit can blur the desktop — actually shows.
  final RailAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isGlass = appearance == RailAppearance.glass;

    // Along the rail: down a side, across the top. Everything below reads this
    // rather than asking which edge it is, so another edge on the same axis
    // would need nothing more here.
    final axis = fromTop ? Axis.horizontal : Axis.vertical;

    // How far the rail runs, and how thick it is across. A slot's content is
    // a ring with its percentage beneath it whichever way the rail runs, so
    // the box keeps its shape and only its orientation changes.
    final extent = metrics.slotExtent(fromTop);
    final along =
        metrics.collapsedVerticalPadding * 2 + states.length * extent;
    final thickness = metrics.railThickness(fromTop);

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
      fromTop: fromTop,
      cornerRadius: metrics.notchCornerRadius,
      filletRadius: metrics.notchFilletRadius,
      child: SizedBox(
        // Sized from what is actually rendered, not from the slot count the
        // metrics were built with. The two can drift — a provider added to the
        // catalog without the native side agreeing — and the symptom is a
        // clipped ring rather than anything that names the cause.
        //
        // The rail's thickness is `collapsedWidth` on whichever axis it is
        // *not* running along, and the slots claim the other.
        width: fromTop ? along : thickness,
        height: fromTop ? thickness : along,
        child: Padding(
          padding: fromTop
              ? EdgeInsets.symmetric(
                  horizontal: metrics.collapsedVerticalPadding,
                )
              : EdgeInsets.symmetric(
                  vertical: metrics.collapsedVerticalPadding,
                ),
          child: Flex(
            direction: axis,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < states.length; index++)
                _Arriving(
                  animation: entrance,
                  index: index,
                  count: states.length,
                  fromRight: onRightEdge,
                  fromTop: fromTop,
                  child: switch (states[index]) {
                    final state? => _RailSlot(
                      state: state,
                      metrics: metrics,
                      extent: extent,
                      axis: axis,
                      isHovered: state.id == hoveredId,
                      onEnter: () => onHoverSlot(state.id),
                      onTap: () => onOpenDetail(state.id),
                    ),
                    null => _EmptySlot(
                      metrics: metrics,
                      extent: extent,
                      axis: axis,
                      // Clears the card on the way in. An empty position has
                      // no provider to describe, and without this the previous
                      // ring's card stays up — so a plus appeared to be
                      // claimed by whichever provider the pointer passed over
                      // last.
                      onEnter: () => onHoverSlot(null),
                      onTap: () => onAddToSlot(index),
                    ),
                  },
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
    required this.metrics,
    required this.extent,
    required this.axis,
    required this.isHovered,
    required this.onEnter,
    required this.onTap,
  });

  final ProviderState state;
  final RailMetrics metrics;

  /// How much room this slot takes along the rail.
  final double extent;

  /// Which way the rail runs, so the slot claims its space on that axis and
  /// leaves the other to the rail's thickness.
  final Axis axis;

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
          width: axis == Axis.horizontal ? extent : null,
          height: axis == Axis.horizontal ? null : extent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  _Jelly(
                    // A lift on hover confirms which ring the card belongs to,
                    // alongside the tail pointing at it.
                    active: isHovered,
                    child: UsageRing(
                      fraction: fraction,
                      diameter: metrics.ringDiameter,
                      stroke: metrics.ringStroke,
                      color: ringColor,
                      dimmed: !isLive,
                      // Sweeps while the figure shown is the previous one.
                      isReaching: state.isReaching,
                      // Drawn rather than typeset: a "+" from the system font
                      // sits off-centre in a ring and changes weight with the
                      // user's text settings.
                      child: ProviderGlyph(
                        providerId: state.id,
                        isEmpty: isEmpty,
                        color: isEmpty
                            ? palette.textTertiary
                            : palette.textPrimary,
                        size: metrics.ringDiameter * (isEmpty ? 0.34 : 0.47),
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
                SizedBox(height: 3 * metrics.scale),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: metrics.slotLabelSize,
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
    this.fromTop = false,
    this.metrics = RailMetrics.fallback,
    this.appearance = RailAppearance.solid,
  });

  final bool onRightEdge;

  /// Lying along the top bezel rather than standing against a side.
  final bool fromTop;

  /// The sliver follows the rail's scale, so it does not stay a fixed size
  /// against a rail that grew or shrank with the display.
  final RailMetrics metrics;

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
    final radius = Radius.circular(metrics.nubRadius);
    final isGlass = appearance == RailAppearance.glass;

    // Rounded on the inward side only; the edge side is flat against the
    // bezel, the same rule the full rail follows.
    final corners = fromTop
        ? BorderRadius.vertical(bottom: radius)
        : BorderRadius.horizontal(
            left: onRightEdge ? radius : Radius.zero,
            right: onRightEdge ? Radius.zero : radius,
          );

    final nub = Container(
      width: fromTop ? metrics.nubHeight : metrics.nubWidth,
      height: fromTop ? metrics.nubWidth : metrics.nubHeight,
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
    required this.extent,
    required this.axis,
    required this.metrics,
    required this.onTap,
    required this.onEnter,
  });

  final double extent;
  final Axis axis;
  final RailMetrics metrics;
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
          width: widget.axis == Axis.horizontal ? widget.extent : null,
          height: widget.axis == Axis.horizontal ? null : widget.extent,
          child: Center(
            child: _Jelly(
              active: _hovered,
              child: AnimatedContainer(
                duration: AppMetrics.fadeAnimation,
                width: widget.metrics.ringDiameter * 0.875,
                height: widget.metrics.ringDiameter * 0.875,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _hovered
                        ? palette.textSecondary.withValues(alpha: 0.7)
                        : palette.textTertiary.withValues(alpha: 0.35),
                    width: 1.2 * widget.metrics.scale,
                  ),
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: widget.metrics.ringDiameter * 0.44,
                  color: _hovered
                      ? palette.textSecondary
                      : palette.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Springs its child up on hover and lets it settle.
///
/// A plain scale animation arrives at its new size and stops, which reads as
/// the icon changing size rather than reacting to the pointer. This overshoots
/// and settles — the give of something soft being pressed — which is what makes
/// the rail feel answerable rather than redrawn.
///
/// The two directions are not symmetrical on purpose. Arriving gets the
/// overshoot, because that is the moment worth acknowledging; leaving is a
/// short ease back, because a wobble on the way out draws the eye to a ring
/// the pointer has already left.
class _Jelly extends StatefulWidget {
  const _Jelly({required this.active, required this.child});

  final bool active;
  final Widget child;

  /// How much larger the child grows at rest inside the spring.
  static const double lift = 1.12;

  @override
  State<_Jelly> createState() => _JellyState();
}

class _JellyState extends State<_Jelly> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 220),
    value: widget.active ? 1 : 0,
  );

  late final Animation<double> _scale = _controller.drive(
    Tween<double>(begin: 1, end: _Jelly.lift).chain(
      CurveTween(
        curve: Curves.elasticOut,
        // `elasticOut` run backwards wobbles on the way out, which is exactly
        // what should not happen to a ring the pointer has left.
      ),
    ),
  );

  late final Animation<double> _settle = _controller.drive(
    Tween<double>(begin: 1, end: _Jelly.lift).chain(
      CurveTween(curve: Curves.easeOutCubic),
    ),
  );

  @override
  void didUpdateWidget(_Jelly oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    widget.active ? _controller.forward(from: 0) : _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.status == AnimationStatus.reverse
            ? _settle.value
            : _scale.value;
        return Transform.scale(scale: value, child: child);
      },
      child: widget.child,
    );
  }
}

/// Brings one slot in on its own, a beat after the one above it.
///
/// The rail used to arrive as a single block sliding out of the bezel: every
/// ring already in its final place relative to the others, the whole slab
/// translating together. That reads as a panel being pushed on screen rather
/// than as the rail assembling itself.
///
/// Each slot now travels its own distance on its own slice of the reveal, so
/// they land one after another. The stagger is small — a slot starts before
/// the one above it has settled — because a queue that waits its turn feels
/// slow, while an overlap feels like one motion with depth in it.
class _Arriving extends StatelessWidget {
  const _Arriving({
    required this.animation,
    required this.index,
    required this.count,
    required this.fromRight,
    required this.child,
    this.fromTop = false,
  });

  final Animation<double>? animation;
  final int index;
  final int count;
  final bool fromRight;

  /// Arriving downward out of the top bezel rather than sideways.
  final bool fromTop;

  final Widget child;

  /// How much of the reveal each slot waits before starting.
  ///
  /// A fifth of it, so with three slots the last begins at forty per cent —
  /// far enough behind the first to be seen as a separate arrival rather than
  /// a blur, and still overlapping it.
  static const double _stagger = 0.20;

  /// How much of the reveal each slot takes to arrive. The last one finishes
  /// exactly as the reveal does.
  static const double _span = 0.60;

  @override
  Widget build(BuildContext context) {
    final parent = animation;
    if (parent == null) return child;

    final start = (index * _stagger).clamp(0.0, 1.0 - _span);
    final interval = Interval(start, start + _span);

    // Closing runs as one motion rather than in reverse order. Unbuilding
    // itself piece by piece draws attention to a widget the user has just
    // finished with.
    final travel = CurvedAnimation(
      parent: parent,
      curve: Interval(start, start + _span, curve: Curves.easeOutBack),
      reverseCurve: Curves.easeInCubic,
    );
    final fade = CurvedAnimation(
      parent: parent,
      curve: interval,
      reverseCurve: const Interval(0, 0.5, curve: Curves.easeIn),
    );

    return AnimatedBuilder(
      animation: parent,
      builder: (context, slot) {
        final t = travel.value;
        return Opacity(
          opacity: fade.value.clamp(0.0, 1.0),
          child: Transform.translate(
            // Out from behind the bezel, and a shade under its resting size,
            // so it reads as coming toward the user rather than sliding past.
            offset: fromTop
                ? Offset(0, -(1 - t) * 34)
                : Offset((fromRight ? 1 : -1) * (1 - t) * 34, 0),
            child: Transform.scale(
              scale: 0.72 + 0.28 * t.clamp(0.0, 1.4),
              child: slot,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
