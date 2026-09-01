import Cocoa
import FlutterMacOS

/// The app's only window, repurposed as the edge rail and the setup panel.
///
/// Flutter's template creates this from the storyboard and expects to own the
/// `FlutterViewController`; we keep that arrangement and change the window's
/// behaviour rather than re-parenting the view controller at runtime.
class MainFlutterWindow: RailWindow {

    /// Number of provider slots the rail is laid out for. Mirrors
    /// `ProviderCatalog.slotCount` in Dart; the registry asserts the Dart side
    /// matches, and the rail's height is derived from it here.
    static let slotCount = 3

    private var statusItemController: StatusItemController?
    private var railController: RailWindowController?
    private(set) var nativeChannel: NativeChannel?

    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        contentViewController = flutterViewController
        RegisterGeneratedPlugins(registry: flutterViewController)

        // The Flutter view must be transparent so only the drawn card shows.
        flutterViewController.backgroundColor = .clear

        let rail = RailWindowController(
            window: self,
            slotCount: MainFlutterWindow.slotCount
        )
        let statusItem = StatusItemController()
        let channel = NativeChannel(
            messenger: flutterViewController.engine.binaryMessenger,
            statusItem: statusItem,
            rail: rail,
            slotCount: MainFlutterWindow.slotCount
        )

        statusItem.onRevealRail = { [weak channel] in
            channel?.requestRevealRail()
        }
        statusItem.onToggleRail = { [weak channel] in
            channel?.requestToggleRail()
        }
        statusItem.onRefresh = { [weak channel] in
            channel?.requestRefresh()
        }
        statusItem.onSettings = { [weak channel] in
            channel?.requestSettings()
        }

        self.statusItemController = statusItem
        self.railController = rail
        self.nativeChannel = channel

        // Present the rail immediately, before Dart has said anything.
        //
        // The Flutter view only loads once its window is displayed, and the
        // engine only starts once the view loads. Waiting for Dart to choose a
        // surface would deadlock: Dart cannot run until a window is on screen,
        // and no window would be on screen until Dart ran.
        //
        // The rail is the right thing to show anyway — it is the primary
        // interface, and its defaults (right edge, vertically centred) are what
        // Dart will confirm a moment later. On first launch Dart swaps to the
        // connect screen once it has read the user's settings.
        rail.showRail(pinnedOpen: false)

        super.awakeFromNib()
    }
}
