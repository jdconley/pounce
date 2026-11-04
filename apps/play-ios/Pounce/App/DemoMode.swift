#if DEBUG
import Foundation
import PounceKit

/// DEBUG launch argument `-demo <lobby|lobbyReady|table|other|replay|celebrate|curtain|handoff|peek|crowded|hit>`: opens a room fed
/// by a fake socket that sends one `DemoFixtures` snapshot, so the real screens render with no
/// server. `lobbyReady` is the lobby with no open seat, so the start pill is live. `other` is the table on another seat's turn (ring glow + paw marker, dimmed hand).
/// `replay` plays `DemoFixtures.replay()` twice through the real store and intent path
/// (events, then each action's snapshot), then stops; the scene logs its frame count each
/// second (`[replay]` on stdout) to check that the view pauses when nothing moves.
/// `nope` is my play step on a table that refuses every move (`bad_step`), to see a
/// provisional move roll back.
/// `celebrate` starts in the lobby and plays `DemoFixtures.celebration()` through the real
/// store and intent path: the versus intro and deal, a round over with two shelf leaps, the
/// next deal 6 s later (the server's gap), then my going out, the last leap and game over.
/// It logs like `replay`. `-slowmo <factor>` (any demo) runs the app at that speed (`Pace`),
/// socket gaps stretched to match, for screenshots of fast moments.
/// `curtain`: two seats on this phone and seat 0's turn, so the pass-and-play curtain is up;
/// hold the paw to show seat 0's hand.
/// `peek`: the same table on a remote seat's turn: the local cats row along the bottom; tap
/// one, hold, and that hand shows until a tap on the table.
/// `handoff`: two seats on this phone, seat 0's hand shown (the hold is skipped); seat 0 draws,
/// then discards and the turn goes to a remote seat, so the shown hand must turn face down at
/// once, not after the discard animates. Logs like `replay`.
/// `crowded`: six seats, five of them laid down with long runs and big sets (`DemoFixtures.crowded()`).
/// `hit`: my play step after laying down, with Leo's run 4-7 to hit (`DemoFixtures.hitTable()`);
/// the fake server takes each hit as the real one would and sends the event and snapshot.
enum DemoMode: String {
    case lobby, lobbyReady, table, other, replay, nope, celebrate, curtain, handoff, peek, crowded, hit

    static func from(arguments: [String] = CommandLine.arguments) -> DemoMode? {
        guard let i = arguments.firstIndex(of: "-demo"), arguments.indices.contains(i + 1) else { return nil }
        return DemoMode(rawValue: arguments[i + 1])
    }

    var room: RoomView {
        switch self {
        case .lobby: return DemoFixtures.lobby()
        case .lobbyReady:
            var room = DemoFixtures.lobby()
            room.seats[3] = SeatView(kind: .closed)
            return room
        case .table: return DemoFixtures.table(seats: 4, mySeat: 0, phase: 2)
        case .other:
            var room = DemoFixtures.table(seats: 4, mySeat: 0, phase: 2)
            room.game?.turn = 2
            return room
        case .replay: return DemoFixtures.replayStart()
        case .nope:
            var room = DemoFixtures.table(seats: 4, mySeat: 0, phase: 2)
            room.game?.step = .play
            return room
        case .celebrate: return DemoFixtures.lobby()
        case .curtain, .handoff: return DemoFixtures.curtain()
        case .peek:
            var room = DemoFixtures.curtain()
            room.game?.turn = 1
            return room
        case .crowded: return DemoFixtures.crowded()
        case .hit: return DemoFixtures.hitTable()
        }
    }

    /// `handoff`: seat 0 draws a card, then discards it and the turn passes to seat 1.
    static func handoffSteps() -> [DemoFixtures.ReplayStep] {
        var room = DemoFixtures.curtain()
        let card: CardID = 53  // 6, calico: on no hand, row or pile in the curtain table
        room.game?.hands[0]?.append(card)
        room.game?.handCounts[0] += 1
        room.game?.deckCount -= 1
        room.game?.step = .play
        let drew = DemoFixtures.ReplayStep(events: [.drew(seat: 0, from: .deck, card: card)], room: room)
        room.game?.hands[0]?.removeAll { $0 == card }
        room.game?.handCounts[0] -= 1
        room.game?.discardTop = card
        room.game?.discardCount += 1
        room.game?.turn = 1
        room.game?.step = .draw
        let passed = DemoFixtures.ReplayStep(
            events: [.discarded(seat: 0, card: card, skipTarget: nil), .turn(seat: 1)], room: room)
        return [drew, passed]
    }

    /// The fake socket behind this demo.
    func makeSocket() -> any RoomSocketing {
        switch self {
        case .replay: ReplaySocket(start: DemoFixtures.replayStart(), steps: DemoFixtures.replay(), loops: 2)
        case .handoff: ReplaySocket(start: room, steps: Self.handoffSteps(), loops: 1)
        case .celebrate: CelebrateSocket()
        case .nope: DemoSocket(room: room, refusing: true)
        case .hit: DemoSocket(room: room, hits: true)
        default: DemoSocket(room: room)
        }
    }
}

