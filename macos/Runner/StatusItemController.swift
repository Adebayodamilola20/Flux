import Cocoa

/// Owns the menu-bar item: its drawn icon, its percentage label, and the
/// click handling that toggles the popover.
///
/// The icon is drawn from primitives as a template image so macOS tints it for
/// light and dark menu bars automatically, and no artwork is bundled.
final class StatusItemController {

    // MARK: - Callbacks

    /// Left-click on the status item.
    ///
    /// Deliberately not the same as [onToggleRail]. A click on the icon used to
    /// flip the rail's visibility *off* and persist it, so the rail vanished
    /// and stayed gone until the icon was found and clicked again — the icon is
    /// how you reach the app, not a switch that turns it off by surprise.
    var onRevealRail: (() -> Void)?

    /// "Show/Hide Rail" from the context menu, which is the explicit switch.
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

    /// Short name of the provider the figure belongs to, e.g. `Claude`.
    ///
    /// The menu bar cycles through everything on the rail, so a bare number
    /// would be ambiguous the moment there is more than one — 37% of what?
    private var label: String?

    /// Set while a changeover is animating, so the swap reads as a transition
    /// rather than a number that flickered.
    private var isFading = false

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
        button.setAccessibilityLabel("Side Notch")
    }

    // MARK: - Public API

    /// Updates the menu-bar presentation. Called from the Flutter side whenever
    /// usage or the relevant preferences change.
    func update(
        showIcon: Bool,
        showPercent: Bool,
        percent: Int?,
        isError: Bool,
        label: String?
    ) {
        // Only a change of *subject* is worth animating. Re-rendering the same
        // provider because its percentage ticked should not blink the menu bar.
        let changedSubject = showPercent
            && self.showPercent
            && label != nil
            && self.label != nil
            && label != self.label

        self.showIcon = showIcon
        self.showPercent = showPercent
        self.percent = percent
        self.isError = isError
        self.label = label

        if changedSubject {
            crossFade()
        } else {
            render()
        }
    }

    /// Dips the title out and back as the subject changes.
    ///
    /// AppKit gives a status item no transition of its own, so this is done by
    /// hand: a short fade on the button's layer, with the new text swapped in
    /// at the trough where it cannot be seen changing.
    private func crossFade() {
        guard let button = statusItem.button else {
            render()
            return
        }
        guard !isFading else {
            render()
            return
        }
        isFading = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            button.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.render()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                button.animator().alphaValue = 1
            }, completionHandler: {
                self.isFading = false
            })
        })
    }

    /// Reflects whether the popover is currently visible.
    func setHighlighted(_ highlighted: Bool) {
        statusItem.button?.highlight(highlighted)
    }

    // MARK: - Rendering

    private func render() {
        guard let button = statusItem.button else { return }

        button.image = showIcon ? StatusItemController.notchImage() : nil

        if showPercent {
            var text: String
            if isError {
                // An error must never leave a stale number in the menu bar.
                text = "!"
            } else if let percent {
                text = "\(percent)%"
            } else {
                text = "–"
            }

            // Named, because the figure rotates: without this the user sees a
            // number change and cannot tell whether their usage moved or the
            // menu bar simply moved on to the next app.
            if let label, !label.isEmpty, !isError {
                text = "\(label) \(text)"
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

        let subject = label ?? "usage"
        let spoken = percent.map { "\(subject) \($0) percent used" }
            ?? "\(subject) unknown"
        button.setAccessibilityLabel("Side Notch, \(spoken)")
    }

    /// The product's own mark: the rail itself, seen edge-on.
    ///
    /// A dot said nothing — it was indistinguishable from every other status
    /// item, and named nothing. This is the silhouette the app actually draws
    /// on screen: a tab standing against the right edge, flat on the bezel
    /// side, rounded inward, with the two reverse curves that make it read as
    /// part of the display rather than a floating box. Whatever the menu bar
    /// shows should be the thing the user is about to see.
    private static func notchImage() -> NSImage {
        let size = NSSize(width: 13, height: 15)
        let image = NSImage(size: size, flipped: false) { rect in
            // The bar the notch grows out of, hard against the trailing edge.
            let edge = NSBezierPath(rect: NSRect(
                x: rect.maxX - 1.5,
                y: rect.minY,
                width: 1.5,
                height: rect.height
            ))

            // The tab, in the same proportions as the real one.
            let tab = NSRect(
                x: rect.minX + 1,
                y: rect.minY + 2.5,
                width: rect.width - 3.5,
                height: rect.height - 5
            )
            let radius: CGFloat = 3

            let path = NSBezierPath()
            path.move(to: NSPoint(x: tab.maxX, y: tab.minY))
            path.line(to: NSPoint(x: tab.minX + radius, y: tab.minY))
            path.appendArc(
                withCenter: NSPoint(x: tab.minX + radius, y: tab.minY + radius),
                radius: radius,
                startAngle: 270,
                endAngle: 180,
                clockwise: true
            )
            path.line(to: NSPoint(x: tab.minX, y: tab.maxY - radius))
            path.appendArc(
                withCenter: NSPoint(x: tab.minX + radius, y: tab.maxY - radius),
                radius: radius,
                startAngle: 180,
                endAngle: 90,
                clockwise: true
            )
            path.line(to: NSPoint(x: tab.maxX, y: tab.maxY))
            path.close()

            NSColor.black.setFill()
            path.fill()
            edge.fill()
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
            onRevealRail?()
            return
        }

        let isSecondary = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)

        if isSecondary {
            showContextMenu()
        } else {
            onRevealRail?()
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
            title: "Quit Side Notch",
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
