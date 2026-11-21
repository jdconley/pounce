import Foundation

/// `POST /v1/screens`'s answer: a link a phone can make to this TV, by scanning `url` or typing
/// `code` (docs/tv-protocol.md, "TV links").
public struct ScreenLinkOffer: Decodable, Equatable, Sendable {
    public let token: String
    public let code: String
    public let url: URL
    /// How long the link lives, in milliseconds, as the server sends it.
    public let expiresIn: Int

    public init(token: String, code: String, url: URL, expiresIn: Int) {
        self.token = token
        self.code = code
        self.url = url
        self.expiresIn = expiresIn
    }

    /// When to ask for the next link: at 80% of this one's life.
    public var renewAfter: Duration { .milliseconds(Int((Double(expiresIn) * ScreenLink.renewAt).rounded())) }
}

public enum ScreenLinkEvent: Equatable, Sendable {
    /// A link to show. Each renewal brings a new one; the last one shown is the one to keep showing.
    case code(token: String, code: String, url: URL)
    /// A phone linked this TV to the table `room`, which already lists it as a screen. The link
    /// is spent: the events end after this.
    case linked(room: String)
    /// A phone linked this TV to its Daily Dish board: the board token to keep
    /// (docs/daily-protocol.md, "A board on the TV"). The link is spent: the events end after this.
    case board(token: String)
    /// Waiting on the network: the link shown may not reach the server.
    case offline
}

