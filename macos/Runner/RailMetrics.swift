import Cocoa

/// The rail's geometry, in points.
///
/// This is the single source of truth for the widget's size on both sides of
/// the platform channel: Swift positions the window with these numbers and
/// sends the same values to Flutter, which lays the card out inside them. A
/// constant duplicated in Dart would eventually drift, and the symptom would be
/// a hover zone that no longer matches what the user can see.
enum RailMetrics {

    // MARK: - Scale

    /// How much larger or smaller the rail is drawn than its base size.
    ///
    /// Set from the display the rail is on, by `RailWindowController`. A rail
    /// sized for a 27-inch display is a slab on a 13-inch laptop, and one
    /// sized for the laptop is a row of dots on the 27-inch. The answer is not
    /// a table of device names — that is wrong for every display nobody
    /// thought of — but one ratio against a reference height.
    static var scale: CGFloat = 1

    /// The height this design was drawn against, in points.
    private static let referenceHeight: CGFloat = 1080

    /// Bounds on that ratio.
    ///
    /// Without them a very small display shrinks the rings past being
    /// clickable, and a very tall one turns the rail into furniture. This
    /// range is what still reads as the same product.
    private static let minScale: CGFloat = 0.82
    private static let maxScale: CGFloat = 1.35

    /// Works out the scale for a display.
    ///
    /// Driven by height in points rather than pixels: points are what the user
    /// has already told macOS they want things to be, so a Retina laptop set
    /// to "More Space" reports a taller screen and gets a proportionally
    /// smaller rail, which is the behaviour wanted.
    static func scale(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return 1 }
        let height = screen.visibleFrame.height
        guard height > 0 else { return 1 }
        return min(max(height / referenceHeight, minScale), maxScale)
    }

    /// Scales a base measurement and lands it on a whole point, so an edge
    /// never falls on a half pixel.
    private static func s(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded()
    }

    // MARK: - Geometry

    /// Width of the rail once it is open.
    static var collapsedWidth: CGFloat { s(46) }

    /// Width of the open rail plus its hover card.
    static var expandedWidth: CGFloat { s(280) }

    /// Vertical space each provider slot occupies.
    static var slotHeight: CGFloat { s(66) }

    /// Padding above and below the stack of slots. Large enough to clear the
    /// reverse curves the rail's outline makes where it meets the screen edge.
    static var collapsedVerticalPadding: CGFloat { s(28) }

    /// Room reserved around the card for its shadow. The window must be larger
    /// than the card or the shadow is clipped at the window edge.
    static var shadowPadding: CGFloat { s(26) }

    /// The settings affordance below the provider stack.
    ///
    /// The gap is measured to the control's box, not to what it draws. Folded,
    /// the control is a stroked arc inset roughly ten points inside that box,
    /// so a positive gap here leaves the arc floating well clear of the rail.
    /// A slightly negative value is what seats it against the rail's edge.
    static var settingsButtonSize: CGFloat { s(34) }
    static var settingsButtonGap: CGFloat { s(-4) }
    static var settingsHotZonePadding: CGFloat { s(8) }

    /// The resting sliver, as drawn.
    static var nubWidth: CGFloat { s(7) }
    static var nubHeight: CGFloat { s(84) }

    /// The pointer target for that sliver.
    ///
    /// Deliberately larger than the sliver itself. Seven points is the right
    /// size to look at and the wrong size to aim at; a target the user has to
    /// hunt for makes the whole widget feel unreliable. Widening it costs
    /// nothing because the area is transparent and click-through while closed.
    static var nubHotZoneWidth: CGFloat { s(16) }
    static var nubHotZoneHeight: CGFloat { s(120) }

    /// Height of the open rail at its tallest. Sized for the three-slot rail
    /// plus enough room for the hover card to breathe.
    static var expandedHeight: CGFloat { s(260) }

    /// Height of the open rail for a given number of provider slots.
    static func collapsedHeight(slots: Int) -> CGFloat {
        CGFloat(slots) * slotHeight + collapsedVerticalPadding * 2
    }

    /// Full window size. Fixed across every state so the window never resizes
    /// while animating — Flutter animates inside a stationary window, which is
    /// what keeps the motion smooth.
    static func windowSize(slots: Int) -> NSSize {
        let heightWithSettings = collapsedHeight(slots: slots)
            + settingsButtonGap
            + settingsButtonSize
            + settingsHotZonePadding

        return NSSize(
            width: expandedWidth + shadowPadding * 2,
            height: max(expandedHeight, heightWithSettings) + shadowPadding * 2
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

    /// The settings control below the rail, in the window's coordinate space.
    static func settingsButtonRect(
        in windowSize: NSSize,
        edge: RailEdge,
        slots: Int
    ) -> NSRect {
        let rail = railRect(in: windowSize, edge: edge, slots: slots)
        let x = rail.midX - settingsButtonSize / 2
        return NSRect(
            x: x,
            y: rail.minY - settingsButtonGap - settingsButtonSize,
            width: settingsButtonSize,
            height: settingsButtonSize
        )
    }

    /// The pointer target while the rail is open: the rail and its control.
    ///
    /// Deliberately *not* widened to take in the hover card. The card is a
    /// readout that follows the pointer down the rail, not somewhere to travel
    /// to, and spanning it meant the rail stayed open across the width of the
    /// card — so leaving the rail did not close it, and the user had to clear
    /// the card as well before anything went away.
    static func openHotZone(
        in windowSize: NSSize,
        edge: RailEdge,
        slots: Int
    ) -> NSRect {
        let settings = settingsButtonRect(
            in: windowSize,
            edge: edge,
            slots: slots
        ).insetBy(
            dx: -settingsHotZonePadding,
            dy: -settingsHotZonePadding
        )
        let rail = railRect(in: windowSize, edge: edge, slots: slots)
        let minY = min(settings.minY, rail.minY)
        let maxY = max(settings.maxY, rail.maxY)
        let height = min(maxY - minY, windowSize.height)
        let x: CGFloat = edge == .right
            ? windowSize.width - shadowPadding - collapsedWidth
            : shadowPadding
        return NSRect(
            x: x,
            y: minY,
            width: collapsedWidth,
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
            "settingsButtonSize": Double(settingsButtonSize),
            "settingsButtonGap": Double(settingsButtonGap),
            "edgeInset": 0.0,
            "windowWidth": Double(size.width),
            "windowHeight": Double(size.height),
            "slots": slots,
            "scale": Double(scale),
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
