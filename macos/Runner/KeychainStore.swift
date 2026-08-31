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

/// Reads the session Claude Code already holds, so this app can ask Anthropic
/// for the current usage figure instead of showing a cached one.
///
/// Claude Code used to keep its OAuth tokens in `~/.claude/.credentials.json`.
/// On macOS it now keeps them in the login Keychain, and leaves the old file
/// behind unmaintained — which is why reading that file yields a token that
/// expired months ago, and why usage read through it is always the stale copy
/// from `~/.claude.json` rather than the live number.
///
/// Deliberately narrow. This is not a general "read any Keychain item" call:
///
///  * the service name is a constant here, not a parameter, so nothing on the
///    Dart side can point it at another application's secrets,
///  * the token is used for exactly one request — Anthropic's own usage
///    endpoint — and is never written anywhere, logged, or persisted,
///  * it is only ever read, never updated or refreshed. Refreshing would
///    rotate the token and sign the user out of their own CLI.
///
/// macOS asks the user to approve the first read, because the item belongs to
/// another application. That prompt is the correct gate and this code does not
/// try to avoid it.
enum ClaudeCodeCredentials {

    /// The service name Claude Code files its credentials under.
    private static let service = "Claude Code-credentials"

    enum Outcome {
        /// The stored credential blob, verbatim JSON.
        case found(String)
        /// Claude Code has not signed in on this Mac.
        case absent
        /// The user declined the Keychain prompt, or macOS refused.
        case denied
    }

    /// Reads the credential blob.
    ///
    /// Blocks while the approval dialog is up, so callers must keep this off
    /// the main thread.
    static func read() -> Outcome {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        // Claude Code files the item under the macOS short user name. Trying
        // that first keeps the query specific; the service-only query is the
        // fallback so a differently-filed item is still found rather than
        // reported as "not signed in".
        var queries = [base]
        queries.insert(
            base.merging([kSecAttrAccount as String: NSUserName()]) { current, _ in current },
            at: 0
        )

        var lastStatus = errSecItemNotFound
        for query in queries {
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            lastStatus = status

            if status == errSecSuccess {
                guard let data = item as? Data,
                      let value = String(data: data, encoding: .utf8),
                      !value.isEmpty
                else {
                    return .absent
                }
                return .found(value)
            }
            // Only a genuine miss is worth retrying with a wider query. A
            // refusal will refuse again, and asking twice means two dialogs.
            if status != errSecItemNotFound { break }
        }

        // errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed all
        // mean the same thing to the caller: no token this time, so fall back
        // to the cached figures rather than failing the refresh outright.
        return lastStatus == errSecItemNotFound ? .absent : .denied
    }

    /// When the stored credential was last written, or nil when there is none.
    ///
    /// This is the signal that the user signed in again — `claude /login`
    /// replaces the item, and its modification date moves. Without it the app
    /// keeps using a token it read before the switch, which is still valid and
    /// still answers for the *previous* account, so the rail goes on reporting
    /// an account the user has left.
    ///
    /// **This does not raise the approval dialog.** The Keychain ACL guards an
    /// item's *data*, not its attributes, so a query that asks for attributes
    /// and explicitly declines the data is answered without prompting. That is
    /// what makes it safe to call on every poll: it costs no dialog and reads
    /// no secret. Only when the date has moved is the guarded read done again.
    static func modifiedAt() -> Date? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            // Stated rather than merely omitted: asking for the data is what
            // would turn this into a prompt.
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var queries = [base]
        queries.insert(
            base.merging([kSecAttrAccount as String: NSUserName()]) { current, _ in current },
            at: 0
        )

        for query in queries {
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let attributes = item as? [String: Any]
            else {
                continue
            }
            if let modified = attributes[kSecAttrModificationDate as String] as? Date {
                return modified
            }
            // The item exists but reports no modification date. Its creation
            // date still moves when the item is replaced, so it answers the
            // same question.
            if let created = attributes[kSecAttrCreationDate as String] as? Date {
                return created
            }
        }

        return nil
    }
}
