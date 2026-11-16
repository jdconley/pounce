import Foundation
import Security

/// One generic-password item in the data-protection keychain, readable after first unlock on
/// this device only: never synced to iCloud, never restored to another device. Every call is
/// `@concurrent`: the Keychain is IO, and can block for a long time while the device is busy.
public struct KeychainItem: Sendable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    @concurrent
    public func load() async -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Adds or replaces the item. False when the Keychain refused (an unsigned test host).
    @discardableResult
    @concurrent
    public func save(_ data: Data) async -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query.merging(attributes) { $1 }
            add[kSecAttrSynchronizable as String] = false
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @concurrent
    public func delete() async {
        SecItemDelete(query as CFDictionary)
    }
}
