import Foundation

// The Daily Dish's client side (docs/daily-protocol.md): the routes, the server's clock, and the
// run session every daily game plays through. All of it is off the main actor: the routes and the
// session are actors, and a game's own types are decoded on the session before a game sees them.

// MARK: the routes

/// The daily routes. A 404 from `start` or `board` means the server has the Dish off: hide it.
public protocol DailyService: Sendable {
    func start(game: String, person: String?) async throws -> DailyStart
    /// The same, asking for a game's `rules` at the run's first start (`{ "rules": "lives" }`).
    /// A service that knows one set of rules leaves it to the default, which ignores them.
    func start(game: String, person: String?, rules: String?) async throws -> DailyStart
    func moves(run: String, body: DailyMovesBody, person: String?) async throws -> DailyMovesAnswer
    /// `hints`: the hints used so far, so a resent hint costs nothing more.
    func hint(run: String, hints: Int, person: String?) async throws -> DailyMovesAnswer
    func giveUp(run: String, person: String?) async throws -> DailyMovesAnswer
    func showOnTV(run: String, on: Bool, person: String?) async throws
    func board(date: String?, person: String?) async throws -> DailyBoard
    func stats(person: String?) async throws -> DailyStatsList
    /// Puts this person's board on the TV that `key` names (its QR or backup code).
    func linkBoard(_ key: ScreenKey, person: String?) async throws
    /// Every TV showing this person's board forgets it.
    func unlinkBoard(person: String?) async throws
}

extension DailyService {
    public func start(game: String, person: String?, rules: String?) async throws -> DailyStart {
        try await start(game: game, person: person)
    }
}

extension APIClient: DailyService {
    private static func who(_ person: String?) -> [URLQueryItem] {
        person.map { [URLQueryItem(name: "person", value: $0)] } ?? []
    }

    private static func path(_ part: String) -> String {
        part.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? part
    }

    public func start(game: String, person: String?) async throws -> DailyStart {
        try await start(game: game, person: person, rules: nil)
    }

    public func start(game: String, person: String?, rules: String?) async throws -> DailyStart {
        let body: [String: String]? = rules.map { ["rules": $0] }
        let data = try await authenticated("POST", "/v1/daily/\(Self.path(game))/start", body: body, query: Self.who(person))
        return try decode(DailyStart.self, from: data, status: 200)
    }

    public func moves(run: String, body: DailyMovesBody, person: String?) async throws -> DailyMovesAnswer {
        let data = try await authenticated("POST", "/v1/daily/runs/\(Self.path(run))/moves", body: body, query: Self.who(person))
        return try decode(DailyMovesAnswer.self, from: data, status: 200)
    }

    public func hint(run: String, hints: Int, person: String?) async throws -> DailyMovesAnswer {
        let data = try await authenticated("POST", "/v1/daily/runs/\(Self.path(run))/hint", body: ["hints": hints], query: Self.who(person))
        return try decode(DailyMovesAnswer.self, from: data, status: 200)
    }

    public func giveUp(run: String, person: String?) async throws -> DailyMovesAnswer {
        let data = try await authenticated("POST", "/v1/daily/runs/\(Self.path(run))/giveup", body: nil, query: Self.who(person))
        return try decode(DailyMovesAnswer.self, from: data, status: 200)
    }

    public func showOnTV(run: String, on: Bool, person: String?) async throws {
        _ = try await authenticated("PUT", "/v1/daily/runs/\(Self.path(run))/tv", body: ["on": on], query: Self.who(person))
    }

    public func board(date: String?, person: String?) async throws -> DailyBoard {
        var query = Self.who(person)
        if let date { query.append(URLQueryItem(name: "date", value: date)) }
        let data = try await authenticated("GET", "/v1/daily/board", body: nil, query: query)
        return try decode(DailyBoard.self, from: data, status: 200)
    }

    public func stats(person: String?) async throws -> DailyStatsList {
        let data = try await authenticated("GET", "/v1/daily/stats", body: nil, query: Self.who(person))
        return try decode(DailyStatsList.self, from: data, status: 200)
    }

    public func linkBoard(_ key: ScreenKey, person: String?) async throws {
        var body: [String: ScreenLinkValue] = ["board": .flag(true)]
        switch key {
        case .token(let token): body["token"] = .text(token)
        case .code(let code): body["code"] = .text(code)
        }
        do {
            _ = try await authenticated("POST", "/v1/screens/link", body: body, query: Self.who(person))
        } catch APIError.notFound {
            throw ScreenLinkError.notFound
        } catch APIError.tooManyAttempts(let after) {
            throw ScreenLinkError.tooManyAttempts(retryAfter: after)
        }
    }

