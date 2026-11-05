// pounce-e2e: drives real games against a play-api server (default the local dev server)
// over the same PounceKit networking the app uses. macOS only; credentials live in memory.
//
//   pounce-e2e full [--local 2] [--bots 2] [--timeout 1800]
//                   [--move-seats 1,2 --move-at-phase 8 --move-file PATH]
//       (once any seat reaches that phase index, those local seats are offered to other phones
//        with moveSeat; one line per seat goes to PATH: "<seat> pounce-dev://j/<CODE>?move=<M>")
//   pounce-e2e join <CODE> [--name Remote] [--cat 4] [--drop-after N [--reconnect-after 3 | --reconnect-file PATH]] [--quit-after N] [--timeout 1800]
//       (--reconnect-file: stay away until PATH exists, so a slow UI test can't miss the away)
//   pounce-e2e scenario presence|reconnect|move
//   pounce-e2e peek <CODE>            (one snapshot as a seatless device: turn, step, seats)
//
// Every mode takes `--base <url>` (default http://localhost:8787). Exit 0 on success, 1 with a
// one-line reason on failure, 2 on bad usage.
import Foundation
import PounceKit

// MARK: output

func log(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: options

struct Options {
    var positional: [String] = []
    var flags: [String: String] = [:]

    init(_ args: ArraySlice<String>) {
        var it = args.makeIterator()
        while let arg = it.next() {
            if arg.hasPrefix("--") {
                flags[String(arg.dropFirst(2))] = it.next() ?? ""
            } else {
                positional.append(arg)
            }
        }
    }

    func int(_ key: String, _ fallback: Int) -> Int { flags[key].flatMap(Int.init) ?? fallback }
    func string(_ key: String, _ fallback: String) -> String { flags[key] ?? fallback }
}

// MARK: one device

/// What a device knows right now (a copy, safe to inspect off the actor).
struct DeviceView: Sendable {
    var room: RoomView?
    var seq = 0
    var snapshots = 0
    var errors: [ErrorCode] = []
    var events: [RoomEvent] = []
    var moveCodes: [Seat: String] = [:]
    var connected = false
    var gone: SocketEvent?

    var game: GameView? { room?.game }
    var mySeats: [Seat] { room.map { r in r.seats.indices.filter { r.seats[$0].yours } } ?? [] }
    var hands: [Seat: [CardID]] { game?.hands ?? [:] }

    /// The presence events seen for `seat`, in order.
    func presence(of seat: Seat) -> [Presence] {
        events.compactMap {
            if case .presence(let s, let p) = $0, s == seat { return p }
            return nil
        }
    }
}

/// A phone: one device credential (minted on first use) and at most one live room socket.
/// Replacing the socket (a drop and reconnect) ignores anything the old one still emits.
actor Device {
    let name: String
    let config: APIConfig
    let api: APIClient
    private var socket: RoomSocket?
    private var pump: Task<Void, Never>?
    private var state = DeviceView()
    private var generation = 0

    init(_ name: String, config: APIConfig) {
        self.name = name
        self.config = config
        api = APIClient(config: config, credentials: MemoryCredentialStore())
    }

    var view: DeviceView { state }

    func createRoom() async throws -> String { try await api.createRoom() }

    func connect(_ code: String) async {
        generation += 1
        let gen = generation
        let api = api
        let s = RoomSocket(code: code, config: config, credential: { try await api.credential() })
        socket = s
        pump = Task { [weak self] in
            for await event in s.events { await self?.handle(event, gen: gen) }
        }
        await s.start()
    }

    /// Closes the socket for good (the server sees a disconnect).
    func drop() async {
        generation += 1
        let s = socket
        socket = nil
        state.connected = false
        pump?.cancel()
        pump = nil
        await s?.stop()
    }

    func send(_ message: ClientMessage) async throws {
        guard let socket else { throw Failure("\(name): send without a socket") }
        try await socket.send(message)
    }

    private func handle(_ event: SocketEvent, gen: Int) {
        guard gen == generation else { return }
        switch event {
        case .connecting, .disconnected:
            state.connected = false
        case .connected:
            state.connected = true
        case .notFound, .closed:
            state.gone = event
        case .message(let message):
            switch message {
            case .snapshot(_, let seq, let room):
                state.room = room
                state.seq = seq
                state.snapshots += 1
            case .unsupportedProtocol(let version):
                state.errors.append(ErrorCode(rawValue: "unsupported_protocol_\(version)"))
            case .event(let seq, let roomEvent):
                state.seq = seq
                state.events.append(roomEvent)
                report(roomEvent)
            case .moveCode(let seat, let code):
                state.moveCodes[seat] = code
            case .error(let code):
                state.errors.append(code)
            case .streak, .rematch:
                break
            }
        }
    }

    private func report(_ event: RoomEvent) {
        switch event {
        case .game(.roundOver(let wentOut, let points, let advanced, let scores, let phase)):
            log("[\(name)] roundOver wentOut=\(wentOut.map(String.init) ?? "-") points=\(points) advanced=\(advanced) scores=\(scores) phase=\(phase)")
        case .game(.gameOver(let winners)):
            log("[\(name)] gameOver winners=\(winners)")
        case .game(.roundStarted(let round, let dealer)):
            log("[\(name)] roundStarted round=\(round) dealer=\(dealer)")
        case .presence(let seat, let presence):
            log("[\(name)] presence seat=\(seat) \(presence.rawValue)")
        default:
            break
        }
    }
}

// MARK: waiting and acting

@discardableResult
func wait(
    _ device: Device, _ what: String, timeout: Double = 30, _ ok: (DeviceView) -> Bool
) async throws -> DeviceView {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        let v = await device.view
        if ok(v) { return v }
        if let gone = v.gone { throw Failure("\(device.name): room gone (\(gone)) while waiting for \(what)") }
        if Date() > deadline { throw Failure("\(device.name): timed out after \(Int(timeout)) s waiting for \(what)") }
        try await Task.sleep(for: .milliseconds(25))
    }
}

