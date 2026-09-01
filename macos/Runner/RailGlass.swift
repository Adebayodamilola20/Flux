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

    /// Both must match the values `RailColumn` passes to `NotchShape` in Dart.
    /// The frost is drawn behind that outline, so any disagreement shows as a
    /// second, differently-shaped panel sitting behind the rail.
    private static let cornerRadius: CGFloat = 20
    private static let filletRadius: CGFloat = 13

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

    /// The rail's outline, as a mask image.
    ///
    /// Drawn at the exact size rather than as a resizable nine-part image: the
    /// two inward corners are rounded, the two outward ones are not, and the
    /// outline curves *back* into the screen edge at top and bottom. A
    /// symmetric cap-inset image cannot express any of that.
    private static func mask(for size: NSSize, onRightEdge: Bool) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        return NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            context.addPath(notchPath(in: rect, onRightEdge: onRightEdge))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
    }

    /// A direct port of `NotchPathBuilder.build` in `rail_shapes.dart`.
    ///
    /// Kept structurally identical to the Dart — same clamps, same order, same
    /// control points — because the two are drawn on top of each other and the
    /// difference between this and a rounded rectangle is the entire design.
    /// The shape is symmetric about its horizontal axis, so it needs no
    /// adjustment for AppKit's upward Y.
    private static func notchPath(in rect: NSRect, onRightEdge: Bool) -> CGPath {
        let w = rect.width
        let h = rect.height

        // The reverse curves eat into the top and bottom, so they cannot be
        // larger than half the height, and the inward corners cannot exceed
        // what is left.
        let f = min(max(filletRadius, 0), h / 2)
        let r = min(max(cornerRadius, 0), (h - f * 2) / 2)

        let path = CGMutablePath()
        let x0 = rect.minX
        let y0 = rect.minY

        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: x0 + px, y: y0 + py)
        }

        if onRightEdge {
            path.move(to: point(w, 0))
            // Reverse curve: leaves the screen edge and sweeps inward.
            path.addQuadCurve(to: point(w - f, f), control: point(w, f))
            path.addLine(to: point(r, f))
            path.addQuadCurve(to: point(0, f + r), control: point(0, f))
            path.addLine(to: point(0, h - f - r))
            path.addQuadCurve(to: point(r, h - f), control: point(0, h - f))
            path.addLine(to: point(w - f, h - f))
            // Reverse curve back out to the screen edge.
            path.addQuadCurve(to: point(w, h), control: point(w, h - f))
        } else {
            path.move(to: point(0, 0))
            path.addQuadCurve(to: point(f, f), control: point(0, f))
            path.addLine(to: point(w - r, f))
            path.addQuadCurve(to: point(w, f + r), control: point(w, f))
            path.addLine(to: point(w, h - f - r))
            path.addQuadCurve(to: point(w - r, h - f), control: point(w, h - f))
            path.addLine(to: point(f, h - f))
            path.addQuadCurve(to: point(0, h), control: point(0, h - f))
        }

        path.closeSubpath()
        return path
    }
}