    public func unlinkBoard(person: String?) async throws {
        _ = try await authenticated("DELETE", "/v1/daily/board/tv", body: nil, query: Self.who(person))
    }
}

// MARK: the clock

/// The run's clock is the server's: from its start to now, plus the run's `hintMs` a hint (30
/// seconds, or none under Nine Lives' lives). No pause. Counted locally, corrected by how far this
/// device's clock is from the server's at start.
public struct DailyClock: Sendable, Hashable {
    /// What one hint adds, from the start answer.
    public let hintMs: Int64

    /// Epoch ms, the server's.
    public let startedAt: Int64
    /// The server's clock minus this device's, at start.
    public let skewMs: Int64
    /// When the run closes (04:00 the person's time), the server's epoch ms.
    public let closesAt: Int64

    public init(start: DailyStart, received: Date = Date()) {
        startedAt = start.startedAt
        closesAt = start.closesAt
        hintMs = Int64(start.hintMs)
        skewMs = start.now - Int64((received.timeIntervalSince1970 * 1000).rounded())
    }

    /// The server's epoch ms at a local moment.
    public func serverMs(at date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) + skewMs }

    /// The time the server would count at `date`, with `hints` used: never negative.
    public func elapsedMs(at date: Date, hints: Int) -> Int64 {
        max(0, serverMs(at: date) - startedAt) + Int64(hints) * hintMs
    }

    /// Milliseconds left before the run closes.
    public func remainingMs(at date: Date) -> Int64 { max(0, closesAt - serverMs(at: date)) }

    /// "4:07", or "1:02:09" past an hour.
    public static func format(ms: Int64) -> String {
        let total = max(0, ms) / 1000
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let ss = s < 10 ? "0\(s)" : "\(s)"
        if h > 0 { return "\(h):\(m < 10 ? "0\(m)" : "\(m)"):\(ss)" }
        return "\(m):\(ss)"
    }
}

// MARK: time

/// The run session's sense of time: when a move joined the queue, and waiting out the batch
/// window or a retry. The app uses the wall clock (`DailyWallTimer`); tests pass a timer they
/// advance by hand, so nothing depends on how fast the machine runs.
public protocol DailyTimer: Sendable {
    /// The time now, counted from any fixed start.
    func now() -> Duration
    /// Returns once `now()` has reached `deadline`, or as soon as the calling task is cancelled.
    func wait(until deadline: Duration) async
}

/// The wall clock (`ContinuousClock`: it keeps counting while the device sleeps).
public struct DailyWallTimer: DailyTimer {
    private let start = ContinuousClock.now

    public init() {}

    public func now() -> Duration { start.duration(to: .now) }

    public func wait(until deadline: Duration) async {
        try? await Task.sleep(until: start.advanced(by: deadline), clock: .continuous)
    }
}

// MARK: the run session

/// Whether the session is reaching the server.
public enum DailyLink: Sendable, Hashable {
    case ok
    /// A call failed; it's being sent again (the same `from`, so the server answers it once).
    case retrying
    /// The run is gone (a 404): another person's, or the server forgot it. Leave the puzzle.
    case lost
}

/// What the server said, as the session hands it on, raw. A game usually wants
/// `DailyRunSession.events(reveal:state:)` instead, which decodes these into its own types.
public enum DailyRunEvent: Sendable, Hashable {
    /// A batch was taken. `reveals` are the server's answers to the moves that reveal something
    /// (Sniff's marks, Box Fort's next set), in order.
    case accepted(seq: Int, reveals: [DailyJSON], progress: Double)
    /// A hint: what it filled (`nil` for a game with no hints, which never asks). `hints` is the
    /// run's count after it.
    case hinted(reveal: DailyJSON?, hints: Int, progress: Double)
    /// The server and this phone disagreed (a move refused as illegal, a stale batch): here is the
    /// run as the server has it. Throw away anything drawn since and draw this.
    case resync(DailyStart)
    /// The run ended: solved, missed, given up, done or closed at 04:00.
    case ended(DailyResult)
    case link(DailyLink)
}

