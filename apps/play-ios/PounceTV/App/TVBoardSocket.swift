import Foundation
import PounceKit

enum BoardSocketEvent: Equatable, Sendable {
    case message(DailyBoardMessage)
    case online
    case offline
    /// The server no longer knows this board (unlinked from a phone, or its 30 days are up): the
    /// TV forgets the token and goes home. The events end after this.
    case gone
}

/// Tonight's board as the TV's model sees its socket, so a test can drive it.
protocol BoardSocketing: Sendable {
    var events: AsyncStream<BoardSocketEvent> { get }
    func start() async
    func stop() async
}

/// The TV's board socket (docs/daily-protocol.md, "The board socket"): `GET
/// /v1/daily/board/ws?board=<token>` as the TV's own device. It pings, and reconnects with backoff
/// when the socket drops. A 404 on connect (a token unknown, expired, revoked or another
/// device's) is `gone`. A revoke closes the open socket; URLSession doesn't hand over the close
/// reason, so the reconnect's 404 is how the TV hears it. One use: make a new one to connect again.
actor TVBoardSocket: BoardSocketing {
    nonisolated let events: AsyncStream<BoardSocketEvent>
    private let feed: AsyncStream<BoardSocketEvent>.Continuation
    private let url: URL
    private let credential: @Sendable () async throws -> DeviceCredential
    private let forget: @Sendable () async -> Void
    private let connector: any WebSocketConnector
    private let backoff: [Duration]
    private let heartbeat: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    private var started = false
    private var stopped = false
    private var attempt = 0
    private var connection: (any WebSocketConnection)?
    private var tasks: [Task<Void, Never>] = []

    init(
        url: URL,
        credential: @escaping @Sendable () async throws -> DeviceCredential,
        forget: @escaping @Sendable () async -> Void = {},
        connector: any WebSocketConnector,
        backoff: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)],
        heartbeat: Duration = .seconds(25),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        (events, feed) = AsyncStream.makeStream(of: BoardSocketEvent.self)
        self.url = url
        self.credential = credential
        self.forget = forget
        self.connector = connector
        self.backoff = backoff
        self.heartbeat = heartbeat
        self.sleep = sleep
        feed.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
    }

    /// The board socket's URL on `config`'s server: ws or wss, with the board token in the query.
    static func url(config: APIConfig, board: String) -> URL {
        let http = config.endpoint("/v1/daily/board/ws", query: [URLQueryItem(name: "board", value: board)])
        var parts = URLComponents(url: http, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.scheme = parts.scheme?.lowercased() == "https" ? "wss" : "ws"
        return parts.url ?? http
    }

    func start() {
        guard !started, !stopped else { return }
        started = true
        tasks.append(Task { await self.run() })
    }

    func stop() async {
        guard !stopped else { return }
        stopped = true
        tasks.forEach { $0.cancel() }
        tasks = []
        let open = connection
        connection = nil
        feed.finish()
        await open?.close()
    }

    // MARK: the loop

    private func run() async {
        while !stopped, !Task.isCancelled {
            switch await connectOnce() {
            case .gone:
                feed.yield(.gone)
                await stop()
                return
            case .again:
                feed.yield(.offline)
                let delay = backoff.isEmpty ? .zero : backoff[min(attempt, backoff.count - 1)]
                attempt += 1
                do { try await sleep(delay) } catch { return }
            }
        }
    }

    private enum After { case gone, again }

    /// One connection, from dialling to its end.
    private func connectOnce() async -> After {
        let device: DeviceCredential
        do { device = try await credential() } catch { return .again }
        guard !stopped else { return .again }
        let open: any WebSocketConnection
        do {
            open = try await connector.connect(url: url, token: device.token)
        } catch SocketConnectError.notFound {
            return .gone
        } catch SocketConnectError.unauthorized {
            await forget()
            return .again
        } catch {
            return .again
        }
        guard !stopped else {
            await open.close()
            return .again
        }
        connection = open
        attempt = 0
        feed.yield(.online)
        let pinger = Task { [heartbeat, sleep] in
            while !Task.isCancelled {
                do { try await sleep(heartbeat) } catch { return }
                try? await open.send(#"{"t":"ping"}"#)
            }
        }
        defer { pinger.cancel() }
        while !stopped {
            let text: String
            do { text = try await open.receive() } catch { break }
            if let message = DailyBoardMessage.decode(text) { feed.yield(.message(message)) }
        }
        connection = nil
        await open.close()
        return .again
    }
}
