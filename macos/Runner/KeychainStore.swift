import Foundation
import Security

/// Thin wrapper over the macOS Keychain for the app's optional API credentials.
///
/// Secrets never touch `UserDefaults`, never appear in a log, and are never
/// returned to Flutter except when explicitly read for an outbound request.
/// Items are stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so
/// they are not synced to iCloud and are unavailable before first unlock.
enum KeychainStore {

    private static let service = "com.aiusagemonitor.credentials"

    /// Reads a secret, or nil when the item does not exist.
    static func read(key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    /// Creates or replaces a secret. Returns false when the Keychain refuses.
    @discardableResult
    static func write(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        var insert = query
        insert.merge(attributes) { current, _ in current }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    /// Removes a secret. Succeeds when the item is already absent.
    @discardableResult
    static func delete(key: String) -> Bool {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
