/// Which screen edge the rail clings to.
enum RailEdge {
  left,
  right;

  String get label => switch (this) {
        RailEdge.left => 'Left edge',
        RailEdge.right => 'Right edge',
      };

  RailEdge get opposite => this == RailEdge.left ? RailEdge.right : RailEdge.left;
}

/// How the rail behaves when the pointer is not over it.
enum RailExpansion {
  /// Expand on hover, collapse when the pointer leaves. The default.
  onHover,

  /// Expand on click, stay open until dismissed. For users who find
  /// hover-expansion twitchy.
  onClick,

  /// Never collapse. Costs screen space but never moves under the pointer.
  alwaysExpanded;

  String get label => switch (this) {
        RailExpansion.onHover => 'Expand on hover',
        RailExpansion.onClick => 'Expand on click',
        RailExpansion.alwaysExpanded => 'Always expanded',
      };

  String get detail => switch (this) {
        RailExpansion.onHover =>
          'Opens as soon as the pointer reaches the edge.',
        RailExpansion.onClick => 'Opens only when you click the rail.',
        RailExpansion.alwaysExpanded => 'Stays open all the time.',
      };

  bool get expandsOnHover => this == RailExpansion.onHover;
  bool get autoCollapses => this != RailExpansion.alwaysExpanded;
}

/// Vertical placement of the rail along its edge, as a fraction of the screen's
/// usable height measured from the top.
///
/// 0.5 centres it, which is where the design puts it by default.
class RailOffset {
  const RailOffset(this.fraction)
      : assert(fraction >= 0 && fraction <= 1, 'fraction must be 0–1');

  final double fraction;

  static const RailOffset centered = RailOffset(0.5);

  double clamped() => fraction.clamp(0.05, 0.95);

  @override
  bool operator ==(Object other) =>
      other is RailOffset && other.fraction == fraction;

  @override
  int get hashCode => fraction.hashCode;
}
