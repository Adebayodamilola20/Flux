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

    /// The usable height the rail is drawn at full size for, in points.
    ///
    /// A 13-inch laptop, which is the smallest display this is meant for —
    /// *not* the largest. Measuring down from a desktop-sized reference is
    /// what made the rail shrink on the machines most people use it on: a
    /// 13-inch reported about 875 points against a 1080-point reference and
    /// got a rail a fifth smaller than the one it was designed as, which read
    /// as an afterthought stuck to the bezel. A laptop now gets the rail at
    /// the size it was drawn, and bigger displays grow from there.
    private static let referenceHeight: CGFloat = 900

    /// How much of a display's extra height turns into extra rail.
    ///
    /// Not all of it. A 34-inch ultrawide is 60% taller than a 13-inch laptop,
    /// and a rail 60% larger on it would be furniture. At this rate the same
    /// ultrawide lands at 1.26 — exactly where it already sat, and where it
    /// looks right — while every laptop stays close to 1.
    private static let growthRate: CGFloat = 0.43

    /// Bounds on the result.
    ///
    /// The floor is close to 1 on purpose: nothing this app runs on should get
    /// a rail meaningfully smaller than the one it was designed as. The
    /// ceiling stops a very tall display turning it into furniture.
    private static let minScale: CGFloat = 0.95
    private static let maxScale: CGFloat = 1.35

    /// Works out the scale for a display.
    ///
    /// Driven by height in points rather than pixels: points are what the user
    /// has already told macOS they want things to be, so a Retina laptop set
    /// to "More Space" reports a taller screen and gets a slightly smaller
    /// rail, which is the behaviour wanted.
    ///
    /// Measured from the display, not the usable area inside it. The usable
    /// area stops above the Dock, so a rail sized from it changed size when
    /// the Dock was shown, hidden, or moved to the side — and on a laptop,
    /// where the Dock takes a far larger share of a shorter screen, it made
    /// the rail smaller still. How big the display is does not depend on
    /// what else is on it.
    ///
    /// Worked examples, at the default resolution of each:
    ///
    ///     13-inch laptop     900 pt   ->  1.00
    ///     15-inch laptop     982 pt   ->  1.04
    ///     16-inch laptop    1117 pt   ->  1.10
    ///     34-inch ultrawide 1440 pt   ->  1.26
    static func scale(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return 1 }
        let height = screen.frame.height
        guard height > 0 else { return 1 }

        let ratio = height / referenceHeight
        let scaled = 1 + (ratio - 1) * growthRate
        return min(max(scaled, minScale), maxScale)
    }

    /// Scales a base measurement and lands it on a whole point, so an edge
    /// never falls on a half pixel.
    ///
    /// One scale, from the display, whichever edge the rail is on. A top rail
    /// was briefly drawn larger on the theory that it needs more presence in
    /// the part of the screen the user is already looking at; in practice it
    /// just made it bulky next to everything else up there. The rings are the
    /// same rings wherever the rail is.
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

    /// The resting sliver, as drawn. Mirrors `_baseNubWidth` in Dart.
    static var nubWidth: CGFloat { s(11) }
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

    /// Slots on a top rail get a little more room than their box needs.
    ///
    /// Stacked down a side, a ring's neighbours are its own width away and the
    /// eye reads them as a column. Laid out across at that spacing they crowd —
    /// three rings and three percentages in a row with nothing between them.
    /// This is the gap, not a bigger ring. Mirrors `_horizontalSlotSpacing` in
    /// `RailMetrics` on the Dart side.
    private static let horizontalSlotSpacing: CGFloat = 1.22

    /// A slot's box, in the two directions the rail can run.
    ///
    /// The content is the same shape either way — a ring with its percentage
    /// beneath — so the box is too: `collapsedWidth` across the rail and
    /// `slotHeight` along it. What changes is which of those lies along the
    /// rail. Getting it backwards makes the rail exactly as thick as a ring
    /// and pushes every label out of it.
    static func railThickness(edge: RailEdge) -> CGFloat {
        edge.isHorizontal ? slotHeight : collapsedWidth
    }

    static func slotExtent(edge: RailEdge) -> CGFloat {
        edge.isHorizontal
            ? (collapsedWidth * horizontalSlotSpacing).rounded()
            : slotHeight
    }

    static func railLength(slots: Int, edge: RailEdge) -> CGFloat {
        CGFloat(slots) * slotExtent(edge: edge) + collapsedVerticalPadding * 2
    }

    /// Full window size. Fixed across every state so the window never resizes
    /// while animating — Flutter animates inside a stationary window, which is
    /// what keeps the motion smooth.
    static func windowSize(slots: Int, edge: RailEdge = .right) -> NSSize {
        // The rail's own length in the direction it runs, which is not the
        // same number for the two axes: a top rail's slots are wider than they
        // are tall and carry extra spacing between them.
        let alongWithSettings = railLength(slots: slots, edge: edge)
            + settingsButtonGap
            + settingsButtonSize
            + settingsHotZonePadding

        // The same window turned on its side. Sized for the widest state
        // either way, because Flutter animates inside a window that never
        // resizes.
        if edge.isHorizontal {
            return NSSize(
                width: max(expandedHeight, alongWithSettings) + shadowPadding * 2,
                height: expandedWidth + shadowPadding * 2
            )
        }

        return NSSize(
            width: expandedWidth + shadowPadding * 2,
            height: max(expandedHeight, alongWithSettings) + shadowPadding * 2
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
        if edge.isHorizontal {
            return NSRect(
                x: (windowSize.width - nubHotZoneHeight) / 2,
                y: windowSize.height - shadowPadding - nubHotZoneWidth,
                width: nubHotZoneHeight,
                height: nubHotZoneWidth
            )
        }
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
        let along = min(railLength(slots: slots, edge: edge), edge.isHorizontal
            ? windowSize.width
            : windowSize.height)
        let thickness = railThickness(edge: edge)

        if edge.isHorizontal {
            // Hanging from the top: flat against the bezel, so it is pinned to
            // the top of the window rather than centred in it.
            return NSRect(
                x: (windowSize.width - along) / 2,
                y: windowSize.height - shadowPadding - thickness,
                width: along,
                height: thickness
            )
        }

        let x: CGFloat = edge == .right
            ? windowSize.width - shadowPadding - thickness
            : shadowPadding
        return NSRect(
            x: x,
            y: (windowSize.height - along) / 2,
            width: thickness,
            height: along
        )
    }

    /// The settings control below the rail, in the window's coordinate space.
    static func settingsButtonRect(
        in windowSize: NSSize,
        edge: RailEdge,
        slots: Int
    ) -> NSRect {
        let rail = railRect(in: windowSize, edge: edge, slots: slots)

        // Beyond the far end of the rail, whichever way it runs. Below a side
        // rail, past the trailing edge of a top one — a top rail has nothing
        // below it but the hover card, and putting the control there would
        // stack the two.
        if edge.isHorizontal {
            return NSRect(
                x: rail.maxX + settingsButtonGap,
                y: rail.midY - settingsButtonSize / 2,
                width: settingsButtonSize,
                height: settingsButtonSize
            )
        }

        return NSRect(
            x: rail.midX - settingsButtonSize / 2,
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
    ///
    /// - Parameter includingCard: widen to take the hover card in. Only true
    ///   while a card is actually drawn: it is a readout the pointer can reach
    ///   for — the retry and detail controls live on it — so while one is up,
    ///   the space between the rail and it has to stay live or the card
    ///   disappears on the way to being clicked. With no card up there is
    ///   nothing out there to reach, and the zone stays the rail's own width.
    static func openHotZone(
        in windowSize: NSSize,
        edge: RailEdge,
        slots: Int,
        includingCard: Bool = false
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

        // A top rail runs the other way, so the union is taken across and the
        // zone deepens downward for the card rather than widening sideways.
        if edge.isHorizontal {
            let minX = min(settings.minX, rail.minX)
            let maxX = max(settings.maxX, rail.maxX)
            let depth = includingCard ? expandedWidth : railThickness(edge: edge)
            return NSRect(
                x: minX,
                y: windowSize.height - shadowPadding - depth,
                width: min(maxX - minX, windowSize.width),
                height: min(depth, windowSize.height)
            )
        }

        let minY = min(settings.minY, rail.minY)
        let maxY = max(settings.maxY, rail.maxY)
        let height = min(maxY - minY, windowSize.height)
        let width = includingCard ? expandedWidth : railThickness(edge: edge)
        let x: CGFloat = edge == .right
            ? windowSize.width - shadowPadding - width
            : shadowPadding
        return NSRect(
            x: x,
            y: minY,
            width: width,
            height: height
        )
    }

    /// Values handed to Flutter so its layout matches the window exactly.
    static func channelPayload(slots: Int, edge: RailEdge = .right) -> [String: Any] {
        let size = windowSize(slots: slots, edge: edge)
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
            // What Flutter draws inside the rail has to grow by the same
            // amount, or a bigger top notch would hold the same small rings.
            "scale": Double(scale),
        ]
    }
}

/// Which screen edge the rail clings to. Mirrors `RailEdge` in Dart.
enum RailEdge: String {
    case left
    case right
    case top

    init(name: String?) {
        self = RailEdge(rawValue: name ?? "") ?? .right
    }

    /// True when the rail lays its slots out across the screen.
    var isHorizontal: Bool { self == .top }
}
