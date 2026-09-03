import Cocoa

/// What the single Flutter-hosting window is currently being used for.
///
/// Flutter owns one `FlutterViewController`, and a view can live in only one
/// window, so the app has exactly one window and changes its behaviour instead
/// of creating a second one. The two modes want opposite things — the rail must
/// never take focus, the setup panel must — so the differences are concentrated
/// here rather than scattered through the controller.
enum RailMode {
    /// The edge widget: borderless, non-activating, floating above normal
    /// windows, positioned against a screen edge.
    case rail

    /// The setup and settings surface: a centred, focusable window the user can
    /// type into.
    case panel
}

/// The app's only window.
///
/// Not final: the storyboard instantiates `MainFlutterWindow`, which subclasses
/// this to install the Flutter view controller.
class RailWindow: NSPanel {

    private(set) var mode: RailMode = .rail

    /// The rail must be able to become key so clicks inside it reach Flutter,
    /// but `.nonactivatingPanel` keeps that from pulling the whole app — and
    /// the user's focus — away from whatever they were doing.
    override var canBecomeKey: Bool { true }

    /// Keeps the frame exactly where it was put.
    ///
    /// AppKit otherwise pulls a window back inside the screen's usable area,
    /// which for a rail hanging off the top edge means dropping it below the
    /// menu bar — the position that made it look like a panel floating in the
    /// content area rather than a notch growing out of the bezel. The rail
    /// window is borderless and positioned deliberately, so there is nothing
    /// here for that rule to protect.
    override func constrainFrameRect(
        _ frameRect: NSRect,
        to screen: NSScreen?
    ) -> NSRect {
        mode == .rail ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    /// Only the setup panel is a "main" window. Letting the rail claim that
    /// would make macOS treat a passive widget as the user's current document.
    override var canBecomeMain: Bool { mode == .panel }

    /// Gate on presentation, owned by `RailWindowController`.
    ///
    /// The storyboard's window controller shows this window at launch, and
    /// `flutter run` foregrounds the app on attach. Either path would order the
    /// window front at its unpositioned default frame before the controller has
    /// placed it. Refusing to be presented unless the controller says so makes
    /// the widget impossible to show in the wrong place.
    var isPresentationAllowed = false

    override func makeKeyAndOrderFront(_ sender: Any?) {
        guard isPresentationAllowed else {
            orderOut(nil)
            return
        }
        super.makeKeyAndOrderFront(sender)
    }

    override func orderFront(_ sender: Any?) {
        guard isPresentationAllowed else {
            orderOut(nil)
            return
        }
        super.orderFront(sender)
    }

    override func setIsVisible(_ visible: Bool) {
        guard visible == false || isPresentationAllowed else { return }
        super.setIsVisible(visible)
    }

    // MARK: - Modes

    func configureCommon() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false            // The card paints its own shadow.
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Flutter decides which ring the pointer is on, and it needs the moves
        // to do it. Off by default, and without it the rail opens but the card
        // never follows the pointer between rings.
        acceptsMouseMovedEvents = true
    }

    func apply(mode newMode: RailMode) {
        mode = newMode

        switch newMode {
        case .rail:
            // `.nonactivatingPanel` is what makes this feel like a system
            // widget rather than an app window: interacting with it never
            // pulls the user out of their editor.
            styleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
            level = .floating
            isMovable = false
            isMovableByWindowBackground = false
            hidesOnDeactivate = false
            animationBehavior = .none

            // Follow the user to whichever Space and full-screen app is
            // active, and stay put when Spaces change.
            collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]

        case .panel:
            // Focusable, so the key field in the connect flow can be typed
            // into, and draggable by its background since it has no title bar.
            styleMask = [.borderless, .fullSizeContentView, .resizable]
            level = .normal
            isMovable = true
            isMovableByWindowBackground = true
            hidesOnDeactivate = false
            animationBehavior = .documentWindow
            collectionBehavior = [.fullScreenAuxiliary]
        }
    }
}
