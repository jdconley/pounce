import Foundation
import PounceKit

/// A TV waiting for a phone to link it (`ScreenLink`), as the TV's model sees one, so a test can
/// drive it.
protocol ScreenLinking: Sendable {
    var events: AsyncStream<ScreenLinkEvent> { get }
    func start(showing: String?) async
    func stop() async
}

extension ScreenLink: ScreenLinking {}

/// Everything the TV's model reaches outside the app: the server (tables it makes, its links and
/// the table's socket) and the values it keeps. Every call is async or makes an object that does
/// its work off the main thread.
struct TVServices {
    /// Makes a table with this TV as its screen (`POST /v1/rooms`, `screen: true`); its code.
    var createRoom: @Sendable (_ game: String) async throws -> String
    /// A new link for a phone to scan or type.
    var link: @MainActor () -> any ScreenLinking
    /// One connection to table `code` as its screen; a table that goes to the background and
    /// back makes another.
    var socket: @Sendable (_ code: String) -> any RoomSocketing
    /// The kept table and sound setting.
    var keep: any ScreenKeeping
    /// The link a phone scans to join table `code`: `/j/<CODE>` on this TV's server.
    var inviteURL: (_ code: String) -> URL = { DeepLink.shareURL(code: $0) }
    /// Applies the TV's sound setting to the game's sounds.
    var applySound: @MainActor (Bool) -> Void = { Settings.shared.soundOn = $0 }
    /// Reconnects a table's socket as soon as the network comes back (the live TV only).
    var watchesNetwork = false
}

extension TVServices {
    /// The real server at `config`, as this TV's own device: its credential is in the Keychain.
    static func live(config: APIConfig) -> TVServices {
        let api = APIClient(config: config, credentials: KeychainCredentialStore(service: KeychainCredentialStore.serviceName(for: config)))
        return TVServices(
            createRoom: { game in try await api.createRoom(game: game, screen: true) },
            link: { ScreenLink(api: api, config: config) },
            socket: { code in
                RoomSocket(code: code, config: config, role: .screen, credential: { try await api.credential() }, connector: URLSessionWebSocketConnector(headers: config.headers))
            },
            keep: DefaultsScreenKeep(),
            inviteURL: { config.endpoint("/j/\($0)") },
            watchesNetwork: true)
    }
}
