import Foundation
import PounceKit
import Synchronization

// MARK: a network that goes dead

/// Wraps the real connector with a network that can go dead for a while, the way a phone on poor
/// cellular does: while stalled, nothing gets through and nothing fails fast. Like TCP
/// retransmitting into a dead link, sends, frames from the server and pongs are held until the
/// stall ends (lost with the socket if it is dropped first), and new connects time out. The
/// sockets themselves stay "open", so only the app's own heartbeat can tell.
final class StallingConnector: WebSocketConnector {
    private let inner = URLSessionWebSocketConnector()
    private let until = Mutex<ContinuousClock.Instant?>(nil)

    func stall(for duration: Duration) { until.withLock { $0 = .now + duration } }

    var stalled: Bool { until.withLock { $0.map { ContinuousClock.now < $0 } ?? false } }

    /// What is left of the stall.
    var remaining: Duration { until.withLock { $0.map { max(.zero, $0 - .now) } ?? .zero } }

    func connect(url: URL, token: String) async throws -> any WebSocketConnection {
        if stalled {
            // A connect into a dead network hangs until the handshake gives up.
            try await Task.sleep(for: min(remaining, .seconds(15)))
            throw SocketConnectError.failed("timed out (stalled network)")
        }
        return StallingConnection(inner: try await inner.connect(url: url, token: token), owner: self)
    }
}

final class StallingConnection: WebSocketConnection {
    let inner: any WebSocketConnection
    let owner: StallingConnector

    init(inner: any WebSocketConnection, owner: StallingConnector) {
        self.inner = inner
        self.owner = owner
    }

    func send(_ text: String) async throws {
        try await Task.sleep(for: owner.remaining)
        try await inner.send(text)
    }

    func receive() async throws -> String {
        let frame = try await inner.receive()
        try await Task.sleep(for: owner.remaining)
        return frame
    }

    func sendPing() async throws {
        try await Task.sleep(for: owner.remaining)
        try await inner.sendPing()
    }

    /// Into a dead network, a close frame never arrives either.
    func close() async { owner.stalled ? await inner.abort() : await inner.close() }

    func abort() async { await inner.abort() }
}

// MARK: the scenario

/// `scenario stall [--stall 20]`: the playtest's 20-second move. A (Ana) and B (Ben) at one
/// table, B on the real `RoomStore` and `RoomSocket` behind a `StallingConnector`. On B's turn
/// B draws, then the network goes dead and B discards at once. Prints when B's table shows
/// weak and reconnecting, when A sees B's seat turn weak and lost, when B is back, and when the
/// discard lands on A, then checks it landed exactly once.
@MainActor
func stallScenario(_ base: APIConfig, _ o: Options) async throws {
    let stallFor = Duration.seconds(o.int("stall", 20))
    let a = Device("A", config: base)
    let code = try await a.createRoom()
    _ = try await join(a, code)
    try await claim(a, seat: 0, person("Ana", cat: 1))

    let api = APIClient(config: base, credentials: MemoryCredentialStore())
    let network = StallingConnector()
    let socket = RoomSocket(code: code, config: base, credential: { try await api.credential() }, connector: network)
    let store = RoomStore(code: code, socket: socket)
    let run = Task { await store.run() }
    defer {
        run.cancel()
        Task { await store.close() }
    }
    try await until("B's first snapshot") { store.room != nil }
    store.send(.claim(seat: 1, person: person("Ben", cat: 5)))
    for _ in 0..<600 where await a.view.room?.seats[1].kind != .human {
        try await Task.sleep(for: .milliseconds(50))
    }
    try await start(a)
    try await until("the game on B") { store.phase == .playing && store.room?.link != nil }
    guard store.room?.game?.turn == 1 else { throw Failure("seat 1 should play first") }

    guard store.act(seat: 1, .draw(.deck)) else { throw Failure("B couldn't draw") }
    try await until("B's draw answered") { !store.actionInFlight && store.room?.game?.step == .play }
    guard let room = store.room, let hand = room.game?.hands[1],
          let card = Strategy.discardPick(hand: hand) else { throw Failure("B has no hand") }
    let before = await a.view
    let countBefore = before.game?.handCounts[1] ?? -1

    // The network goes dead, and B plays straight into it.
    let t0 = ContinuousClock.now
    let at = { (ContinuousClock.now - t0).formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)) }
    network.stall(for: stallFor)
    let model = TableModel(room: room)
    guard store.act(seat: 1, model.discardAction(card: card, target: model.skipTargets(for: 1).first)) else {
        throw Failure("B couldn't discard")
    }
    log("t=0 network dead for \(stallFor); B discards \(card) (pending \(store.pendingMove?.id ?? "-"))")

    var seen: Set<String> = []
    func note(_ key: String, _ line: @autoclosure () -> String) {
        guard !seen.contains(key) else { return }
        seen.insert(key)
        log("t=\(at()) \(line())")
    }
    let deadline = ContinuousClock.now + stallFor + .seconds(30)
    while ContinuousClock.now < deadline {
        let av = await a.view
        switch store.connection {
        case .weak: note("b-weak", "B's table: weak signal")
        case .reconnecting: note("b-down", "B's table: reconnecting")
        case .good: if seen.contains("b-down") { note("b-back", "B's table: connected again") }
        }
        if let link = av.room?.seats[1].link { note("a-\(link.rawValue)", "A sees Ben's seat: \(link.rawValue)") }
        if seen.contains("a-weak") || seen.contains("a-lost"), av.room?.seats[1].link == nil, av.game?.turn == 1 {
            note("a-fine", "A sees Ben's seat fine again")
        }
        if av.game?.turn == 0 {
            note("landed", "the discard landed on A (turn passed to Ana)")
            if store.pendingMove == nil, !store.actionInFlight { break }
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    let after = await a.view
    guard seen.contains("landed") else {
        let bTurn = store.room?.game.map { "turn \($0.turn) \($0.step.rawValue)" } ?? "-"
        throw Failure(
            "the discard never landed: B \(store.connection) seq \(store.lastSeq) \(bTurn) pending \(store.pendingMove?.id ?? "-") inFlight \(store.actionInFlight) acks \(store.room?.link?.acks ?? [])")
    }
    guard after.game?.handCounts[1] == countBefore - 1, after.game?.discardTop == card else {
        throw Failure("Ben's hand went \(countBefore) -> \(after.game?.handCounts[1] ?? -1); discard top \(after.game?.discardTop ?? -1)")
    }
    guard store.lastError == nil, after.errors.isEmpty else {
        throw Failure("errors: B \(store.lastError?.rawValue ?? "-"), A \(after.errors.map(\.rawValue))")
    }
    // A dead network past the 10 s heartbeat limit reconnects (and A sees Ben lost); a short
    // one only shows weak, and the held move lands when it ends.
    let expected = stallFor >= .seconds(11) ? ["b-weak", "b-down", "a-weak", "a-lost"] : ["b-weak", "a-weak"]
    for key in expected where !seen.contains(key) {
        throw Failure("never saw \(key)")
    }
    log("ok stall: the move waited out a \(stallFor) dead network and landed once")
}

/// Polls `condition` on the main actor.
@MainActor
func until(_ what: String, timeout: Double = 30, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { throw Failure("timed out waiting for \(what)") }
        try await Task.sleep(for: .milliseconds(25))
    }
}
