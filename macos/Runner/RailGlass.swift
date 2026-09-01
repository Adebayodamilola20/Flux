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
        // `.fullScreenUI` rather than `.hudWindow`: the HUD material is close
        // to opaque once the theme wash is over it, which made the setting
        // produce a dark panel instead of glass. This one keeps far more of
        // what is behind the window, which is the point.
        effect.material = .fullScreenUI
        // Keeps the material at full strength even though the rail is never
        // the key window — otherwise the frost drops away the moment the user
        // clicks back into their editor, which is always.
        effect.isEmphasized = true
        // `.active` rather than `.followsWindowActiveState`: the rail is never
        // the key window, and a frost that greys out whenever the user is
        // working in their editor would be frosted approximately never.
        effect.state = .active
        effect.wantsLayer = true
        effect.isHidden = true
        effect.alphaValue = 0
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

    /// How long the frost takes to arrive and leave.
    ///
    /// These match `AppMetrics.expand` and `AppMetrics.collapse` in Dart. The
    /// frost and the rail drawn over it are one object to the eye, so if the
    /// material snaps while Flutter animates, the two separate: a coloured
    /// pane appears before the rail on the way in, and outstays it on the way
    /// out. Matching the curve and the duration is what keeps them together.
    private static let fadeIn: TimeInterval = 0.26
    private static let fadeOut: TimeInterval = 0.19

    /// How far the material starts outside its resting place, as a fraction of
    /// the rail's width.
    ///
    /// Matches the `FractionalTranslation` the open rail animates through in
    /// Dart. The rail does not fade in where it lands — it emerges from behind
    /// the bezel — so a frost that only fades is already sitting in place while
    /// the rail is still travelling, and reads as a coloured box arriving
    /// first. Travelling with it is what makes the two one object.
    private static let slideFraction: CGFloat = 0.6

    /// Flutter's `Curves.easeOutCubic` and `Curves.easeInCubic` as timing
    /// functions. The rail uses one in each direction; the frost has to use the
    /// same, or it drifts ahead mid-travel even with the durations matched.
    private static let easeOutCubic = CAMediaTimingFunction(
        controlPoints: 0.215, 0.61, 0.355, 1
    )
    private static let easeInCubic = CAMediaTimingFunction(
        controlPoints: 0.55, 0.055, 0.675, 0.19
    )

    /// Whether the rail is currently drawn.
    ///
    /// Hidden while the rail is away so the frost does not sit on an empty
    /// screen edge, and hidden in panel mode where the panel draws its own
    /// background.
    ///
    /// - Parameter animated: fade rather than snap. False for the structural
    ///   changes — the rail being hidden outright, or switching to panel mode —
    ///   where there is no Flutter animation to stay in step with.
    func setVisible(_ visible: Bool, animated: Bool = false) {
        guard visible != isVisible else { return }
        isVisible = visible
        apply(animated: animated)
    }

    /// Positions the material over the rail's drawn rectangle.
    func layout(windowSize: NSSize, edge: RailEdge, slots: Int) {
        onRightEdge = edge == .right
        frame = RailMetrics.railRect(in: windowSize, edge: edge, slots: slots)
        effect.frame = frame
        effect.maskImage = Self.mask(for: frame.size, onRightEdge: onRightEdge)
        apply()
    }

    private func apply(animated: Bool = false) {
        let shouldShow = isEnabled && isVisible && !frame.isEmpty

        guard animated else {
            effect.layer?.removeAllAnimations()
            effect.isHidden = !shouldShow
            effect.alphaValue = shouldShow ? 1 : 0
            effect.frame = shouldShow ? frame : offscreenFrame
            return
        }

        // Unhidden for the whole travel in both directions: a hidden view does
        // not animate, so hiding first would snap the frost away and animate
        // nothing.
        effect.isHidden = false

        // Set without animating, or the view would travel to the start before
        // travelling back in from it.
        if shouldShow {
            effect.frame = offscreenFrame
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = shouldShow ? Self.fadeIn : Self.fadeOut
            context.timingFunction = shouldShow
                ? Self.easeOutCubic
                : Self.easeInCubic
            effect.animator().alphaValue = shouldShow ? 1 : 0
            effect.animator().frame = shouldShow ? frame : offscreenFrame
        } completionHandler: { [weak self] in
            guard let self else { return }
            // Re-read rather than trusting the value captured when the travel
            // started: a hover that returns mid-animation will have shown it
            // again, and hiding here would undo that.
            let visibleNow = self.isEnabled && self.isVisible && !self.frame.isEmpty
            self.effect.isHidden = !visibleNow
        }
    }

    /// Where the material sits before it has travelled in, or after it leaves:
    /// pushed back behind the bezel by the same fraction the rail uses.
    private var offscreenFrame: NSRect {
        frame.offsetBy(
            dx: (onRightEdge ? 1 : -1) * frame.width * Self.slideFraction,
            dy: 0
        )
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
