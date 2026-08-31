import Cocoa

/// Frosted material behind the rail.
///
/// **Why this cannot be done in Flutter.** The obvious approach is a
/// `BackdropFilter`, but that blurs what is behind it *within the Flutter layer
/// tree*. The rail window is transparent and there is nothing behind the rail
/// inside Flutter — the desktop is behind the *window*. Blurring it needs
/// AppKit, which is what `NSVisualEffectView` with `.behindWindow` blending
/// does: the compositor samples what the window is sitting on top of.
///
/// The view is placed under the Flutter view and sized to exactly the rail's
/// drawn rectangle, then masked to the same outline Flutter draws. Anything
/// larger would frost the transparent part of the window, which is most of it —
/// a blurred rectangle hanging in the middle of the screen.
final class RailGlass {

    /// Matches `NotchShape.cornerRadius` in Dart. The two shapes have to agree
    /// or the frost shows outside the card's edge.
    private static let cornerRadius: CGFloat = 20

    private let effect = NSVisualEffectView()

    private var isEnabled = false
    private var isVisible = false
    private var frame: NSRect = .zero
    private var onRightEdge = true

    init() {
        // `.behindWindow` is the blending mode that samples the desktop rather
        // than the window's own contents.
        effect.blendingMode = .behindWindow
        effect.material = .hudWindow
        // `.active` rather than `.followsWindowActiveState`: the rail is never
        // the key window, and a frost that greys out whenever the user is
        // working in their editor would be frosted approximately never.
        effect.state = .active
        effect.wantsLayer = true
        effect.isHidden = true
    }

    /// Inserts the material beneath the Flutter view.
    func attach(to contentView: NSView) {
        guard effect.superview == nil else { return }
        effect.autoresizingMask = []
        contentView.addSubview(effect, positioned: .below, relativeTo: nil)
    }

    /// Whether the user asked for glass at all.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        apply()
    }

    /// Whether the rail is currently drawn.
    ///
    /// Hidden while the rail is away so the frost does not sit on an empty
    /// screen edge, and hidden in panel mode where the panel draws its own
    /// background.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        apply()
    }

    /// Positions the material over the rail's drawn rectangle.
    func layout(windowSize: NSSize, edge: RailEdge, slots: Int) {
        onRightEdge = edge == .right
        frame = RailMetrics.railRect(in: windowSize, edge: edge, slots: slots)
        effect.frame = frame
        effect.maskImage = Self.mask(for: frame.size, onRightEdge: onRightEdge)
        apply()
    }

    private func apply() {
        effect.isHidden = !(isEnabled && isVisible) || frame.isEmpty
    }

    /// The rail's outline: rounded on the inward side, flat against the bezel.
    ///
    /// Drawn at the exact size rather than as a resizable nine-part image,
    /// because the two inward corners are rounded and the two outward ones are
    /// not — a symmetric cap-inset image cannot express that.
    private static func mask(for size: NSSize, onRightEdge: Bool) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        let radius = min(cornerRadius, min(size.width, size.height) / 2)

        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            let minX = rect.minX, maxX = rect.maxX
            let minY = rect.minY, maxY = rect.maxY

            if onRightEdge {
                // Flat right edge, rounded left.
                path.move(to: NSPoint(x: maxX, y: minY))
                path.line(to: NSPoint(x: minX + radius, y: minY))
                path.appendArc(
                    withCenter: NSPoint(x: minX + radius, y: minY + radius),
                    radius: radius,
                    startAngle: 270,
                    endAngle: 180,
                    clockwise: true
                )
                path.line(to: NSPoint(x: minX, y: maxY - radius))
                path.appendArc(
                    withCenter: NSPoint(x: minX + radius, y: maxY - radius),
                    radius: radius,
                    startAngle: 180,
                    endAngle: 90,
                    clockwise: true
                )
                path.line(to: NSPoint(x: maxX, y: maxY))
            } else {
                // Flat left edge, rounded right.
                path.move(to: NSPoint(x: minX, y: minY))
                path.line(to: NSPoint(x: maxX - radius, y: minY))
                path.appendArc(
                    withCenter: NSPoint(x: maxX - radius, y: minY + radius),
                    radius: radius,
                    startAngle: 270,
                    endAngle: 0,
                    clockwise: false
                )
                path.line(to: NSPoint(x: maxX, y: maxY - radius))
                path.appendArc(
                    withCenter: NSPoint(x: maxX - radius, y: maxY - radius),
                    radius: radius,
                    startAngle: 0,
                    endAngle: 90,
                    clockwise: false
                )
                path.line(to: NSPoint(x: minX, y: maxY))
            }

            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
    }
}
