import Cocoa

/// Owns the menu-bar item: its drawn icon, its percentage label, and the
/// click handling that toggles the popover.
///
/// The icon is drawn from primitives as a template image so macOS tints it for
/// light and dark menu bars automatically, and no artwork is bundled.
final class StatusItemController {

    // MARK: - Callbacks

    /// Left-click on the status item, or "Show Rail" from the menu.
    var onToggleRail: (() -> Void)?
    /// "Refresh Now" chosen from the context menu.
    var onRefresh: (() -> Void)?
    /// "Settings…" chosen from the context menu.
    var onSettings: (() -> Void)?

    // MARK: - State

    private let statusItem: NSStatusItem
    private var showIcon = true
    private var showPercent = true
    private var percent: Int?
    private var isError = false

    /// Screen-space centre of the status item, used to anchor the popover.
    var anchorPoint: NSPoint? {
        guard let button = statusItem.button, let window = button.window else {
            return nil
        }
        let rect = button.convert(button.bounds, to: nil)
        let onScreen = window.convertToScreen(rect)
        return NSPoint(x: onScreen.midX, y: onScreen.minY)
    }

    // MARK: - Lifecycle

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        render()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel("AI Usage Monitor")
    }

    // MARK: - Public API

    /// Updates the menu-bar presentation. Called from the Flutter side whenever
    /// usage or the relevant preferences change.
    func update(showIcon: Bool, showPercent: Bool, percent: Int?, isError: Bool) {
        self.showIcon = showIcon
        self.showPercent = showPercent
        self.percent = percent
        self.isError = isError
        render()
    }

    /// Reflects whether the popover is currently visible.
    func setHighlighted(_ highlighted: Bool) {
        statusItem.button?.highlight(highlighted)
    }

    // MARK: - Rendering

    private func render() {
        guard let button = statusItem.button else { return }

        button.image = showIcon ? StatusItemController.sparkImage() : nil

        if showPercent {
            let text: String
            if isError {
                // An error must never leave a stale number in the menu bar.
                text = "!"
            } else if let percent {
                text = "\(percent)%"
            } else {
                text = "–"
            }

            let font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button.attributedTitle = NSAttributedString(
                string: showIcon ? " \(text)" : text,
                attributes: [
                    .font: font,
                    .baselineOffset: 0.5,
                ]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }

        let spoken = percent.map { "\($0) percent used" } ?? "usage unknown"
        button.setAccessibilityLabel("AI Usage Monitor, \(spoken)")
    }

    /// An eight-point sparkle, drawn to match the mark used inside the popover.
    private static func sparkImage() -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let outer = min(rect.width, rect.height) / 2 - 0.5
            let hub = outer * 0.26
            let points = 8
            let path = NSBezierPath()

            for index in 0..<points {
                let angle = (2 * CGFloat.pi / CGFloat(points)) * CGFloat(index) - .pi / 2
                let spread = CGFloat.pi / CGFloat(points) * 0.5

                let tip = NSPoint(
                    x: center.x + cos(angle) * outer,
                    y: center.y + sin(angle) * outer
                )
                let left = NSPoint(
                    x: center.x + cos(angle - spread) * hub,
                    y: center.y + sin(angle - spread) * hub
                )
                let right = NSPoint(
                    x: center.x + cos(angle + spread) * hub,
                    y: center.y + sin(angle + spread) * hub
                )
                let control = NSPoint(
                    x: center.x + cos(angle) * hub * 1.6,
                    y: center.y + sin(angle) * hub * 1.6
                )

                path.move(to: left)
                path.curve(to: tip, controlPoint1: control, controlPoint2: control)
                path.curve(to: right, controlPoint1: control, controlPoint2: control)
                path.close()
            }

            path.appendOval(in: NSRect(
                x: center.x - hub * 0.9,
                y: center.y - hub * 0.9,
                width: hub * 1.8,
                height: hub * 1.8
            ))

            NSColor.black.setFill()
            path.fill()
            return true
        }
        // Template rendering lets AppKit tint the icon for the current menu bar
        // appearance, including "Reduce transparency" and accent-colour modes.
        image.isTemplate = true
        return image
    }

    // MARK: - Interaction

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onToggleRail?()
            return
        }

        let isSecondary = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)

        if isSecondary {
            showContextMenu()
        } else {
            onToggleRail?()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Show/Hide Rail",
            action: #selector(menuToggleRail),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let refresh = NSMenuItem(
            title: "Refresh Now",
            action: #selector(menuRefresh),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(menuSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit AI Usage Monitor",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        // Attaching the menu only for this click keeps left-click free to
        // toggle the popover rather than always opening the menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuToggleRail() { onToggleRail?() }
    @objc private func menuRefresh() { onRefresh?() }
    @objc private func menuSettings() { onSettings?() }
}
