#if DEBUG
import PounceKit
import SwiftUI

/// Purrtrait's DEBUG demos (`-demo purr-<name>`, `DemoFixtures.PurrDemo`): every phone screen with
/// no server. `PurrDemoSocket` answers moves the way the server would, roughly: a pick starts the
/// drawing, Got it and Give up reveal the word, and the reveal moves on to the next drawer after a
/// few seconds. Ink goes nowhere (there is no TV).
enum PurrDemo {
    static func room(_ mode: DemoMode) -> RoomView {
        let name = mode.rawValue.replacingOccurrences(of: "purr-", with: "")
        let demo = DemoFixtures.PurrDemo(rawValue: name) ?? .draw
        let seats = CommandLine.arguments.firstIndex(of: "-seats").flatMap { CommandLine.arguments[safe: $0 + 1] }.flatMap(Int.init) ?? 4
        return DemoFixtures.purrRoom(demo, seats: seats)
    }

    static func socket(_ mode: DemoMode) -> any RoomSocketing { PurrDemoSocket(room: mode.room) }
}

actor PurrDemoSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private var room: RoomView
    private var seq = 1
    /// Ink messages taken (the frame gate's probe).
    private(set) var inkMessages = 0

    init(room: RoomView) {
        self.room = room
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    func start() async {
        continuation.yield(.connected)
        snapshot()
    }

    func reconnectNow() async {}
    func stop() async { continuation.finish() }

    private func snapshot() {
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
    }

    private func emit(_ event: PurrEvent) {
        seq += 1
        continuation.yield(.message(.event(seq: seq, event: .purrtrait(event))))
    }

    func send(_ m: ClientMessage) async throws {
        switch m {
        case .ink:
            inkMessages += 1
            return
        case .setOptions(let options):
            room.options = options
            return snapshot()
        case .start:
            guard room.status == .lobby else { return }
            room = DemoFixtures.purrRoom(.pick, seats: room.seats.filter { $0.kind == .human }.count)
            return snapshot()
        case .remove(let seat):
            if room.seats.indices.contains(seat) { room.seats[seat] = SeatView(kind: .open) }
            return snapshot()
        case .claim(let seat, let person):
            if room.seats.indices.contains(seat) { room.seats[seat] = SeatView(kind: .human, person: person, yours: true, presence: .awake) }
            return snapshot()
        case .leave(let seat):
            if room.seats.indices.contains(seat) { room.seats[seat] = SeatView(kind: .open) }
            return snapshot()
        case .actPurrtrait(let seat, let action, _):
            try? await Task.sleep(for: Pace.duration(.milliseconds(200)))
            act(seat: seat, action)
        default:
            return
        }
    }

    private func act(seat: Seat, _ action: PurrAction) {
        guard var view = room.purrtrait, let drawer = view.drawer else { return snapshot() }
        switch action {
        case .choose(let level):
            guard view.phase == .choosing, let choices = view.choices else { return snapshot() }
            view.phase = .drawing
            view.level = level
            view.group = level == .easy ? .food : .outside
            view.word = choices.word(level)
            view.choices = nil
            view.youDraw = true
            view.remainingMs = view.timer * 1000
            emit(.chosen(drawer: drawer, group: view.group ?? .food, level: level))
        case .gotIt(let guesser):
            guard view.phase == .drawing, let word = view.word else { return snapshot() }
            let points = (view.level ?? .easy).points
            view.scores[guesser] += points
            view.scores[drawer] += points
            view.phase = .reveal
            view.last = PurrLast(word: word, guesser: guesser, points: points)
            view.word = nil
            view.youDraw = false
            view.remainingMs = nil
            emit(.guessed(drawer: drawer, guesser: guesser, points: points, word: word))
            next(after: view)
        case .giveUp:
            guard view.phase == .drawing, let word = view.word else { return snapshot() }
            view.phase = .reveal
            view.last = PurrLast(word: word, guesser: nil, points: 0)
            view.word = nil
            view.youDraw = false
            view.remainingMs = nil
            emit(.missed(drawer: drawer, word: word, reason: .gaveUp))
            next(after: view)
        case .forfeit:
            if view.out.indices.contains(seat) { view.out[seat] = true }
        }
        room.purrtrait = view
        snapshot()
    }

    /// After the reveal's few seconds: the next drawer (the demo's other seats just watch).
    private func next(after view: PurrView) {
        Task {
            try? await Task.sleep(for: Pace.duration(.seconds(4)))
            await self.advance()
        }
    }

    private func advance() {
        guard var view = room.purrtrait, view.phase == .reveal else { return }
        let next = view.nextDrawer
        guard let next else {
            view.phase = .over
            view.drawer = nil
            let top = view.scores.max() ?? 0
            view.winners = view.scores.indices.filter { view.scores[$0] == top }
            room.status = .over
            room.purrtrait = view
            emit(.over(winners: view.winners, scores: view.scores))
            return snapshot()
        }
        if next < (view.drawer ?? 0) { view.round += 1 }
        view.drawer = next
        view.turn = "\(view.round):\((Int(view.turn.split(separator: ":").last ?? "0") ?? 0) + 1)"
        view.group = nil
        view.level = nil
        view.last = nil
        if room.seats[safe: next]?.yours == true {
            view.phase = .choosing
            view.remainingMs = 10_000
            view.choices = PurrChoices(easy: "rainbow", tricky: "shadow")
        } else {
            view.phase = .drawing
            view.group = .animals
            view.remainingMs = view.timer * 1000
        }
        room.purrtrait = view
        emit(.turn(drawer: next, round: view.round))
        snapshot()
    }
}
#endif
