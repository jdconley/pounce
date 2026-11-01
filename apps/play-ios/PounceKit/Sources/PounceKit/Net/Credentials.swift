import Foundation
import Security
import Synchronization

/// The device identity the server minted: `token` is the bearer secret.
public struct DeviceCredential: Codable, Equatable, Sendable {
    public let deviceId: String
    public let token: String

    public init(deviceId: String, token: String) {
        self.deviceId = deviceId
        self.token = token
    }
}

public protocol CredentialStore: Sendable {
    func load() -> DeviceCredential?
    func save(_ c: DeviceCredential)
    func clear()
}

/// Keeps the credential in memory only (tests, previews).
public final class MemoryCredentialStore: CredentialStore {
    private let value = Mutex<DeviceCredential?>(nil)

    public init() {}

    public func load() -> DeviceCredential? { value.withLock { $0 } }
    public func save(_ c: DeviceCredential) { value.withLock { $0 = c } }
    public func clear() { value.withLock { $0 = nil } }
}

/// Stores the credential as one generic-password item that survives relaunch
/// but never leaves this device (no iCloud sync, no backup restore to another
/// device). Holds only an immutable service name, and the Security framework
/// calls are thread-safe, so the class is Sendable without a lock.
public final class KeychainCredentialStore: CredentialStore {
    public static let defaultService = "com.conleychaos.play.device"
    private static let account = "device"

    private let service: String

    public init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    /// The service for one server's credential: a token minted by the dev server is refused by
    /// production (and the other way round), so each server keeps its own device identity and
    /// switching between a Debug and a Release build orphans nothing.
    public static func serviceName(for config: APIConfig) -> String {
        "\(defaultService).\(config.serverKey)"
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func load() -> DeviceCredential? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(DeviceCredential.self, from: data)
    }

    public func save(_ c: DeviceCredential) {
        guard let data = try? JSONEncoder().encode(c) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    public func clear() { SecItemDelete(query as CFDictionary) }
}
