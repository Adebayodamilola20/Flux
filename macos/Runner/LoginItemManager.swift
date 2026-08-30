import Foundation
import ServiceManagement

/// Registers the app as a macOS login item.
///
/// Uses `SMAppService`, the supported API since macOS 13. Registration is
/// reflected in System Settings → General → Login Items, so the user can revoke
/// it there; the app reconciles with the system state on every launch rather
/// than trusting its own stored preference.
enum LoginItemManager {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Applies the requested state. Returns the state actually in effect
    /// afterwards, which may differ if macOS refused or the user has the item
    /// disabled in System Settings.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                // Registering an already-enabled service throws; treat that as
                // success rather than surfacing a spurious failure.
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("[loginItem] request failed: \(error.localizedDescription)")
            return isEnabled
        }

        if service.status == .requiresApproval {
            // macOS needs the user to approve it in System Settings; report the
            // truth rather than claiming success.
            NSLog("[loginItem] awaiting user approval in System Settings")
            return false
        }

        return isEnabled
    }
}
