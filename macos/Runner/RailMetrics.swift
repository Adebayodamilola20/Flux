import Foundation

/// The rail's geometry, in points.
///
/// This is the single source of truth for the widget's size on both sides of
/// the platform channel: Swift positions the window with these numbers and
/// sends the same values to Flutter, which lays the card out inside them. A
/// constant duplicated in Dart would eventually drift, and the symptom would be
/// a hover zone that no longer matches what the user can see.
enum RailMetrics {

    /// Width of the rail once it is open.
    static let collapsedWidth: CGFloat = 52

    /// Width of the open rail plus its hover card.
    static let expandedWidth: CGFloat = 280

    /// Vertical space each provider slot occupies.
    static let slotHeight: CGFloat = 58

    /// Padding above and below the stack of slots. Large enough to clear the
    /// reverse curves the rail's outline makes where it meets the screen edge.
    static let collapsedVerticalPadding: CGFloat = 16

    /// Room reserved around the card for its shadow. The window must be larger
    /// than the card or the shadow is clipped at the window edge.
    static let shadowPadding: CGFloat = 26

    /// The resting sliver, as drawn.
    static let nubWidth: CGFloat = 7
    static let nubHeight: CGFloat = 84

    /// The pointer target for that sliver.
    ///
    /// Deliberately larger than the sliver itself. Seven points is the right
    /// size to look at and the wrong size to aim at; a target the user has to
    /// hunt for makes the whole widget feel unreliable. Widening it costs
    /// nothing because the area is transparent and click-through while closed.
    static let nubHotZoneWidth: CGFloat = 16
    static let nubHotZoneHeight: CGFloat = 120

    /// Height of the open rail at its tallest. The window is sized for the
    /// worst case so it never has to resize mid-animation.
    static let expandedHeight: CGFloat = 468

    /// Height of the open rail for a given number of provider slots.
    static func collapsedHeight(slots: Int) -> CGFloat {
        CGFloat(slots) * slotHeight + collapsedVerticalPadding * 2
    }

    /// Full window size. Fixed across every state so the window never resizes
    /// while animating — Flutter animates inside a stationary window, which is
    /// what keeps the motion smooth.
    static func windowSize(slots: Int) -> NSSize {
        NSSize(
            width: expandedWidth + shadowPadding * 2,
            height: max(expandedHeight, collapsedHeight(slots: slots))
                + shadowPadding * 2
        )
    }

    /// The pointer target while the rail is at rest, in the window's own
    /// coordinate space.
    ///
    /// Anchored to the screen-edge side, because that is where the sliver is
    /// drawn — the rest of the window is empty and must not react.
    static func restingHotZone(
        in windowSize: NSSize,
        edge: RailEdge
    ) -> NSRect {
        let x: CGFloat = edge == .right
            ? windowSize.width - shadowPadding - nubHotZoneWidth
            : shadowPadding
        return NSRect(
            x: x,
            y: (windowSize.height - nubHotZoneHeight) / 2,
            width: nubHotZoneWidth,
            height: nubHotZoneHeight
        )
    }

    /// The rail's drawn rectangle — the column of rings, not its hover target.
    ///
    /// Distinct from [openHotZone], which spans the card as well: the pointer
    /// target is deliberately larger than what is painted, and frosting the
    /// hover zone would put a blurred rectangle over empty screen.
    static func railRect(
        in windowSize: NSSize,
        edge: RailEdge,
        slots: Int
    ) -> NSRect {
        let height = min(collapsedHeight(slots: slots), windowSize.height)
        let x: CGFloat = edge == .right
            ? windowSize.width - shadowPadding - collapsedWidth
            : shadowPadding
        return NSRect(
            x: x,
            y: (windowSize.height - height) / 2,
            width: collapsedWidth,
            height: height
        )
    }

    /// The pointer target while the rail is open: the rail and its card.
    static func openHotZone(
        in windowSize: NSSize,
        edge: RailEdge
    ) -> NSRect {
        let height = min(expandedHeight, windowSize.height)
        let x: CGFloat = edge == .right
            ? windowSize.width - shadowPadding - expandedWidth
            : shadowPadding
        return NSRect(
            x: x,
            y: (windowSize.height - height) / 2,
            width: expandedWidth,
            height: height
        )
    }

    /// Values handed to Flutter so its layout matches the window exactly.
    static func channelPayload(slots: Int) -> [String: Any] {
        let size = windowSize(slots: slots)
        return [
            "collapsedWidth": Double(collapsedWidth),
            "expandedWidth": Double(expandedWidth),
            "slotHeight": Double(slotHeight),
            "collapsedVerticalPadding": Double(collapsedVerticalPadding),
            "shadowPadding": Double(shadowPadding),
            "edgeInset": 0.0,
            "windowWidth": Double(size.width),
            "windowHeight": Double(size.height),
            "slots": slots,
        ]
    }
}

/// Which screen edge the rail clings to. Mirrors `RailEdge` in Dart.
enum RailEdge: String {
    case left
    case right

    init(name: String?) {
        self = RailEdge(rawValue: name ?? "") ?? .right
    }
}