/// `-demo celebrate`: the lobby, then each `DemoFixtures.celebration()` step (its events, then
/// its snapshot) after the gap before it. The gaps follow the real server: the next round is
/// dealt 6 s after `roundOver`.
actor CelebrateSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private var player: Task<Void, Never>?
    /// Seconds before each step: start, lay down, Kiki out, next deal, lay down, go out.
    static let gaps: [Double] = [1.5, 4.5, 1.6, 6, 3.5, 1.4]

    init() {
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    func start() async {
        continuation.yield(.connected)
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: DemoFixtures.lobby())))
        guard player == nil else { return }
        let continuation = continuation
        player = Task {
            var seq = 1
            for (i, step) in DemoFixtures.celebration().enumerated() {
                try? await Task.sleep(for: .seconds(Pace.seconds(Self.gaps[i % Self.gaps.count])))
                guard !Task.isCancelled else { return }
                print("[celebrate] step \(i) events=\(step.events.count)")
                for event in step.events {
                    seq += 1
                    continuation.yield(.message(.event(seq: seq, event: .game(event))))
                }
                if step.events.isEmpty { seq += 1 }
                continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: step.room)))
            }
            print("[celebrate] done")
        }
    }

    func send(_ m: ClientMessage) async throws {}

    func reconnectNow() async {}

    func stop() async {
        player?.cancel()
        continuation.finish()
    }
}

/// `-demo replay` / `handoff`: the start snapshot, then every step (its events, then its
/// snapshot, seqs counting up like the server's) every `gap`, `loops` times over.
actor ReplaySocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private let startRoom: RoomView
    private let steps: [DemoFixtures.ReplayStep]
    private let loops: Int
    private var player: Task<Void, Never>?
    static let gap: Duration = .milliseconds(1300)

    init(start: RoomView, steps: [DemoFixtures.ReplayStep], loops: Int) {
        startRoom = start
        self.steps = steps
        self.loops = loops
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    func start() async {
        continuation.yield(.connected)
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: startRoom)))
        guard player == nil else { return }
        let continuation = continuation
        let loops = loops
        let steps = steps
        player = Task {
            var seq = 1
            try? await Task.sleep(for: .seconds(Pace.seconds(2)))
            for loop in 0..<loops {
                print("[replay] loop \(loop + 1) start")
                for step in steps {
                    guard !Task.isCancelled else { return }
                    for event in step.events {
                        seq += 1
                        continuation.yield(.message(.event(seq: seq, event: .game(event))))
                    }
                    continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: step.room)))
                    try? await Task.sleep(for: Pace.duration(Self.gap))
                }
            }
            print("[replay] done")
        }
    }

    func send(_ m: ClientMessage) async throws {}

    func reconnectNow() async {}

    func stop() async {
        player?.cancel()
        continuation.finish()
    }
}

extension TableScene {
    private static let logsTimeline = [.replay, .nope, .celebrate, .handoff].contains(DemoMode.from())
    /// `-log-timeline` (any table, e.g. a UI test against the dev server): the same lines to the
    /// unified log (`log stream --predicate 'eventMessage CONTAINS "[timeline]"'`).
    static let logsTimelineToSystem = CommandLine.arguments.contains("-log-timeline")

    /// `-demo replay`: one line per game intent (played with its duration, or skipped).
    func timelineLog(_ line: @autoclosure () -> String) {
        if Self.logsTimeline { print("[timeline] \(line())") }
        if Self.logsTimelineToSystem { NSLog("[timeline] %@", line()) }
    }

    /// `-demo replay`: prints the rendered frame count once a second (a Task, so it never
    /// wakes the view itself).
    func startFrameLog() {
        let director = director
        let clock = ContinuousClock()
        let start = clock.now
        Task { [weak self] in
            var last = director.framesRendered
            while self != nil {
                try? await Task.sleep(for: .seconds(1))
                let frames = director.framesRendered
                let t = (clock.now - start).components.seconds
                print("[replay] t=\(t)s frames=\(frames) +\(frames - last) paused=\(self?.view?.isPaused ?? true)")
                last = frames
            }
        }
    }
}

/// A room socket that connects at once, sends one snapshot and ignores everything sent to it
/// (or, `refusing`, answers every game action with `bad_step` after a moment).
actor DemoSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private var room: RoomView
    private let refusing: Bool
    /// Takes hits like the server: the card joins the group (on the `side` asked for), then
    /// the `hit` event and a snapshot.
    private let hits: Bool
    private var seq = 1

    init(room: RoomView, refusing: Bool = false, hits: Bool = false) {
        self.room = room
        self.refusing = refusing
        self.hits = hits
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    func start() async {
        continuation.yield(.connected)
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
    }

    func send(_ m: ClientMessage) async throws {
        if hits, case .act(let seat, .hit(let card, let target, let side)) = m { return hit(seat: seat, card: card, target: target, side: side) }
        guard refusing, case .act = m else { return }
        try? await Task.sleep(for: Pace.duration(.milliseconds(400)))
        continuation.yield(.message(.error(.badStep)))
    }

    func reconnectNow() async {}

    func stop() async {
        continuation.finish()
    }

    private func hit(seat: Seat, card: CardID, target: HitTarget, side: HitSide?) {
        guard var game = room.game, var groups = game.laid[safe: target.seat] ?? nil, groups.indices.contains(target.group),
              let group = Rules.canHit(groups[target.group], card: card, side: side) else {
            continuation.yield(.message(.error(.badTarget)))
            return
        }
        groups[target.group] = group
        game.laid[target.seat] = groups
        game.hands[seat]?.removeAll { $0 == card }
        game.handCounts[seat] -= 1
        room.game = game
        seq += 1
        continuation.yield(.message(.event(seq: seq, event: .game(.hit(seat: seat, card: card, target: target, group: group)))))
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
    }
}
#endif
