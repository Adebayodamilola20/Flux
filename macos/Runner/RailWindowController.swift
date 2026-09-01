import Cocoa

/// Places the rail against a screen edge, decides when the pointer is over it,
/// and switches the window between the rail and the setup panel.
///
/// Expansion never resizes the window. The window is always the size of the
/// expanded card; Flutter animates the card inside it while the frame stays
/// put. Resizing a window every time the pointer arrives is what makes this
/// kind of widget feel cheap — the window server and the Flutter animation each
/// pick their own timing and the edges visibly disagree.
///
/// The cost of a fixed-size window is a large transparent area that would
/// otherwise swallow clicks meant for the app underneath. `ignoresMouseEvents`
/// is toggled with the expansion state to give that area back while collapsed.
final class RailWindowController {

    /// How long the pointer must be away before the rail collapses. Short
    /// enough to feel immediate, long enough to survive crossing a gap between
    /// two parts of the card.
    private static let collapseGrace: TimeInterval = 0.18

    private let window: RailWindow
    private let slotCount: Int

    private var moveMonitors: [Any] = []
    private var collapseWorkItem: DispatchWorkItem?

    private(set) var isExpanded = false

    /// Frosted material behind the rail, when the user asks for it.
    let glass = RailGlass()
    private(set) var isRailVisible = false

    private var edge: RailEdge = .right
    private var offsetFraction: CGFloat = 0.5
    private var preferredScreenId: String?

    /// True when the rail should ignore hover entirely because the user asked
    /// for it to stay open.
    private var isPinnedOpen = false

    /// Raised when the pointer enters or leaves the widget, so Flutter can run
    /// the expand and collapse animation.
    var onExpansionChanged: ((Bool) -> Void)?

    /// Raised when the window switches between rail and setup panel.
    var onModeChanged: ((RailMode) -> Void)?

    init(window: RailWindow, slotCount: Int) {
        self.window = window
        self.slotCount = slotCount
        window.configureCommon()
        window.apply(mode: .rail)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        removeMonitors()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Placement

    func configure(edge: RailEdge, offsetFraction: CGFloat, screenId: String?) {
        self.edge = edge
        self.offsetFraction = min(max(offsetFraction, 0.05), 0.95)
        self.preferredScreenId = screenId
        if isRailVisible {
            reposition()
        }
    }

    /// The display the rail should live on.
    ///
    /// Falls back to the screen with the menu bar when the remembered display
    /// has been disconnected, so unplugging a monitor never strands the widget
    /// off-screen.
    private func targetScreen() -> NSScreen? {
        if let id = preferredScreenId,
           let match = NSScreen.screens.first(where: { $0.railIdentifier == id }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func reposition() {
        guard let screen = targetScreen() else { return }

        let size = RailMetrics.windowSize(slots: slotCount)
        let visible = screen.visibleFrame

        // Flush against the bezel. The rail is meant to read as part of the
        // display, and any gap at all — even a point — breaks that and turns it
        // back into a window parked near the edge.
        let x: CGFloat = edge == .right
            ? visible.maxX - size.width + RailMetrics.shadowPadding
            : visible.minX - RailMetrics.shadowPadding

        // `offsetFraction` is measured from the top, the way the user reads the
        // screen; AppKit's origin is at the bottom.
        let usable = visible.height - size.height
        let y = visible.maxY - size.height - usable * offsetFraction

        window.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: true,
            animate: false
        )

        // The frost follows the rail: same rectangle, same edge, recomputed
        // whenever the window moves or the edge changes.
        if let contentView = window.contentView {
            glass.attach(to: contentView)
        }
        glass.layout(windowSize: size, edge: edge, slots: slotCount)
    }

    @objc private func screensChanged() {
        guard isRailVisible, window.mode == .rail else { return }
        reposition()
    }

    // MARK: - Rail visibility

    func showRail(pinnedOpen: Bool) {
        isPinnedOpen = pinnedOpen
        window.apply(mode: .rail)
        onModeChanged?(.rail)

        reposition()
        window.isPresentationAllowed = true
        window.orderFront(nil)
        isRailVisible = true

        // Visibility is not set here: the frost belongs to the open rail, and
        // `setExpanded` is what knows whether that is what is on screen.
        setExpanded(pinnedOpen, notify: true, force: true)
        installMonitors()
    }

    func hideRail() {
        guard isRailVisible else { return }
        isRailVisible = false
        glass.setVisible(false)
        removeMonitors()
        window.orderOut(nil)
        window.isPresentationAllowed = false
    }

    func setPinnedOpen(_ pinned: Bool) {
        isPinnedOpen = pinned
        guard isRailVisible, window.mode == .rail else { return }
        if pinned {
            cancelPendingCollapse()
            setExpanded(true, notify: true)
        } else {
            evaluateHover(at: NSEvent.mouseLocation)
        }
    }

    /// Opens the rail programmatically — from the menu-bar item, or when a
    /// click is the configured way to expand it.
    func expandNow() {
        cancelPendingCollapse()
        setExpanded(true, notify: true)
    }

    // MARK: - Setup panel

    func showPanel(size: NSSize) {
        cancelPendingCollapse()
        removeMonitors()
        isRailVisible = false
        // The panel draws its own background; frost sized to the rail would
        // sit in the middle of it.
        glass.setVisible(false)

        window.apply(mode: .panel)
        window.ignoresMouseEvents = false
        onModeChanged?(.panel)

        if let screen = targetScreen() ?? NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                // Slightly above centre reads as deliberate placement; dead
                // centre looks like it was dropped there.
                y: visible.midY - size.height / 2 + visible.height * 0.06
            )
            window.setFrame(
                NSRect(origin: origin, size: size),
                display: true,
                animate: false
            )
        }

        window.isPresentationAllowed = true
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        guard window.mode == .panel else { return }
        window.orderOut(nil)
        window.isPresentationAllowed = false
    }

