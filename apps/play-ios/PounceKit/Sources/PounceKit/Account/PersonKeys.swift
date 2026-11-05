import Foundation
import Security
import Synchronization

/// A person's key (spec §13.1, the `device` provider): 32 random bytes, base64url. It proves a
/// person id is this device's, since ids are visible at a table. The server keeps only its hash.
public enum PersonKeys {
    public static func random() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max, using: &rng) }
        }
        return Base64URL.encode(Data(bytes))
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Person keys by person id. `key(for:)` makes one the first time it is asked.
public protocol PersonKeyStore: Sendable {
    func key(for personId: String) -> String
    func remove(_ personId: String)
}

public final class MemoryPersonKeyStore: PersonKeyStore {
    private let keys = Mutex<[String: String]>([:])

    public init() {}

    public func key(for personId: String) -> String {
        keys.withLock { all in
            if let key = all[personId] { return key }
            let key = PersonKeys.random()
            all[personId] = key
            return key
        }
    }

    public func remove(_ personId: String) { keys.withLock { _ = $0.removeValue(forKey: personId) } }
}

/// One generic-password item in the data-protection keychain, readable after first unlock on
/// this device only: never synced to iCloud, never restored to another device.
struct KeychainItem: Sendable {
    let service: String
    let account: String

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func load() -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    func save(_ data: Data) -> Bool {
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

    func delete() { SecItemDelete(query as CFDictionary) }
}

/// Person keys in the Keychain, one item per person id. A key the Keychain refuses to keep (an
/// unsigned test host) is still returned, and remembered for this process only.
public final class KeychainPersonKeyStore: PersonKeyStore {
    public static let defaultService = "com.conleychaos.play.person"
    private let service: String
    private let fallback = MemoryPersonKeyStore()

    public init(service: String = KeychainPersonKeyStore.defaultService) {
        self.service = service
    }

    public func key(for personId: String) -> String {
        let item = KeychainItem(service: service, account: personId)
        if let data = item.load(), let key = String(data: data, encoding: .utf8) { return key }
        let key = fallback.key(for: personId)
        item.save(Data(key.utf8))
        return key
    }

    public func remove(_ personId: String) {
        KeychainItem(service: service, account: personId).delete()
        fallback.remove(personId)
    }

    /// The Keychain accepted a write here (false on an unsigned test host).
    static func isUsable(_ store: KeychainPersonKeyStore) -> Bool {
        let probe = KeychainItem(service: store.service, account: "probe-\(UUID().uuidString)")
        defer { probe.delete() }
        return probe.save(Data("x".utf8)) && probe.load() != nil
    }
}
