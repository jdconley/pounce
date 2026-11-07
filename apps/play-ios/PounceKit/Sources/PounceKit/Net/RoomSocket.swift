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
    /// The open connection's quality changed (`LinkMeter`). Every new connection starts `good`
    /// without one.
    case link(LinkQuality)
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
/// Heartbeats: every `tick` the connection's `LinkMeter` is checked and, when due, a heartbeat
/// goes out: `{"t":"ping"}` once a snapshot says the server takes them (`room.link`, at its
/// `ping` interval), else a WebSocket ping. Quality changes are `.link` events (and, to a server
/// with links, a `link` report so the other phones can see it); a dead connection is aborted
/// (no close frame, so the server shows the seat reconnecting) and a new one connects at once.
///
/// The run loop holds the actor until it stops, so call `stop()` when done.
public actor RoomSocket: RoomSocketing {
    public nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation

    private let url: URL
    private let credential: @Sendable () async throws -> DeviceCredential
    private let connector: any WebSocketConnector
    private let backoff: [Duration]
    private let heartbeat: LinkMeter.Config
    private let tick: Duration
    private let clock: @Sendable () -> Duration
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
    /// The open connection's meter, and the quality last reported for it.
    private var meter: LinkMeter?
    private var shownQuality: LinkQuality = .good
    /// From the last snapshot: the server takes `{"t":"ping"}` (and `link` reports), this often.
    private var appPings: Duration?

    public init(
        code: String,
        config: APIConfig,
        credential: @escaping @Sendable () async throws -> DeviceCredential,
        connector: any WebSocketConnector = URLSessionWebSocketConnector(),
        backoff: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)],
        heartbeat: LinkMeter.Config = LinkMeter.Config(),
        tick: Duration = .milliseconds(500),
        clock: @escaping @Sendable () -> Duration = RoomSocket.uptime,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
        url = config.socketURL(code: code)
        self.credential = credential
        self.connector = connector
        self.backoff = backoff
        self.heartbeat = heartbeat
        self.tick = tick
        self.clock = clock
        self.sleep = sleep
    }

    /// The time since this process started, on a clock that keeps going while the app sleeps.
    @Sendable public static func uptime() -> Duration {
        Self.origin.duration(to: .now)
    }

    private static let origin = ContinuousClock.now

    // MARK: public

    public func start() {
        guard !started, !finished else { return }
        started = true
        launch()
    }

    /// The open connection's last heartbeat round trip (diagnostics and tests).
    public var lastRoundTrip: Duration? { meter?.lastRoundTrip }

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
        meter = nil
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
            meter = LinkMeter(config: heartbeat, now: clock())
            shownQuality = .good
            emit(.connected)
            pingTask = Task { await self.beat(gen, conn) }
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
            meter?.heard(now: clock())
            guard let message = try? Codec.decode(text) else { continue }
            if case .pong = message {
                pong(gen)
                continue
            }
            emit(.message(message))
            switch message {
            case .snapshot(_, _, let room):
                attempt = 0
                appPings = room.link.map { .milliseconds(min(max($0.ping, 1000), 30_000)) }
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

    /// Every `tick`: a heartbeat when one is due, then the meter's verdict. A dead connection is
    /// closed, which ends the receive loop and so reconnects. Cancelled when `conn` is dropped.
    private func beat(_ gen: Int, _ conn: any WebSocketConnection) async {
        while true {
            do { try await sleep(tick) } catch { return }
            guard isCurrent(gen), var meter else { return }
            let now = clock()
            if let every = appPings { meter.config.pingEvery = every }
            if meter.shouldPing(now: now) {
                meter.pingSent(now: now)
                // Never awaited here: a send into a dead socket can hang, and the meter must keep ticking.
                if appPings != nil {
                    Task { try? await conn.send(Codec.encode(ClientMessage.ping)) }
                } else {
                    Task { [weak self] in
                        guard (try? await conn.sendPing()) != nil else { return }
                        await self?.pong(gen)
                    }
                }
            }
            let verdict = meter.tick(now: now)
            self.meter = meter
            show(meter.quality, conn)
            if verdict == .dead {
                await died(gen, conn)
                return
            }
        }
    }

    /// A dead connection: reconnect now, without waiting for its receive to fail (on a dead
    /// network that can take as long as the network stays dead), and drop it with no goodbye.
    private func died(_ gen: Int, _ conn: any WebSocketConnection) async {
        guard isCurrent(gen) else { return }
        _ = dropConnection()
        emit(.disconnected)
        launch()
        await conn.abort()
    }

    private func pong(_ gen: Int) {
        guard isCurrent(gen), var meter, let conn = connection else { return }
        meter.pong(now: clock())
        self.meter = meter
        show(meter.quality, conn)
    }

    /// Reports a quality change: a `.link` event, and to a server with links, a `link` message.
    private func show(_ quality: LinkQuality, _ conn: any WebSocketConnection) {
        guard quality != shownQuality else { return }
        shownQuality = quality
        emit(.link(quality))
        guard appPings != nil else { return }
        let report = ClientMessage.link(quality == .weak ? .weak : .good)
        Task { try? await conn.send(Codec.encode(report)) }
    }
}
