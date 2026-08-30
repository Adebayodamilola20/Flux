import Cocoa
import FlutterMacOS

/// A background agent: no Dock tile, no menu bar of its own, and no exit when
/// the window closes.
@main
class AppDelegate: FlutterAppDelegate {

    /// URL scheme registered in Info.plist, used to receive the callback at the
    /// end of a provider's browser sign-in.
    static let callbackScheme = "aiusagemonitor"

    override func applicationWillFinishLaunching(_ notification: Notification) {
        // Must be registered before the app finishes launching, or a URL that
        // launched the app is delivered before there is a handler for it.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        super.applicationWillFinishLaunching(notification)
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        // `.accessory` keeps the app out of the Dock and the app switcher while
        // still allowing it to activate and take key focus when the setup panel
        // opens — which the connect flow's text field needs.
        NSApp.setActivationPolicy(.accessory)
        super.applicationDidFinishLaunching(notification)
    }

    /// The rail is "closed" constantly; terminating with it would defeat the
    /// entire point of a background utility.
    override func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        return false
    }

    /// Relaunching from Finder or a login item should not force a window open;
    /// the rail and the status item are the entry points.
    override func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        return false
    }

    override func applicationSupportsSecureRestorableState(
        _ app: NSApplication
    ) -> Bool {
        return true
    }

    // MARK: - Authentication callbacks

    /// Receives `aiusagemonitor://…` URLs and hands them to Dart.
    ///
    /// This is the return leg of a browser-based sign-in: the provider redirects
    /// to our registered scheme, macOS routes it here, and the Dart side matches
    /// it to the flow that is waiting. Nothing is parsed in Swift beyond
    /// confirming it is a URL, so the provider-specific handling stays in one
    /// place.
    @objc private func handleURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent reply: NSAppleEventDescriptor
    ) {
        guard
            let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: raw),
            url.scheme == AppDelegate.callbackScheme
        else {
            return
        }

        let window = NSApp.windows.compactMap { $0 as? MainFlutterWindow }.first
        window?.nativeChannel?.deliverAuthCallback(url: url)
    }
}
