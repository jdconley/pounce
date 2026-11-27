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
    /// Tonight's board's socket for board token `token` (one connection; a new one to reconnect).
    var boardSocket: @Sendable (_ token: String) -> any BoardSocketing = { _ in NoBoardSocket() }
    /// The kept board token (the Keychain on a real TV).
    var boards: any BoardKeeping = MemoryBoardKeep()
    /// Whether the server has the Daily Dish on (its board socket answers 426 to a plain request).
    /// Nil when it can't tell (offline, a server error): home asks again.
    var dailyOn: @Sendable () async -> Bool? = { false }
    /// How long home waits before asking again whether the Dish is on, after `attempt` tries.
    var retryDelay: @Sendable (_ attempt: Int) -> Duration = { .seconds(2 * $0) }
    /// The clock: the board token's 30 days, the watch card's 20 seconds.
    var now: @Sendable () -> Date = { Date() }
    /// The link a phone scans to join table `code`: `/j/<CODE>` on this TV's server.
    var inviteURL: (_ code: String) -> URL = { DeepLink.shareURL(code: $0) }
    /// The QR a phone scans to join Purrtrait table `code` with the TV's key: `/e/<CODE>?near=<KEY>`.
    var easelURL: (_ code: String, _ key: String) -> URL = { DeepLink.easelURL(code: $0, near: $1) }
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
            boardSocket: { token in
                TVBoardSocket(
                    url: TVBoardSocket.url(config: config, board: token),
                    credential: { try await api.credential() },
                    connector: URLSessionWebSocketConnector(headers: config.headers))
            },
            boards: KeychainBoardKeep(),
            dailyOn: { await TVServices.dailyOn(api: api, config: config) },
            inviteURL: { config.endpoint("/j/\($0)") },
            easelURL: { code, key in config.endpoint("/e/\(code)", query: [URLQueryItem(name: "near", value: key)]) },
            watchesNetwork: true)
    }

    /// Asks the server whether the Daily Dish is on: `GET /v1/daily/board/ws` without an upgrade
    /// answers 426 when it is, 404 when it isn't (docs/daily-protocol.md). Nil when it can't tell:
    /// no credential, no network, or any other answer.
    @concurrent
    static func dailyOn(api: APIClient, config: APIConfig) async -> Bool? {
        guard let token = try? await api.credential().token else { return nil }
        var request = URLRequest(url: config.endpoint("/v1/daily/board/ws"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (name, value) in config.headers { request.setValue(value, forHTTPHeaderField: name) }
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 426: return true
        case 404: return false
        default: return nil
        }
    }
}

/// A board socket that never connects: services with no Daily Dish (demos that don't show it).
final class NoBoardSocket: BoardSocketing {
    let events: AsyncStream<BoardSocketEvent>
    private let feed: AsyncStream<BoardSocketEvent>.Continuation

    init() { (events, feed) = AsyncStream.makeStream(of: BoardSocketEvent.self) }

    func start() async {}
    func stop() async { feed.finish() }
}
