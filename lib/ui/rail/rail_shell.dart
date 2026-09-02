import 'dart:async';
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
import 'rail_settings_button.dart';

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

  /// Sets the hovered ring and keeps the window's pointer target in step.
  ///
  /// The target widens to take the card in while one is drawn, so moving from
  /// a ring onto its card does not close the rail on the way. The window
  /// cannot work this out for itself — the card is Flutter's.
  void _setHovered(String? id) {
    if (id == _hoveredId) return;
    setState(() => _hoveredId = id);
    unawaited(context.read<NativeBridge>().setRailCardVisible(id != null));
  }

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
          if (mounted) _setHovered(null);
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
                  child: RailNub(
                    onRightEdge: onRight,
                    appearance: settings.railAppearance,
                  ),
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
                    onHoverSlot: _setHovered,
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
        _SettingsLayer(
          animation: _controller,
          metrics: metrics,
          slotCount: states.length,
          onRight: onRight,
          enabled: shell.isExpanded,
          child: RailSettingsButton(
            railExpanded: shell.isExpanded,
            onRightEdge: onRight,
            appearance: settings.railAppearance,
            onPressed: () => shell.openPanel(ShellSurface.settings),
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

/// The settings affordance that lives below the provider rail.
class _SettingsLayer extends StatelessWidget {
  const _SettingsLayer({
    required this.animation,
    required this.metrics,
    required this.slotCount,
    required this.onRight,
    required this.enabled,
    required this.child,
  });

  final Animation<double> animation;
  final RailMetrics metrics;
  final int slotCount;
  final bool onRight;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controlSize = metrics.settingsButtonSize + 8;
    final sideOffset =
        metrics.shadowPadding + (metrics.collapsedWidth - controlSize) / 2;

    return Positioned(
      top: metrics.settingsButtonTop(slotCount) - 4,
      left: onRight ? null : sideOffset,
      right: onRight ? sideOffset : null,
      child: IgnorePointer(
        ignoring: !enabled,
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.45, 1, curve: Curves.easeOut),
            reverseCurve: const Interval(0, 0.4, curve: Curves.easeIn),
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.45, 1, curve: Curves.easeOutBack),
              ),
            ),
            child: child,
          ),
        ),
      ),
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

    // Animated, not plain: moving between rings changes only `top`, and a
    // plain Positioned teleports the card there. The switcher below cross-fades
    // the contents, so without this the card's frame jumps to the new ring
    // while its text fades — which reads as one card vanishing and another
    // appearing rather than the same card following the pointer.
    return AnimatedPositioned(
      duration: AppMetrics.calloutMove,
      curve: Curves.easeOutCubic,
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
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
              ),
            ),
            alignment: onRight ? Alignment.centerRight : Alignment.centerLeft,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: Offset(onRight ? 0.04 : -0.04, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: const Interval(
                        0.35,
                        1,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                  ),
              // One card, swapped in place.
              //
              // There used to be an AnimatedSwitcher here, cross-fading the
              // old provider's card out while the new one came in. Combined
              // with the AnimatedPositioned above it, that put **two complete
              // cards on screen at once**: the switcher keeps the outgoing
              // child mounted for the length of its transition, and its Stack
              // centres children of different heights on each other, so two
              // cards of different sizes ended up visibly apart rather than
              // overlapping. Moving the pointer across the rail showed a card
              // for a ring the pointer had already left, sitting beside the
              // one for the ring it was on.
              //
              // The card is meant to *follow* the pointer, which is what the
              // AnimatedPositioned does. Its contents belong to whichever ring
              // it has arrived at, and there is only ever one of it.
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