    // MARK: - Hover

    private func installMonitors() {
        removeMonitors()

        // Two monitors are needed because each sees only half the picture: the
        // global one fires while another app is active, the local one while
        // this app is. Between them the pointer is tracked everywhere.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.evaluateHover(at: NSEvent.mouseLocation)
            _ = event
        }) {
            moveMonitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.evaluateHover(at: NSEvent.mouseLocation)
            return event
        }) {
            moveMonitors.append(local)
        }
    }

    private func removeMonitors() {
        for monitor in moveMonitors {
            NSEvent.removeMonitor(monitor)
        }
        moveMonitors.removeAll()
        cancelPendingCollapse()
    }

    /// Decides whether the pointer counts as being over the widget.
    ///
    /// The hot zone is the visible card, not the window: while collapsed the
    /// window is far larger than the pill, and treating the whole frame as a
    /// target would expand the rail from most of the way across the screen.
    private func evaluateHover(at location: NSPoint) {
        guard isRailVisible, window.mode == .rail, !isPinnedOpen else { return }

        let inside = hotZoneOnScreen().contains(location)

        if inside {
            cancelPendingCollapse()
            if !isExpanded {
                setExpanded(true, notify: true)
            }
        } else if isExpanded {
            scheduleCollapse()
        }
    }

    private func hotZoneOnScreen() -> NSRect {
        let frame = window.frame
        let size = frame.size

        // Two very different targets. At rest it is the sliver, so brushing
        // past the edge does not open anything. Once open it is the rail plus
        // its card, so moving the pointer onto the card never collapses the
        // rail out from under it.
        let local = isExpanded
            ? RailMetrics.openHotZone(in: size, edge: edge)
            : RailMetrics.restingHotZone(in: size, edge: edge)

        return local.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    private func scheduleCollapse() {
        guard collapseWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWorkItem = nil
            // Re-check rather than trusting the reading that scheduled this:
            // the pointer may have come back during the grace period.
            if !self.hotZoneOnScreen().contains(NSEvent.mouseLocation) {
                self.setExpanded(false, notify: true)
            }
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + RailWindowController.collapseGrace,
            execute: item
        )
    }

    private func cancelPendingCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    /// - Parameter force: apply the state even if it matches, which the first
    ///   call after showing the rail needs — `isExpanded` starts false and the
    ///   window's mouse-event setting has not been established yet.
    private func setExpanded(_ expanded: Bool, notify: Bool, force: Bool = false) {
        guard force || expanded != isExpanded else { return }
        let changed = expanded != isExpanded
        isExpanded = expanded

        // The frost is sized to the *open* rail. While collapsed, Flutter draws
        // only the nub, so leaving the material up put a full-height pane of
        // blurred desktop against the bezel with nothing drawn on it.
        glass.setVisible(expanded && isRailVisible)

        // Give the transparent part of the window back to whatever is beneath
        // it while collapsed, so the widget never eats a click meant for the
        // editor behind it.
        window.ignoresMouseEvents = !expanded

        if notify && (changed || force) {
            onExpansionChanged?(expanded)
        }
    }
}

extension NSScreen {
    /// Stable identifier for this display, used to remember which monitor the
    /// user put the rail on.
    var railIdentifier: String? {
        guard let number = deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return nil
        }
        return number.stringValue
    }

    /// Name shown in the monitor picker.
    var railDisplayName: String {
        if #available(macOS 10.15, *) {
            return localizedName
        }
        return "Display \(railIdentifier ?? "?")"
    }
}
