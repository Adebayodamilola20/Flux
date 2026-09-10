import SwiftUI

/// The material the expanded notch, tooltip and settings orb are painted with.
///
/// Raw values are persistence keys, not display copy: keeping them stable lets
/// labels change without losing an existing choice. The default is `.glass`
/// because an "on by default" choice must not depend on the user having opened
/// Settings.
enum NotchSurfaceStyle: String, CaseIterable, Identifiable {
    case glass
    case solid
    case light

    var id: String { rawValue }

    /// Whether this Mac has a Liquid Glass to hand the surface to at all.
    ///
    /// DevNotch's deployment target is macOS 15, where `glassEffect` does not
    /// exist. A material is not a stand-in: the notch panel sits over the bezel
    /// with nothing behind it to blur, so a `.regular` material there would
    /// come out as a flat grey rectangle rather than as translucency.
    static var glassAvailable: Bool {
        if #available(macOS 26.0, *) { return true } else { return false }
    }

    /// The style that actually gets painted, which is the chosen one only where
    /// it can be. Every glass branch keys off this rather than off `self`, so a
    /// preference set on a newer Mac (or restored from one) still draws
    /// something sensible on an older one instead of drawing nothing.
    var effective: NotchSurfaceStyle {
        switch self {
        // Glass needs macOS 26; everything else draws anywhere.
        case .glass: return Self.glassAvailable ? .glass : .solid
        case .solid, .light: return self
        }
    }

    /// Whether this style paints an opaque surface of its own.
    var isOpaque: Bool { effective != .glass }

    /// The colour this style paints its surface with.
    ///
    /// Stated outright rather than resolved from a dynamic `NSColor`. A
    /// dynamic one answers to whatever appearance is in force where it is
    /// drawn, which is the panel's in the running app but *light* anywhere
    /// there is no panel — an offscreen render, a snapshot test. That turned
    /// the black band across a MacBook's camera housing white, which is the
    /// one place on the whole surface that must never be anything but black.
    var surfaceColor: Color {
        effective == .light ? .white : .black
    }

    /// The styles worth putting in front of someone on this Mac.
    ///
    /// Glass is dropped where it cannot be drawn rather than offered and
    /// silently downgraded, which would be a control that appears to do
    /// nothing.
    static var offered: [NotchSurfaceStyle] {
        allCases.filter { $0 != .glass || glassAvailable }
    }

    var title: String {
        switch self {
        case .glass: return L10n.t("Liquid Glass")
        case .solid: return L10n.t("Solid black")
        case .light: return L10n.t("Solid white")
        }
    }

    var explanation: String {
        switch self {
        case .glass:
            return L10n.t("System Liquid Glass. Follows this Mac's Appearance settings, including Clear or Tinted glass and light or dark mode.")
        case .solid:
            return L10n.t("The original opaque black notch. Always dark, whatever the Mac's appearance.")
        case .light:
            return L10n.t("An opaque white notch, with dark text and rings. Always light, whatever the Mac's appearance.")
        }
    }

    /// One window-level switch decides both halves of "how dark is this notch":
    /// the dynamic `NSColor`s in `Palette` and SwiftUI's `colorScheme` are both
    /// resolved against the window's appearance, so pinning it here saves
    /// threading a style through every view that picks a colour.
    ///
    /// `nil` is not a fallback — it is the whole point of the glass style. With
    /// no appearance of our own, light or dark, Clear or Tinted all arrive from
    /// the Mac's Appearance settings; naming one would quietly overrule the
    /// user there.
    ///
    /// Reduce transparency is the exception the window has to be told about:
    /// it means "no see-through chrome", which for the notch is the solid
    /// style, and a light palette on a black surface would be unreadable. The
    /// precedence is the Settings window's — reduce transparency first, then
    /// glass, then the opaque fill.
    func panelAppearance(reduceTransparency: Bool) -> NSAppearance? {
        // Light is the one style that names a light appearance, and it names
        // it even under reduce transparency: that setting means "no
        // see-through chrome", which the white surface already satisfies.
        // Forcing dark there would hand back a black notch to someone who
        // explicitly asked for a white one.
        if effective == .light { return NSAppearance(named: .aqua) }
        return effective == .glass && !reduceTransparency ? nil : NSAppearance(named: .darkAqua)
    }
}

private struct NotchSurfaceStyleKey: EnvironmentKey {
    static let defaultValue = NotchSurfaceStyle.glass
}

extension EnvironmentValues {
    var notchSurfaceStyle: NotchSurfaceStyle {
        get { self[NotchSurfaceStyleKey.self] }
        set { self[NotchSurfaceStyleKey.self] = newValue }
    }
}