/// A TV waiting to be linked: it asks for a link (`POST /v1/screens`), shows it, and listens on
/// the link's socket for the phone that scans or types it. Mirrors the web player's `ScreenLink`
/// (`apps/play-web/src/net/screen-link.ts`).
///
/// - The link is renewed at 80% of its life. The old socket keeps listening until the new one is
///   open, since a phone may link the old code meanwhile; a `linked` from either wins.
/// - A renewal that fails keeps the old link and socket and asks again quietly, with backoff.
/// - `expired`, or a socket the server refuses (404 for an unknown or expired link, 401 for a
///   refused device token; 4404 and 4401 for a browser), asks for a new link.
/// - A socket that drops reconnects to the same link, with backoff.
/// - A heartbeat (`{"t":"ping"}`, answered `{"t":"pong"}`) finds a socket that died silently.
///
/// One use: `events` finishes on `linked` or `stop()`, and a stopped link can't be restarted.
/// Make a new one to show a link again. Its sockets and timers hold the actor until then, so call
/// `stop()` when the link is no longer shown.
public actor ScreenLink {
    /// The share of a link's life after which a new one is asked for.
    static let renewAt = 0.8

    public nonisolated let events: AsyncStream<ScreenLinkEvent>
    private let continuation: AsyncStream<ScreenLinkEvent>.Continuation

    private let config: APIConfig
    private let screens: @Sendable (String?) async throws -> ScreenLinkOffer
    private let credential: @Sendable () async throws -> DeviceCredential
    private let connector: any WebSocketConnector
    private let backoff: [Duration]
    private let heartbeat: Duration?
    private let sleep: @Sendable (Duration) async throws -> Void

    private struct Slot {
        let id: Int
        let connection: any WebSocketConnection
        /// Something arrived since the last heartbeat went out.
        var heard = true
        var pinged = false
        var tasks: [Task<Void, Never>] = []
    }

    private enum Again: Sendable {
        case renew(timed: Bool)
        case connect
    }

    private var started = false
    private var stopped = false
    /// Bumped by every renewal and by stopping, so work for an older link never acts.
    private var generation = 0
    /// Bumped by every connect, so only the latest one's socket is kept.
    private var dialing = 0
    private var attempt = 0
    private var showing: String?
    private var token = ""
    private var nextSlot = 0
    /// The socket of the link shown.
    private var live: Slot?
    /// The socket of the link being replaced: kept listening until the new one is open.
    private var old: Slot?
    private var renewTimer: Task<Void, Never>?
    private var retryTimer: Task<Void, Never>?

    private static let ping = #"{"t":"ping"}"#
    private static let pong = #"{"t":"pong"}"#

    public init(
        config: APIConfig,
        screens: @escaping @Sendable (String?) async throws -> ScreenLinkOffer,
        credential: @escaping @Sendable () async throws -> DeviceCredential,
        connector: any WebSocketConnector = URLSessionWebSocketConnector(),
        backoff: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)],
        heartbeat: Duration? = .seconds(25),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        (events, continuation) = AsyncStream.makeStream(of: ScreenLinkEvent.self)
        self.config = config
        self.screens = screens
        self.credential = credential
        self.connector = connector
        self.backoff = backoff
        self.heartbeat = heartbeat
        self.sleep = sleep
        // Whoever reads the events went away (its task was cancelled): nothing is shown, so stop.
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
    }

    /// Links through `api`, as its device. `connector` defaults to URLSession with `config`'s headers.
    public init(api: APIClient, config: APIConfig, connector: (any WebSocketConnector)? = nil) {
        self.init(
            config: config,
            screens: { try await api.screens(showing: $0) },
            credential: { try await api.credential() },
            connector: connector ?? URLSessionWebSocketConnector(headers: config.headers))
    }

    // MARK: public

    /// Asks for a link and starts listening for a phone; `showing` is a table this TV already
    /// shows ("Link another table"). Once only.
    public func start(showing: String? = nil) {
        guard !started, !stopped else { return }
        started = true
        self.showing = showing
        Task { await self.renew(timed: false) }
    }

    /// Closes the socket and ends renewals and `events`.
    public func stop() async {
        guard !stopped else { return }
        for connection in finish() { await connection.close() }
    }

    // MARK: lifecycle

    private func isCurrent(_ gen: Int) -> Bool { gen == generation && !stopped }

    private func emit(_ event: ScreenLinkEvent) { continuation.yield(event) }

    /// Stops for good, after `last`; returns the sockets still to close.
    private func finish(_ last: ScreenLinkEvent? = nil) -> [any WebSocketConnection] {
        stopped = true
        generation += 1
        cancelTimers()
        let open = dropAll()
        if let last { emit(last) }
        continuation.finish()
        return open
    }

    private func cancelTimers() {
        renewTimer?.cancel()
        retryTimer?.cancel()
        renewTimer = nil
        retryTimer = nil
    }

    /// Forgets both sockets and returns them, to close.
    private func dropAll() -> [any WebSocketConnection] {
        let slots = [old, live].compactMap { $0 }
        old = nil
        live = nil
        for slot in slots { slot.tasks.forEach { $0.cancel() } }
        return slots.map(\.connection)
    }

    private func close(_ connections: [any WebSocketConnection]) {
        for connection in connections { Task { await connection.close() } }
    }

    /// A new link and a new socket. A timed renewal keeps the old socket listening (a phone may
    /// link the old code meanwhile) until the new one is open; any other renewal closes it first.
    private func renew(timed: Bool) async {
        guard !stopped else { return }
        cancelTimers()
        if !timed { close(dropAll()) }
        generation += 1
        let gen = generation
        let offer: ScreenLinkOffer
        do {
            offer = try await screens(showing)
        } catch {
            guard isCurrent(gen) else { return }
            // A timed renewal that failed still has its old link and socket: try again, quietly.
            if !timed { emit(.offline) }
            retry(gen, .renew(timed: timed))
            return
        }
        guard isCurrent(gen) else { return }
        token = offer.token
        emit(.code(token: offer.token, code: offer.code, url: offer.url))
        let after = offer.renewAfter
        renewTimer = Task { [sleep] in
            do { try await sleep(after) } catch { return }
            await self.renewOnTime(gen)
        }
        await connect(gen)
    }

    private func renewOnTime(_ gen: Int) async {
        guard isCurrent(gen) else { return }
        renewTimer = nil  // this task runs the renewal: cancelling it would cancel the request
        await renew(timed: true)
    }

    private func connect(_ gen: Int) async {
        dialing += 1
        let dial = dialing
        let device: String
        do {
            device = try await credential().token
        } catch {
            guard isCurrent(gen), dial == dialing else { return }
            retry(gen, .connect)
            return
        }
        guard isCurrent(gen), dial == dialing else { return }
        if let live {
            if let old { close([old.connection]) }
            old?.tasks.forEach { $0.cancel() }
            old = live
            self.live = nil
        }
        let connection: any WebSocketConnection
        do {
            connection = try await connector.connect(url: config.screenSocketURL(token: token), token: device)
        } catch SocketConnectError.notFound, SocketConnectError.unauthorized {
            // A link the server no longer knows, or a device token it refused: replace it, not retry it.
            guard isCurrent(gen), dial == dialing else { return }
            close(dropAll())
            retry(gen, .renew(timed: false))
            return
        } catch {
            guard isCurrent(gen), dial == dialing else { return }
            // The network, most likely. A socket on the link being replaced keeps listening (a phone
            // may link the previous code meanwhile), so this is quiet until nothing is listening.
            if old == nil { emit(.offline) }
            retry(gen, .connect)
            return
        }
        guard isCurrent(gen), dial == dialing else {
            await connection.close()
            return
        }
        attempt = 0
        if let old {
            old.tasks.forEach { $0.cancel() }
            close([old.connection])
            self.old = nil
        }
        nextSlot += 1
        let id = nextSlot
        var slot = Slot(id: id, connection: connection)
        slot.tasks.append(Task { await self.listen(id, connection) })
        if let heartbeat {
            slot.tasks.append(Task { await self.beat(id, connection, every: heartbeat) })
        }
        live = slot
    }

    private func retry(_ gen: Int, _ again: Again) {
        let delay = backoff.isEmpty ? .zero : backoff[min(attempt, backoff.count - 1)]
        attempt += 1
        retryTimer?.cancel()
        retryTimer = Task { [sleep] in
            do { try await sleep(delay) } catch { return }
            await self.fire(gen, again)
        }
    }

    private func fire(_ gen: Int, _ again: Again) async {
        guard isCurrent(gen) else { return }
        retryTimer = nil  // this task runs `again`: cancelling it would cancel the request
        switch again {
        case .renew(let timed): await renew(timed: timed)
        case .connect: await connect(gen)
        }
    }

    // MARK: the socket

    private struct Frame: Decodable {
        let t: String
        let room: String?
        let token: String?
    }

    private func isOpen(_ id: Int) -> Bool { live?.id == id || old?.id == id }

    private func listen(_ id: Int, _ connection: any WebSocketConnection) async {
        while true {
            let text: String
            do { text = try await connection.receive() } catch {
                lost(id)
                return
            }
            guard isOpen(id) else { return }
            if live?.id == id { live?.heard = true } else { old?.heard = true }
            guard let frame = try? JSONDecoder().decode(Frame.self, from: Data(text.utf8)) else { continue }
            switch frame.t {
            case "ping":
                Task { try? await connection.send(Self.pong) }
            case "linked":
                guard let room = frame.room else { continue }
                close(finish(.linked(room: room)))
                return
            case "board":
                guard let token = frame.token else { continue }
                close(finish(.board(token: token)))
                return
            case "expired":
                // The link being replaced expiring is expected: its successor is already shown.
                guard live?.id == id else { continue }
                Task { await self.renew(timed: false) }
            default:
                break
            }
        }
    }

    /// A socket that failed or went silent. The one being replaced is closed quietly; the one
    /// shown reconnects.
    private func lost(_ id: Int) {
        if let old, old.id == id {
            old.tasks.forEach { $0.cancel() }
            close([old.connection])
            self.old = nil
            return
        }
        guard live?.id == id, !stopped else { return }
        close(dropAll())
        emit(.offline)
        retry(generation, .connect)
    }

    /// Every `every`: a ping, unless the last one heard nothing back, which means the socket died.
    private func beat(_ id: Int, _ connection: any WebSocketConnection, every: Duration) async {
        while true {
            do { try await sleep(every) } catch { return }
            guard !stopped else { return }
            if live?.id == id, var slot = live {
                if slot.pinged && !slot.heard { return lost(id) }
                slot.pinged = true
                slot.heard = false
                live = slot
            } else if old?.id == id, var slot = old {
                if slot.pinged && !slot.heard { return lost(id) }
                slot.pinged = true
                slot.heard = false
                old = slot
            } else {
                return
            }
            Task { try? await connection.send(Self.ping) }
        }
    }
}