/// Sends `message` and waits for its answer: the next snapshot (R13: every successful change
/// ends with each device's own snapshot) or an error. Returns the error, if any.
@discardableResult
func request(_ device: Device, _ message: ClientMessage, timeout: Double = 20) async throws -> ErrorCode? {
    let before = await device.view
    try await device.send(message)
    let after = try await wait(device, "answer to \(message)", timeout: timeout) {
        $0.snapshots > before.snapshots || $0.errors.count > before.errors.count
    }
    return after.errors.count > before.errors.count ? after.errors.last : nil
}

func act(_ device: Device, seat: Seat, _ action: Action) async throws {
    if let error = try await request(device, .act(seat: seat, action: action)) {
        throw Failure("\(device.name): seat \(seat) \(action) refused with \(error.rawValue)")
    }
}

// MARK: strategy

enum Strategy {
    /// The next move for `seat` on its turn: draw (the discard top when it completes the phase,
    /// else the deck), lay down when `Solver.findPhase` finds the phase, hit while
    /// `Solver.hits` finds one, then discard the highest-points non-Yarn card (a Cucumber
    /// aimed at the first skip target). Nil when it isn't `seat`'s turn.
    static func next(room: RoomView, seat: Seat) -> Action? {
        guard room.status == .playing, let game = room.game, game.status == .playing, game.turn == seat,
              let hand = game.hands[seat], game.phase.indices.contains(seat) else { return nil }
        let phase = game.phase[seat]
        let laid = (game.laid[safe: seat] ?? nil) != nil
        switch game.step {
        case .draw:
            if !laid, let top = game.discardTop, Card(id: top) != .cucumber,
               Solver.findPhase(hand: hand + [top], phaseIndex: phase) != nil {
                return .draw(.discard)
            }
            return .draw(.deck)
        case .play:
            if !laid, let groups = Solver.findPhase(hand: hand, phaseIndex: phase) {
                return .layDown(groups)
            }
            if laid, let hit = Solver.hits(hand: hand, laid: game.laid).first {
                return .hit(card: hit.card, target: hit.target)
            }
            guard let pick = discardPick(hand: hand) else { return nil }
            let model = TableModel(room: room)
            return model.discardAction(card: pick, target: model.skipTargets(for: seat).first)
        }
    }

