import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/rail_placement.dart';
import '../../services/native/native_bridge.dart';
import '../../services/settings_service.dart';
import '../../services/shell_controller.dart';
import '../../services/usage_controller.dart';
import '../theme/app_theme.dart';
import 'rail_callout.dart';
import 'rail_column.dart';

/// The edge widget.
///
/// Three states, in order of how often they are on screen:
///
///  * **at rest** — a sliver against the bezel,
///  * **open** — the rings, in a tab that grows out of the edge,
///  * **focused** — plus a card for whichever ring the pointer is on.
///
/// The window behind all of this never resizes. Swift holds it at the size of
/// the widest state and Flutter reveals what belongs on screen, which is what
/// lets the motion be one eased animation rather than a negotiation between
/// the window server and the framework.
class RailShell extends StatefulWidget {
  const RailShell({super.key});

  @override
  State<RailShell> createState() => _RailShellState();
}

class _RailShellState extends State<RailShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMetrics.expand,
    reverseDuration: AppMetrics.collapse,
  );

  /// The ring the pointer is on. Null means the rail is open but the pointer
  /// is between rings, which shows no card rather than an arbitrary one.
  String? _hoveredId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncExpansion(bool expanded) {
    if (expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
      if (_hoveredId != null) {
        // Drop the selection on the way out so re-opening does not flash the
        // previous provider's card before the pointer lands.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hoveredId = null);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    final usage = context.watch<UsageController>();
    final settings = context.watch<SettingsService>().settings;

    // Driven by the native hover state, not a Flutter MouseRegion: the window
    // is far larger than the visible sliver, so only Swift knows whether the
    // pointer is actually on the widget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncExpansion(shell.isExpanded);
    });

    final metrics = shell.metrics;
    final states = usage.slots;
    final onRight = settings.railEdge == RailEdge.right;

    final hovered = _hoveredId == null
        ? null
        : states.nonNulls.where((s) => s.id == _hoveredId).firstOrNull;

    return Stack(
      children: [
        Positioned(
          top: 0,
          bottom: 0,
          left: onRight ? null : metrics.shadowPadding,
          right: onRight ? metrics.shadowPadding : null,
          child: Center(
            child: Stack(
              alignment: onRight ? Alignment.centerRight : Alignment.centerLeft,
              children: [
                _CollapsedLayer(
                  animation: _controller,
                  child: RailNub(onRightEdge: onRight),
                ),
                _OpenLayer(
                  animation: _controller,
                  fromRight: onRight,
                  child: RailColumn(
                    states: states,
                    metrics: metrics,
                    hoveredId: _hoveredId,
                    onRightEdge: onRight,
                    appearance: settings.railAppearance,
                    onHoverSlot: (id) => setState(() => _hoveredId = id),
                    onOpenDetail: (id) => shell.openPanel(
                      ShellSurface.providerDetail,
                      providerId: id,
                    ),
                    onAddToSlot: (index) => shell.openPanel(
                      ShellSurface.slotPicker,
                      slotIndex: index,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hovered != null)
          _CalloutLayer(
            animation: _controller,
            metrics: metrics,
            slotIndex: states.indexOf(hovered),
            onRight: onRight,
            child: RailCallout(
              key: ValueKey(hovered.id),
              state: hovered,
              onRightEdge: onRight,
              onConnect: () => shell.openPanel(
                ShellSurface.connectProvider,
                providerId: hovered.id,
              ),
              onRetry: () => usage.refresh(hovered.id, manual: true),
            ),
          ),
      ],
    );
  }
}

/// The sliver, which fades out as the rail opens.
class _CollapsedLayer extends StatelessWidget {
  const _CollapsedLayer({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(parent: animation, curve: const Interval(0, 0.4)),
      ),
      child: IgnorePointer(child: child),
    );
  }
}

/// The rings, which slide out of the edge as the rail opens.
class _OpenLayer extends StatelessWidget {
  const _OpenLayer({
    required this.animation,
    required this.fromRight,
    required this.child,
  });

  final Animation<double> animation;
  final bool fromRight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return AnimatedBuilder(
      animation: curve,
      builder: (context, rail) {
        final t = curve.value;
        if (t == 0) return const SizedBox.shrink();

        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: FractionalTranslation(
            // Emerges from behind the bezel rather than fading in place.
            translation: Offset((fromRight ? 1 : -1) * (1 - t) * 0.6, 0),
            child: rail,
          ),
        );
      },
      child: child,
    );
  }
}

/// The card, positioned so its tail lands on the ring it describes.
class _CalloutLayer extends StatelessWidget {
  const _CalloutLayer({
    required this.animation,
    required this.metrics,
    required this.slotIndex,
    required this.onRight,
    required this.child,
  });

  final Animation<double> animation;
  final RailMetrics metrics;
  final int slotIndex;
  final bool onRight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset =
        metrics.shadowPadding + metrics.collapsedWidth + AppMetrics.calloutGap;

    return Positioned(
      top: metrics.slotCenterY(slotIndex),
      left: onRight ? null : inset,
      right: onRight ? inset : null,
      child: FractionalTranslation(
        // Centre the card on the ring, whatever height its content came out at.
        translation: const Offset(0, -0.5),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.35, 1, curve: Curves.easeOut),
          ),
          child: AnimatedSwitcher(
            duration: AppMetrics.fadeAnimation,
            switchInCurve: Curves.easeOut,
            child: child,
          ),
        ),
      ),
    );
  }
}
