import Foundation

public enum SocketEvent: Equatable, Sendable {
    /// A connect attempt began.
    case connecting
    /// The socket is open; the server's snapshot follows.
    case connected
    case message(ServerMessage)
    /// The connection (or a connect attempt) failed; a reconnect is scheduled.
    case disconnected
    /// Terminal: the room does not exist (404 on connect).
    case notFound
    /// Terminal: the server said `room_closed`.
    case closed
}

public enum RoomSocketError: Error, Equatable {
    case notConnected
}

public protocol RoomSocketing: Sendable {
    var events: AsyncStream<SocketEvent> { get }
    func start() async
    func send(_ m: ClientMessage) async throws
    func reconnectNow() async
    func stop() async
}

/// The one live connection to a room.
///
/// `start()` connects and keeps reconnecting after every loss, waiting
/// `backoff[min(attempt, last)]` first; `attempt` goes back to 0 when a snapshot
/// arrives or on `reconnectNow()`. Frames that don't decode are dropped. `events`
/// finishes when the socket stops for good: 404 on connect (`.notFound`), a
/// `room_closed` error (`.closed`), or `stop()`. A stopped socket can't be restarted.
///
/// The run loop holds the actor until it stops, so call `stop()` when done.
public actor RoomSocket: RoomSocketing {
    public nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation

    private let url: URL
    private let credential: @Sendable () async throws -> DeviceCredential
    private let connector: any WebSocketConnector
    private let backoff: [Duration]
    private let pingInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    private var started = false
    private var finished = false
    /// Bumped whenever a run loop is replaced or the socket stops, so tasks from an
    /// older run (or a stopped socket) never touch state or emit events.
    private var generation = 0
    private var attempt = 0
    private var connection: (any WebSocketConnection)?
    private var runTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    public init(
        code: String,
        config: APIConfig,
        credential: @escaping @Sendable () async throws -> DeviceCredential,
        connector: any WebSocketConnector = URLSessionWebSocketConnector(),
        backoff: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)],
        pingInterval: Duration = .seconds(25),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
        url = config.socketURL(code: code)
        self.credential = credential
        self.connector = connector
        self.backoff = backoff
        self.pingInterval = pingInterval
        self.sleep = sleep
    }

    // MARK: public

    public func start() {
        guard !started, !finished else { return }
        started = true
        launch()
    }

    public func send(_ m: ClientMessage) async throws {
        guard let connection else { throw RoomSocketError.notConnected }
        try await connection.send(Codec.encode(m))
    }

    /// Drops the current connection (or cuts a backoff wait short) and connects again
    /// now, from attempt 0. Starts a socket that was never started; no-op once stopped.
    public func reconnectNow() async {
        guard !finished else { return }
        started = true
        attempt = 0
        let old = dropConnection()
        if old != nil { emit(.disconnected) }
        launch()
        await old?.close()
    }

    public func stop() async {
        guard !finished else { return }
        await finish()?.close()
    }

    // MARK: lifecycle

    /// Replaces the run loop; the old one sees a new generation and exits quietly.
    private func launch() {
        runTask?.cancel()
        generation += 1
        let gen = generation
        runTask = Task { await self.run(gen) }
    }

    private func isCurrent(_ gen: Int) -> Bool {
        gen == generation && !finished && !Task.isCancelled
    }

    /// Stops for good and returns the connection that still needs closing.
    private func finish() -> (any WebSocketConnection)? {
        finished = true
        generation += 1
        runTask?.cancel()
        runTask = nil
        let old = dropConnection()
        continuation.finish()
        return old
    }

    private func dropConnection() -> (any WebSocketConnection)? {
        pingTask?.cancel()
        pingTask = nil
        defer { connection = nil }
        return connection
    }

    private func emit(_ event: SocketEvent) {
        continuation.yield(event)
    }

    private func run(_ gen: Int) async {
        while isCurrent(gen) {
            emit(.connecting)
            let conn: any WebSocketConnection
            do {
                let token = try await credential().token
                guard isCurrent(gen) else { return }
                conn = try await connector.connect(url: url, token: token)
            } catch SocketConnectError.notFound {
                guard isCurrent(gen) else { return }
                emit(.notFound)
                _ = finish()
                return
            } catch {
                guard isCurrent(gen) else { return }
                emit(.disconnected)
                guard await waitBeforeRetry(gen) else { return }
                continue
            }
            guard isCurrent(gen) else {
                await conn.close()
                return
            }

            connection = conn
            emit(.connected)
            pingTask = Task { await self.ping(gen, conn) }
            await receive(gen, conn)

            guard isCurrent(gen) else { return }
            _ = dropConnection()
            await conn.close()
            guard isCurrent(gen) else { return }
            emit(.disconnected)
            guard await waitBeforeRetry(gen) else { return }
        }
    }

    /// Returns when `conn` fails or this run stops being current.
    private func receive(_ gen: Int, _ conn: any WebSocketConnection) async {
        while true {
            let text: String
            do { text = try await conn.receive() } catch { return }
            guard isCurrent(gen) else { return }
            guard let message = try? Codec.decode(text) else { continue }
            emit(.message(message))
            switch message {
            case .snapshot:
                attempt = 0
            case .error(let code) where code == .roomClosed:
                emit(.closed)
                await finish()?.close()
                return
            default:
                break
            }
        }
    }

    /// Sleeps the backoff for the current attempt; false when the run should end.
    private func waitBeforeRetry(_ gen: Int) async -> Bool {
        let delay = backoff.isEmpty ? .zero : backoff[min(attempt, backoff.count - 1)]
        attempt += 1
        try? await sleep(delay)
        return isCurrent(gen)
    }

    /// Pings `conn` every `pingInterval`; two failures in a row close it, which
    /// ends the receive loop and so reconnects. Cancelled when `conn` is dropped.
    private func ping(_ gen: Int, _ conn: any WebSocketConnection) async {
        var failures = 0
        while true {
            do { try await sleep(pingInterval) } catch { return }
            guard isCurrent(gen) else { return }
            do {
                try await conn.sendPing()
                failures = 0
            } catch {
                guard isCurrent(gen) else { return }
                failures += 1
                if failures >= 2 {
                    await conn.close()
                    return
                }
            }
        }
    }
}