/// The same, decoded into one game's own types on the session, never on the main actor.
public enum DailyGameEvent<Reveal: Decodable & Sendable, State: Decodable & Sendable>: Sendable {
    case accepted(seq: Int, reveals: [Reveal], progress: Double)
    case hinted(reveal: Reveal?, hints: Int)
    case resync(state: State, seq: Int, hints: Int)
    case ended(DailyResult)
    case link(DailyLink)
}

/// The answer to one move a game waited for (`DailyRunSession.play(_:revealing:)`).
public enum DailyPlayAnswer<Reveal: Decodable & Sendable>: Sendable {
    /// Taken, with the reveals of the batch it went in (for a move sent alone, its own).
    case accepted([Reveal])
    /// Refused or lost; the session resyncs, and a `.resync` event follows.
    case refused
}

/// One run of one daily puzzle, between a game's screen and the server.
///
/// A game draws each move at once and hands it to `send(move:urgent:)`. The session batches them:
/// it sends what's waiting a second after the first of it, or at once for a move marked urgent
/// (a Sniff guess, Box Fort's last piece of a set). One batch is in flight at a time. A batch that
/// fails on the network is sent again with the same `from`, so the server answers it once. Any
/// refusal (illegal, stale, over, or `too_soon`: past the game's move budget) drops what's waiting
/// and resyncs from a fresh start: games adopt the `.resync` state. Every answer goes out to each
/// `events` stream.
public actor DailyRunSession {
    /// The start answer this session began from.
    public nonisolated let start: DailyStart
    public nonisolated let clock: DailyClock
    public nonisolated let person: String?
    /// The rules asked for at start (`DailyGameInfo.rules`), asked again on a resync.
    public nonisolated let rules: String?
    public nonisolated var game: String { start.game }

    public private(set) var seq: Int
    public private(set) var hints: Int
    public private(set) var progress: Double = 0
    public private(set) var result: DailyResult?
    public private(set) var link: DailyLink = .ok

    private let service: any DailyService
    private let window: Duration
    private let retry: Duration
    private let timer: any DailyTimer
    private struct Waiting {
        let id: Int
        let move: DailyJSON
        /// When it joined the queue, as `timer` counts.
        let at: Duration
    }
    private var queue: [Waiting] = []
    private var nextID = 0
    private var urgentThrough: Int?
    private var pumping = false
    private var nap: Task<Void, Never>?
    private var idle: [CheckedContinuation<Void, Never>] = []
    private var waiters: [Int: CheckedContinuation<[DailyJSON]?, Never>] = [:]
    private var subscribers: [Int: @Sendable (DailyRunEvent) -> Void] = [:]
    private var nextSubscriber = 0

    public static let maxBatch = 100

    /// `window`: how long a move waits for others to join its batch (one second on the wire).
    /// `retry`: the first wait before a failed call is sent again (it doubles, up to 8 seconds).
    /// `timer`: the wall clock, or a test's.
    public init(
        start: DailyStart, service: any DailyService, person: String?, rules: String? = nil, received: Date = Date(),
        window: Duration = .seconds(1), retry: Duration = .milliseconds(500), timer: any DailyTimer = DailyWallTimer()
    ) {
        self.start = start
        self.service = service
        self.person = person
        self.rules = rules
        self.window = window
        self.retry = retry
        self.timer = timer
        clock = DailyClock(start: start, received: received)
        seq = start.seq
        hints = start.hints
        result = start.result
        progress = start.result?.progress ?? 0
    }

    /// Starts (or resumes) today's run of `game`, asking for the rules this app plays
    /// (`DailyGameInfo.rules`; a resumed run keeps the rules it began with). Throws
    /// `APIError.notFound` when the server has the Dish off or doesn't list the game.
    public static func begin(game: String, service: any DailyService, person: String?) async throws -> DailyRunSession {
        let rules = DailyCatalog.info(game)?.rules
        let start = try await service.start(game: game, person: person, rules: rules)
        return DailyRunSession(start: start, service: service, person: person, rules: rules)
    }

    // MARK: listening

    /// Every answer from here on, raw. Ends when the listener stops listening. If the run has
    /// already ended, the stream starts with `.ended`.
    public func events() -> AsyncStream<DailyRunEvent> {
        let (stream, continuation) = AsyncStream<DailyRunEvent>.makeStream()
        subscribe(continuation) { $0 }
        return stream
    }

    /// Every answer from here on, decoded into a game's own reveal and state types on the session.
    /// A reveal or state that doesn't decode is dropped (and a state that doesn't is a bug: the
    /// golden vectors pin both sides).
    public func events<Reveal: Decodable & Sendable, State: Decodable & Sendable>(
        reveal: Reveal.Type, state: State.Type
    ) -> AsyncStream<DailyGameEvent<Reveal, State>> {
        let (stream, continuation) = AsyncStream<DailyGameEvent<Reveal, State>>.makeStream()
        subscribe(continuation) { event -> DailyGameEvent<Reveal, State>? in
            switch event {
            case .accepted(let seq, let reveals, let progress):
                return .accepted(seq: seq, reveals: reveals.compactMap { try? $0.decoded(as: Reveal.self) }, progress: progress)
            case .hinted(let reveal, let hints, _):
                return .hinted(reveal: reveal.flatMap { try? $0.decoded(as: Reveal.self) }, hints: hints)
            case .resync(let start):
                guard let state = try? start.state.decoded(as: State.self) else { return nil }
                return .resync(state: state, seq: start.seq, hints: start.hints)
            case .ended(let result): return .ended(result)
            case .link(let link): return .link(link)
            }
        }
        return stream
    }

    private func subscribe<T: Sendable>(_ continuation: AsyncStream<T>.Continuation, map: @escaping @Sendable (DailyRunEvent) -> T?) {
        let id = nextSubscriber
        nextSubscriber += 1
        subscribers[id] = { event in
            if let mapped = map(event) { continuation.yield(mapped) }
        }
        continuation.onTermination = { _ in Task { await self.unsubscribe(id) } }
        if let result, let ended = map(.ended(result)) { continuation.yield(ended) }
    }

    private func unsubscribe(_ id: Int) { subscribers[id] = nil }

    private func emit(_ event: DailyRunEvent) {
        for subscriber in subscribers.values { subscriber(event) }
    }

    /// A game's puzzle and state from the start answer, decoded here, off the main actor.
    public nonisolated func decodeStart<Puzzle: Decodable & Sendable, State: Decodable & Sendable>(
        puzzle: Puzzle.Type, state: State.Type
    ) async throws -> (puzzle: Puzzle, state: State) {
        try await Self.decode(start, puzzle: puzzle, state: state)
    }

    @concurrent private static func decode<Puzzle: Decodable & Sendable, State: Decodable & Sendable>(
        _ start: DailyStart, puzzle: Puzzle.Type, state: State.Type
    ) async throws -> (puzzle: Puzzle, state: State) {
        (try start.puzzle.decoded(as: Puzzle.self), try start.state.decoded(as: State.self))
    }

    // MARK: moves

    /// A move the game already shows. It never waits: the session batches it. `urgent` sends it,
    /// and everything waiting before it, now.
    public func send(move: some Encodable & Sendable, urgent: Bool = false) {
        guard result == nil, let json = try? DailyJSON(move) else { return }
        enqueue(json, urgent: urgent)
    }

    /// A move the game waits on (a Sniff guess): sent at once, answered with the reveals of its
    /// batch. `.refused` means the run resyncs.
    public func play<Reveal: Decodable & Sendable>(_ move: some Encodable & Sendable, revealing: Reveal.Type) async -> DailyPlayAnswer<Reveal> {
        guard result == nil, let json = try? DailyJSON(move) else { return .refused }
        let id = enqueue(json, urgent: true)
        let reveals = await withCheckedContinuation { waiters[id] = $0 }
        guard let reveals else { return .refused }
        return .accepted(reveals.compactMap { try? $0.decoded(as: Reveal.self) })
    }

    /// Sends everything waiting now and returns once the server has answered it all.
    public func flush() async {
        if let last = queue.last { urgentThrough = last.id }
        wake()
        await settled()
    }

    @discardableResult private func enqueue(_ move: DailyJSON, urgent: Bool) -> Int {
        let id = nextID
        nextID += 1
        queue.append(Waiting(id: id, move: move, at: timer.now()))
        if urgent { urgentThrough = id }
        wake()
        return id
    }

    private func wake() {
        nap?.cancel()
        guard !pumping else { return }
        pumping = true
        Task { await self.pump() }
    }

    /// Returns once nothing is waiting or in flight (`flush` without the push; tests wait on it).
    func settled() async {
        guard pumping || !queue.isEmpty else { return }
        await withCheckedContinuation { idle.append($0) }
    }

    private func pump() async {
        while let first = queue.first, result == nil, link != .lost {
            // Wait for the batch window, unless something waiting is urgent.
            if urgentThrough == nil {
                let due = first.at + window
                if timer.now() < due {
                    let sleep = Task { [timer] in await timer.wait(until: due) }
                    nap = sleep
                    await sleep.value
                    nap = nil
                    continue
                }
            }
            let batch = Array(queue.prefix(Self.maxBatch))
            let from = seq
            guard let answer = await call({ service, run, person in
                try await service.moves(run: run, body: DailyMovesBody(from: from, moves: batch.map(\.move)), person: person)
            }) else { break }
            switch answer {
            case .accepted(let seq, let reveals, let progress, let result):
                self.seq = seq
                self.progress = progress
                queue.removeFirst(min(batch.count, queue.count))
                if let urgent = urgentThrough, !queue.contains(where: { $0.id <= urgent }) { urgentThrough = nil }
                for move in batch { waiters.removeValue(forKey: move.id)?.resume(returning: reveals) }
                emit(.accepted(seq: seq, reveals: reveals, progress: progress))
                if let result { end(result) }
            case .refused(_, _, _):
                // Illegal, stale, over, a move this app got wrong, or past the game's move budget
                // (`too_soon`: no human plays that fast): the server's run is the truth.
                await resync()
            }
        }
        pumping = false
        if result != nil || link == .lost { dropQueue() }
        let waiting = idle
        idle = []
        for continuation in waiting { continuation.resume() }
    }

    /// Calls the server, sending again after a network failure (with the same arguments, so a
    /// batch the server already took is answered the same once). Nil when the run is gone.
    private func call<T: Sendable>(_ body: @escaping @Sendable (any DailyService, String, String?) async throws -> T) async -> T? {
        var wait = retry
        while true {
            do {
                let answer = try await body(service, start.run, person)
                setLink(.ok)
                return answer
            } catch APIError.notFound {
                setLink(.lost)
                return nil
            } catch {
                setLink(.retrying)
                await timer.wait(until: timer.now() + wait)
                wait = min(wait * 2, .seconds(8))
            }
        }
    }

    private func setLink(_ next: DailyLink) {
        guard link != next else { return }
        link = next
        emit(.link(next))
    }

    private func dropQueue() {
        queue.removeAll()
        urgentThrough = nil
        let waiting = waiters
        waiters = [:]
        for continuation in waiting.values { continuation.resume(returning: nil) }
    }

    /// Starts again (the same run comes back) and hands every game the server's state.
    private func resync() async {
        dropQueue()
        guard let fresh = await call({ service, _, person in try await service.start(game: self.start.game, person: person, rules: self.rules) }) else { return }
        seq = fresh.seq
        hints = fresh.hints
        emit(.resync(fresh))
        if let result = fresh.result { end(result) }
    }

    private func end(_ result: DailyResult) {
        guard self.result == nil else { return }
        self.result = result
        progress = result.progress
        dropQueue()
        emit(.ended(result))
    }

    // MARK: hints, giving up, the TV

    /// A hint from the server: waiting moves go first, then the hint, carrying the count used so
    /// far (a resend after a dropped connection gets the same hint, once). Returns what it filled,
    /// decoded as the game's reveal, or nil when the game has none or the run has ended.
    public func hint<Reveal: Decodable & Sendable>(as reveal: Reveal.Type) async -> Reveal? {
        guard let json = await hint() else { return nil }
        return try? json.decoded(as: Reveal.self)
    }

    /// The same, raw.
    public func hint() async -> DailyJSON? {
        await flush()
        let used = hints
        guard result == nil, let answer = await call({ service, run, person in try await service.hint(run: run, hints: used, person: person) }) else {
            return nil
        }
        switch answer {
        case .accepted(_, let reveals, let progress, let result):
            hints += 1
            self.progress = progress
            emit(.hinted(reveal: reveals.first, hints: hints, progress: progress))
            if let result { end(result) }
            return reveals.first
        case .refused(.illegal, _, _):
            return nil
        case .refused:
            await resync()
            return nil
        }
    }

    /// Ends the run unsolved. Waiting moves go first. Returns the result (also sent as `.ended`).
    @discardableResult public func giveUp() async -> DailyResult? {
        await flush()
        if let result { return result }
        guard let answer = await call({ service, run, person in try await service.giveUp(run: run, person: person) }) else { return nil }
        switch answer {
        case .accepted(_, _, _, let result?):
            end(result)
        default:
            await resync()
        }
        return result
    }

    /// Show on TV: offers the run to every TV showing a board this person is on.
    public func showOnTV(_ on: Bool) async throws {
        try await service.showOnTV(run: start.run, on: on, person: person)
    }
}