    /// The highest-points non-Yarn card (any card if only Yarn is left).
    static func discardPick(hand: [CardID]) -> CardID? {
        let pool = hand.filter { Card(id: $0) != .yarn }
        return (pool.isEmpty ? hand : pool).max { (Card.points($0), $0) < (Card.points($1), $1) }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: playing a game

struct Summary {
    var rounds = 0
    var winners: [Seat] = []
    var phases: [Int] = []

    var line: String {
        "rounds=\(rounds) winners=\(winners.map(String.init).joined(separator: ",")) phases=\(phases.map(String.init).joined(separator: ","))"
    }
}

/// Plays every turn of the seats `device` holds until game over. `afterAct(n)` runs after the
/// device's n-th action (drop/quit hooks); returning false stops playing (Summary nil).
/// `tick` runs on every poll (the move hook).
func play(
    _ device: Device, timeout: Double, stallAfter: Double = 90,
    tick: (DeviceView) async throws -> Void = { _ in },
    afterAct: (Int) async throws -> Bool = { _ in true }
) async throws -> Summary? {
    let deadline = Date().addingTimeInterval(timeout)
    var acts = 0
    var lastSeq = -1
    var lastChange = Date()
    var seenErrors = await device.view.errors.count
    while true {
        let v = await device.view
        if let gone = v.gone { throw Failure("\(device.name): room gone (\(gone)) mid-game") }
        if v.errors.count > seenErrors {
            let new = v.errors[seenErrors...].map(\.rawValue).joined(separator: ",")
            throw Failure("\(device.name): unexpected error(s) \(new)")
        }
        seenErrors = v.errors.count
        if let game = v.game, game.status == .gameOver || v.room?.status == .over {
            return Summary(rounds: game.round, winners: game.winners, phases: game.phase)
        }
        if v.seq != lastSeq {
            lastSeq = v.seq
            lastChange = Date()
        } else if Date().timeIntervalSince(lastChange) > stallAfter {
            throw Failure("\(device.name): stalled at seq \(v.seq) for \(Int(stallAfter)) s (turn \(v.game.map { String($0.turn) } ?? "-"))")
        }
        if Date() > deadline { throw Failure("\(device.name): game not over after \(Int(timeout)) s") }
        try await tick(v)
        if await device.view.errors.count > seenErrors { continue }

        if v.connected, let room = v.room, let game = room.game, v.mySeats.contains(game.turn),
           let action = Strategy.next(room: room, seat: game.turn) {
            try await act(device, seat: game.turn, action)
            acts += 1
            if try await !afterAct(acts) { return nil }
            seenErrors = await device.view.errors.count
        } else {
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

func person(_ name: String, cat: Int) -> Person {
    Person(id: UUID().uuidString.lowercased(), name: name, cat: cat)
}

/// Connects `device` to `code` and waits for its first snapshot.
func join(_ device: Device, _ code: String) async throws -> DeviceView {
    let before = await device.view.snapshots
    await device.connect(code)
    return try await wait(device, "snapshot of \(code)") { $0.connected && $0.snapshots > before }
}

func claim(_ device: Device, seat: Seat, _ who: Person) async throws {
    if let error = try await request(device, .claim(seat: seat, person: who)) {
        throw Failure("\(device.name): claim seat \(seat) refused with \(error.rawValue)")
    }
}

func configure(_ device: Device, seat: Seat, _ kind: ConfigureKind) async throws {
    if let error = try await request(device, .configure(seat: seat, kind: kind)) {
        throw Failure("\(device.name): configure seat \(seat) \(kind) refused with \(error.rawValue)")
    }
}

func start(_ device: Device) async throws {
    if let error = try await request(device, .start) {
        throw Failure("\(device.name): start refused with \(error.rawValue)")
    }
    try await wait(device, "the game to start") { $0.room?.status == .playing && $0.game != nil }
}

// MARK: modes

/// One device, `local` pass-and-play seats, `bots` bot seats, played to game over.
func full(_ base: APIConfig, _ o: Options) async throws {
    let local = o.int("local", 2)
    let bots = o.int("bots", 2)
    let timeout = Double(o.int("timeout", 1800))
    guard local >= 1, local + bots >= 2, local + bots <= 6 else { throw Failure("need 1+ local, 2–6 players") }
    let host = Device("host", config: base)
    let code = try await host.createRoom()
    log("room \(code)")
    _ = try await join(host, code)
    for seat in 0..<local {
        if seat >= 2 { try await configure(host, seat: seat, .open) }
        try await claim(host, seat: seat, person("Local\(seat + 1)", cat: seat))
    }
    for seat in local..<(local + bots) { try await configure(host, seat: seat, .bot) }
    for seat in (local + bots)..<6 where await host.view.room?.seats[seat].kind == .open {
        try await configure(host, seat: seat, .closed)
    }
    try await start(host)
    log("started: \(local) local, \(bots) bots")
    let moveSeats = (o.flags["move-seats"] ?? "").split(separator: ",").compactMap { Int($0) }
    let moveAt = o.int("move-at-phase", 8)
    let moveFile = o.flags["move-file"]
    var moved = moveSeats.isEmpty
    let tick: (DeviceView) async throws -> Void = { v in
        guard !moved, let game = v.game, game.status == .playing, (game.phase.max() ?? 0) >= moveAt else { return }
        moved = true
        var lines: [String] = []
        for seat in moveSeats {
            try await host.send(.moveSeat(seat: seat))
            let withCode = try await wait(host, "a move code for seat \(seat)") { $0.moveCodes[seat] != nil }
            let link = "pounce-dev://j/\(code)?move=\(withCode.moveCodes[seat]!)"
            lines.append("\(seat) \(link)")
            log("move seat \(seat): \(link)")
        }
        if let moveFile { try (lines.joined(separator: "\n") + "\n").write(toFile: moveFile, atomically: true, encoding: .utf8) }
    }
    // Moved seats are played by people tapping on simulators: allow them time.
    guard let summary = try await play(host, timeout: timeout, stallAfter: moveSeats.isEmpty ? 90 : 900, tick: tick)
    else { throw Failure("stopped early") }
    log(summary.line)
}

/// A remote human on its own phone: claims the first open seat of an app-made room and plays.
func joinMode(_ base: APIConfig, _ o: Options) async throws {
    guard let code = o.positional.first?.uppercased(), RoomCode.isValid(code) else {
        throw Failure("usage: join <CODE> [--name Remote] [--cat 4] [--drop-after N [--reconnect-after S]] [--quit-after N]")
    }
    let name = o.string("name", "Remote")
    let cat = o.int("cat", 4)
    let dropAfter = o.int("drop-after", 0)
    let quitAfter = o.int("quit-after", 0)
    let reconnectAfter = o.int("reconnect-after", 3)
    let reconnectFile = o.flags["reconnect-file"]
    let timeout = Double(o.int("timeout", 1800))
    let me = person(name, cat: cat)
    let remote = Device("remote", config: base)
    _ = try await join(remote, code)
    log("joined \(code)")

    // Claim the first open seat; a refusal (someone else took it) retries on the next snapshot.
    var claimed = false
    let claimDeadline = Date().addingTimeInterval(120)
    while !claimed {
        let v = await remote.view
        guard let room = v.room else { throw Failure("no room") }
        if !v.mySeats.isEmpty { claimed = true; break }
        guard room.status == .lobby else { throw Failure("the game started without a seat for \(name)") }
        if let open = room.seats.firstIndex(where: { $0.kind == .open }) {
            if try await request(remote, .claim(seat: open, person: me)) == nil {
                log("claimed seat \(open) as \(name)")
                claimed = true
            }
        } else {
            let seen = v.snapshots
            if Date() > claimDeadline { throw Failure("no open seat for \(name)") }
            try await wait(remote, "an open seat", timeout: 120) { $0.snapshots > seen }
        }
    }
    try await wait(remote, "the game to start", timeout: 600) { $0.room?.status == .playing }
    log("game started; seat \(await remote.view.mySeats)")

    let summary = try await play(remote, timeout: timeout, stallAfter: 600, afterAct: { n in
        if n == quitAfter {
            log("quitting after action \(n)")
            await remote.drop()
            return false
        }
        if n == dropAfter {
            let seq = await remote.view.seq
            log("dropping the socket after action \(n) (seq \(seq))")
            await remote.drop()
            if let reconnectFile {
                log("waiting for \(reconnectFile)")
                let until = Date().addingTimeInterval(1800)
                while !FileManager.default.fileExists(atPath: reconnectFile), Date() < until {
                    try await Task.sleep(for: .milliseconds(200))
                }
            } else {
                try await Task.sleep(for: .seconds(reconnectAfter))
            }
            let v = try await join(remote, code)
            log("reconnected: snapshot seq \(v.seq), step \(v.game?.step.rawValue ?? "-")")
        }
        return true
    })
    if let summary { log(summary.line) }
}

/// Two minted devices in one room, seat 0 on `a` and seat 1 on `b`.
func pair(_ base: APIConfig) async throws -> (a: Device, b: Device, code: String) {
    let a = Device("A", config: base)
    let b = Device("B", config: base)
    let code = try await a.createRoom()
    _ = try await join(a, code)
    try await claim(a, seat: 0, person("Ana", cat: 1))
    _ = try await join(b, code)
    try await claim(b, seat: 1, person("Ben", cat: 5))
    try await wait(a, "seat 1 taken") { $0.room?.seats[1].kind == .human }
    return (a, b, code)
}

/// Plays `device`'s turns (draw deck, discard) until it is `seat`'s turn on `watcher`.
func playUntilTurn(of seat: Seat, mover: Device, watcher: Device) async throws {
    while true {
        let v = try await wait(watcher, "a turn") { $0.game?.status == .playing }
        if v.game?.turn == seat && v.game?.step == .draw { return }
        let m = try await wait(mover, "mover's turn", timeout: 30) { mv in
            guard let g = mv.game else { return false }
            return mv.mySeats.contains(g.turn) || g.turn == seat
        }
        guard let room = m.room, let game = room.game, m.mySeats.contains(game.turn), game.turn != seat,
              let action = Strategy.next(room: room, seat: game.turn) else { continue }
        try await act(mover, seat: game.turn, action)
    }
}

func scenario(_ base: APIConfig, _ o: Options) async throws {
    switch o.positional.first {
    case "presence":
        let (a, b, _) = try await pair(base)
        try await a.send(.presence(.background))
        try await wait(b, "seat 0 away after background") { $0.presence(of: 0).last == .away }
        try await a.send(.presence(.active))
        try await wait(b, "seat 0 awake after active") { $0.presence(of: 0).last == .awake }
        await a.drop()
        try await wait(b, "seat 0 away after disconnect") { $0.presence(of: 0).last == .away }
        let seatView = try await wait(b, "lobby snapshot") { $0.room != nil }
        _ = seatView
        _ = try await join(a, (await a.view.room?.code) ?? "")
        try await wait(b, "seat 0 awake after reconnect") { $0.presence(of: 0).last == .awake }
        log("ok presence: background→away, active→awake, disconnect→away, reconnect→awake (\(await b.view.presence(of: 0).map(\.rawValue)))")

    case "reconnect":
        let (a, b, code) = try await pair(base)
        try await start(a)
        try await wait(b, "the game on B") { $0.room?.status == .playing }
        try await playUntilTurn(of: 0, mover: b, watcher: a)
        let before = await a.view
        guard let hand = before.hands[0] else { throw Failure("A has no hand") }
        try await act(a, seat: 0, .draw(.deck))
        let drawn = await a.view
        guard let newHand = drawn.hands[0], newHand.count == hand.count + 1,
              let card = newHand.first(where: { !hand.contains($0) }) else { throw Failure("draw didn't add a card") }
        // Mid-turn: drop the socket, wait, reconnect, and expect the snapshot at the same seq.
        await a.drop()
        try await Task.sleep(for: .seconds(1.5))
        let back = try await join(a, code)
        // The drop and the return are presence events (away, awake), each with its own seq; the
        // reconnect snapshot already includes them, so it matches what B last saw.
        let bv = try await wait(b, "seat 0 awake again") { $0.presence(of: 0).last == .awake && $0.seq >= back.seq }
        guard back.seq == bv.seq, back.seq >= drawn.seq else {
            throw Failure("reconnect snapshot seq \(back.seq) vs B's \(bv.seq) (drew at \(drawn.seq))")
        }
        guard back.game?.step == .play, back.game?.turn == 0, back.hands[0]?.contains(card) == true else {
            throw Failure("reconnect snapshot lost the drawn card or the play step")
        }
        let model = TableModel(room: back.room!)
        try await act(a, seat: 0, model.discardAction(card: card, target: model.skipTargets(for: 0).first))
        let after = await a.view
        guard after.game?.turn == 1 || after.game?.status != .playing else {
            throw Failure("turn didn't pass after the discard")
        }
        log("ok reconnect: drew \(card) at seq \(drawn.seq), dropped, snapshot seq \(back.seq) kept it, discard accepted (seq \(after.seq))")

    case "move":
        let a = Device("A", config: base)
        let b = Device("B", config: base)
        let code = try await a.createRoom()
        _ = try await join(a, code)
        try await claim(a, seat: 0, person("Ana", cat: 1))
        try await claim(a, seat: 1, person("Ben", cat: 5))
        try await start(a)
        guard Set(await a.view.hands.keys) == [0, 1] else { throw Failure("A doesn't hold both hands") }
        _ = try await join(b, code)
        guard await b.view.hands.isEmpty else { throw Failure("B sees a hand before the move") }
        try await a.send(.moveSeat(seat: 1))
        let withCode = try await wait(a, "a move code") { $0.moveCodes[1] != nil }
        let moveCode = withCode.moveCodes[1]!
        if let error = try await request(b, .claimMove(code: moveCode)) {
            throw Failure("claimMove refused with \(error.rawValue)")
        }
        let bv = try await wait(b, "seat 1 on B") { $0.mySeats == [1] }
        let av = try await wait(a, "seat 1 gone from A") { $0.mySeats == [0] }
        guard Set(av.hands.keys) == [0] else { throw Failure("A still sees hands \(av.hands.keys.sorted())") }
        guard Set(bv.hands.keys) == [1], bv.hands[1]?.count == bv.game?.handCounts[1] else {
            throw Failure("B got hands \(bv.hands.keys.sorted())")
        }
        // The new device can play seat 1: run turns on both phones until B has acted.
        var bActed = false
        let deadline = Date().addingTimeInterval(60)
        while !bActed {
            if Date() > deadline { throw Failure("B never got to act for seat 1") }
            for d in [a, b] {
                let v = await d.view
                guard let room = v.room, let game = room.game, v.mySeats.contains(game.turn),
                      let action = Strategy.next(room: room, seat: game.turn) else { continue }
                try await act(d, seat: game.turn, action)
                if d === b { bActed = true }
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        if await a.view.errors.isEmpty == false { throw Failure("A got errors \(await a.view.errors)") }
        log("ok move: code \(moveCode) moved seat 1 to B; A holds hands [0], B holds [1] and acted for it")

    default:
        throw Failure("usage: scenario presence|reconnect|move")
    }
}

/// Prints what a seatless device sees of a room: status, turn, step, hand counts, presence.
func peek(_ base: APIConfig, _ o: Options) async throws {
    guard let code = o.positional.first?.uppercased() else { throw Failure("usage: peek <CODE>") }
    let d = Device("peek", config: base)
    let v = try await join(d, code)
    guard let room = v.room else { throw Failure("no room") }
    let seats = room.seats.enumerated().map { i, s in
        "\(i):\(s.kind.rawValue)\(s.person.map { "(\($0.name))" } ?? "")\(s.presence.map { "/\($0.rawValue)" } ?? "")"
    }
    log("room \(room.code) \(room.status.rawValue) seq \(v.seq) seats \(seats.joined(separator: " "))")
    if let g = room.game {
        log("round \(g.round) \(g.status.rawValue) turn \(g.turn) step \(g.step.rawValue) hands \(g.handCounts) phase \(g.phase) laid \(g.laid.map { $0 != nil })")
    }
    await d.drop()
}

// MARK: main

let args = CommandLine.arguments
let options = Options(args.dropFirst(2))
guard let mode = args[safe: 1], let base = URL(string: options.string("base", "http://localhost:8787")) else {
    log("usage: pounce-e2e full|join <CODE>|scenario <name> [--base URL] …  (protocol \(PounceKit.protocolVersion))")
    exit(2)
}
let config = APIConfig(baseURL: base)
do {
    switch mode {
    case "full": try await full(config, options)
    case "join": try await joinMode(config, options)
    case "scenario": try await scenario(config, options)
    case "peek": try await peek(config, options)
    default:
        log("unknown mode \(mode)")
        exit(2)
    }
    exit(0)
} catch {
    log("FAIL \(error)")
    exit(1)
}
