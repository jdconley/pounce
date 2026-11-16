import Foundation
import Security

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

/// Person keys by person id. `key(for:)` makes one the first time it is asked. Async: the real
/// store is the Keychain, which is IO.
public protocol PersonKeyStore: Sendable {
    func key(for personId: String) async -> String
    func remove(_ personId: String) async
}

public actor MemoryPersonKeyStore: PersonKeyStore {
    private var keys: [String: String] = [:]

    public init() {}

    public func key(for personId: String) -> String {
        if let key = keys[personId] { return key }
        let key = PersonKeys.random()
        keys[personId] = key
        return key
    }

    public func remove(_ personId: String) { keys.removeValue(forKey: personId) }
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

    public func key(for personId: String) async -> String {
        let item = KeychainItem(service: service, account: personId)
        if let data = await item.load(), let key = String(data: data, encoding: .utf8) { return key }
        let key = await fallback.key(for: personId)
        await item.save(Data(key.utf8))
        return key
    }

    public func remove(_ personId: String) async {
        await KeychainItem(service: service, account: personId).delete()
        await fallback.remove(personId)
    }

    /// The Keychain accepted a write here (false on an unsigned test host).
    static func isUsable(_ store: KeychainPersonKeyStore) async -> Bool {
        let probe = KeychainItem(service: store.service, account: "probe-\(UUID().uuidString)")
        let saved = await probe.save(Data("x".utf8))
        let loaded = await probe.load() != nil
        await probe.delete()
        return saved && loaded
    }
}
