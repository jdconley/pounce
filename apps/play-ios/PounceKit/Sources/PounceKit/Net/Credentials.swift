import Foundation

/// The device identity the server minted: `token` is the bearer secret.
public struct DeviceCredential: Codable, Equatable, Sendable {
    public let deviceId: String
    public let token: String

    public init(deviceId: String, token: String) {
        self.deviceId = deviceId
        self.token = token
    }
}

/// Where the device credential is kept. Async: the real one is the Keychain, which is IO.
public protocol CredentialStore: Sendable {
    func load() async -> DeviceCredential?
    func save(_ c: DeviceCredential) async
    func clear() async
}

/// Keeps the credential in memory only (tests, previews).
public actor MemoryCredentialStore: CredentialStore {
    private var value: DeviceCredential?

    public init() {}

    public func load() -> DeviceCredential? { value }
    public func save(_ c: DeviceCredential) { value = c }
    public func clear() { value = nil }
}

/// Stores the credential as one generic-password item that survives relaunch
/// but never leaves this device (no iCloud sync, no backup restore to another
/// device), through the IO layer's `KeychainItem`. Holds only an immutable item.
public final class KeychainCredentialStore: CredentialStore {
    public static let defaultService = "com.conleychaos.play.device"
    private static let account = "device"

    private let item: KeychainItem

    public init(service: String = KeychainCredentialStore.defaultService) {
        item = KeychainItem(service: service, account: Self.account)
    }

    /// The service for one server's credential: a token minted by the dev server is refused by
    /// production (and the other way round), so each server keeps its own device identity and
    /// switching between a Debug and a Release build orphans nothing.
    public static func serviceName(for config: APIConfig) -> String {
        "\(defaultService).\(config.serverKey)"
    }

    public func load() async -> DeviceCredential? {
        await item.load().flatMap { try? JSONDecoder().decode(DeviceCredential.self, from: $0) }
    }

    public func save(_ c: DeviceCredential) async {
        guard let data = try? JSONEncoder().encode(c) else { return }
        await item.save(data)
    }

    public func clear() async { await item.delete() }
}
