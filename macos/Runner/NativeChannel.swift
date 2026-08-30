import Cocoa
import FlutterMacOS

/// The single method channel between Flutter and AppKit.
///
/// Deliberately thin: it validates arguments, dispatches to the focused helper
/// types, and replies. All policy lives in Dart; all macOS API use lives in the
/// helpers. Long-running work is moved off the main thread so the UI never
/// stalls waiting on a scan.
final class NativeChannel {

    static let name = "com.aiusagemonitor/native"

    private let channel: FlutterMethodChannel
    private let statusItem: StatusItemController
    private let rail: RailWindowController
    private let slotCount: Int

    init(
        messenger: FlutterBinaryMessenger,
        statusItem: StatusItemController,
        rail: RailWindowController,
        slotCount: Int
    ) {
        self.channel = FlutterMethodChannel(
            name: NativeChannel.name,
            binaryMessenger: messenger
        )
        self.statusItem = statusItem
        self.rail = rail
        self.slotCount = slotCount

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }

        rail.onExpansionChanged = { [weak self] expanded in
            self?.channel.invokeMethod(
                "rail.expansionChanged",
                arguments: ["expanded": expanded]
            )
        }

        rail.onModeChanged = { [weak self] mode in
            self?.channel.invokeMethod(
                "window.modeChanged",
                arguments: ["mode": mode == .rail ? "rail" : "panel"]
            )
        }
    }

    // MARK: - Native-initiated messages

    func requestRefresh() {
        channel.invokeMethod("refreshRequested", arguments: nil)
    }

    func requestSettings() {
        channel.invokeMethod("settingsRequested", arguments: nil)
    }

    func requestToggleRail() {
        channel.invokeMethod("railToggleRequested", arguments: nil)
    }

    /// Delivers a URL-scheme callback from a provider's browser sign-in.
    func deliverAuthCallback(url: URL) {
        channel.invokeMethod("auth.callback", arguments: ["url": url.absoluteString])
    }

    // MARK: - Dispatch

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {

        // MARK: Rail

        case "rail.metrics":
            result(RailMetrics.channelPayload(slots: slotCount))

        case "rail.configure":
            rail.configure(
                edge: RailEdge(name: args["edge"] as? String),
                offsetFraction: CGFloat(args["offset"] as? Double ?? 0.5),
                screenId: args["screenId"] as? String
            )
            result(nil)

        case "rail.show":
            rail.showRail(pinnedOpen: args["pinnedOpen"] as? Bool ?? false)
            result(nil)

        case "rail.hide":
            rail.hideRail()
            result(nil)

        case "rail.setPinnedOpen":
            rail.setPinnedOpen(args["pinned"] as? Bool ?? false)
            result(nil)

        case "rail.expand":
            rail.expandNow()
            result(nil)

        // MARK: Setup panel

        case "panel.show":
            rail.showPanel(size: NSSize(
                width: args["width"] as? Double ?? 760,
                height: args["height"] as? Double ?? 580
            ))
            result(nil)

        case "panel.hide":
            rail.hidePanel()
            result(nil)

        // MARK: Screens

        case "screens.list":
            let screens = NSScreen.screens.compactMap { screen -> [String: Any]? in
                guard let id = screen.railIdentifier else { return nil }
                return [
                    "id": id,
                    "name": screen.railDisplayName,
                    "isPrimary": screen == NSScreen.screens.first,
                    "width": Double(screen.frame.width),
                    "height": Double(screen.frame.height),
                ]
            }
            result(screens)

        // MARK: Menu bar

        case "menuBar.update":
            statusItem.update(
                showIcon: args["showIcon"] as? Bool ?? true,
                showPercent: args["showPercent"] as? Bool ?? false,
                percent: args["percent"] as? Int,
                isError: args["isError"] as? Bool ?? false
            )
            result(nil)

        // MARK: System integration

        case "url.open":
            guard let raw = args["url"] as? String, let url = URL(string: raw) else {
                result(NativeChannel.badArguments("url"))
                return
            }
            // Only ever hand a URL to the user's default browser. The app never
            // renders a provider's sign-in page itself, so it can never see
            // what the user types into it.
            result(NSWorkspace.shared.open(url))

        case "loginItem.isEnabled":
            result(LoginItemManager.isEnabled)

        case "loginItem.setEnabled":
            guard let enabled = args["enabled"] as? Bool else {
                result(NativeChannel.badArguments("enabled"))
                return
            }
            result(LoginItemManager.setEnabled(enabled))

        case "keychain.read":
            guard let key = args["key"] as? String else {
                result(NativeChannel.badArguments("key"))
                return
            }
            result(KeychainStore.read(key: key))

        case "keychain.write":
            guard let key = args["key"] as? String else {
                result(NativeChannel.badArguments("key"))
                return
            }
            // A null value means "remove", so the Dart side has one call for
            // both storing and clearing a credential.
            if let value = args["value"] as? String, !value.isEmpty {
                result(KeychainStore.write(key: key, value: value))
            } else {
                result(KeychainStore.delete(key: key))
            }

        case "process.find":
            guard let names = args["names"] as? [String] else {
                result(NativeChannel.badArguments("names"))
                return
            }
            // Enumerating every pid is cheap but not free; keep it off the
            // main thread so the rail stays responsive.
            DispatchQueue.global(qos: .utility).async {
                let matches = ProcessScanner.find(names: names).map { match in
                    [
                        "pid": Int(match.pid),
                        "name": match.name,
                        "host": match.host as Any,
                        "startedAt": match.startedAt as Any,
                    ] as [String: Any]
                }
                DispatchQueue.main.async { result(matches) }
            }

        case "app.quit":
            result(nil)
            NSApp.terminate(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func badArguments(_ field: String) -> FlutterError {
        FlutterError(
            code: "bad_arguments",
            message: "Missing or invalid argument: \(field)",
            details: nil
        )
    }
}
