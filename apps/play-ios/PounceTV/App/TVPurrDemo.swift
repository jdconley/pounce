#if DEBUG
import Foundation
import notify
import PounceKit

/// DEBUG Purrtrait on the TV with no server (`-demo tv-purrtrait [-seats N]`, the shell's
/// Purrtrait poster, and `-tv-preview purrtrait`): a screen's socket at a table where a drawer's
/// phone draws a cat, stroke by stroke in 50 ms batches as the phone sends them, someone gets it,
/// the word shows, and the next drawer starts. `still`: the drawing arrives whole as an `inkSync`
/// and stays (screenshots); with `-moment reveal`, the reveal too.
actor TVPurrDemoSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let feed: AsyncStream<SocketEvent>.Continuation
    private var room: RoomView
    private let seats: Int
    private let still: Bool
    private var lobby: Bool
    private var seq = 1
    private var player: Task<Void, Never>?
    private let releases: AsyncStream<Void>
    private var tokens: [Int32]

    init(seats: Int, lobby: Bool = false, still: Bool = false, code: String = DemoFixtures.code) {
        self.seats = min(max(seats, 2), 10)
        self.still = still
        self.lobby = lobby
        var room = lobby ? DemoFixtures.purrScreen(.lobby) : DemoFixtures.purrScreen(.draw, seats: self.seats)
        // A still shows the demo cat: its word's group is Animals.
        if still { room.purrtrait?.group = .animals }
        if lobby {
            room.seats = (0..<10).map { _ in SeatView(kind: .open) }
            room.near = RoomNear(key: "H4TR9WQZ", code: "\(code)H4T", expiresIn: 30_000)
        }
        room.code = code
        room.near?.code = "\(code)H4T"
        self.room = room
        (events, feed) = AsyncStream.makeStream(of: SocketEvent.self)
        let release = TVDemoSignal.release.listen()
        releases = release.posts
        tokens = [release.token]
    }

    func start() async {
        feed.yield(.connected)
        snapshot()
        if still {
            feed.yield(.message(.inkSync(turn: room.purrtrait?.turn ?? "", ops: DemoFixtures.purrCatOps)))
            if CommandLine.arguments.contains("-moment") {
                try? await Task.sleep(for: .seconds(1))
                reveal(guesser: 2)
            }
            return
        }
        player = Task { await self.run() }
    }

    func send(_ m: ClientMessage) async throws {}
    func reconnectNow() async {}

    func stop() async {
        player?.cancel()
        for token in tokens { notify_cancel(token) }
        tokens = []
        feed.finish()
    }

    private func snapshot() {
        feed.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
    }

    private func event(_ event: PurrEvent) {
        seq += 1
        feed.yield(.message(.event(seq: seq, event: .purrtrait(event))))
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: Pace.duration(.milliseconds(Int(seconds * 1000))))
        return !Task.isCancelled
    }

    private func run() async {
        if lobby {
            // The test's first go-ahead seats everyone, one cat at a time; the second starts.
            var release = releases.makeAsyncIterator()
            guard await release.next() != nil else { return }
            let full = DemoFixtures.purrScreen(.draw, seats: seats)
            for i in 0..<seats {
                guard await pause(0.3) else { return }
                room.seats[i] = full.seats[i]
                snapshot()
            }
            guard await release.next() != nil else { return }
            var next = full
            next.code = room.code
            next.near = room.near
            room = next
            lobby = false
            snapshot()
            guard await pause(1) else { return }
        }
        var turn = 0
        while !Task.isCancelled {
            guard await draw() else { return }
            guard await pause(0.8) else { return }
            reveal(guesser: (turn + 2) % seats)
            guard await pause(4) else { return }
            turn += 1
            nextTurn(turn)
            guard await pause(0.6) else { return }
        }
    }

    /// The cat, as the drawer's phone sends it: each stroke's points a few at a time, every 50 ms.
    private func draw() async -> Bool {
        guard let turn = room.purrtrait?.turn, let drawer = room.purrtrait?.drawer else { return false }
        for op in DemoFixtures.purrCatOps {
            guard case .stroke(let id, let color, let width, let start, let deltas) = op else { continue }
            var rest = deltas[...]
            let first = Array(rest.prefix(3))
            rest = rest.dropFirst(first.count)
            feed.yield(.message(.ink(seat: drawer, turn: turn, ops: [.stroke(id: id, color: color, width: width, start: start, deltas: first)])))
            while !rest.isEmpty {
                guard await pause(0.05) else { return false }
                let piece = Array(rest.prefix(3))
                rest = rest.dropFirst(piece.count)
                feed.yield(.message(.ink(seat: drawer, turn: turn, ops: [.extend(id: id, deltas: piece)])))
            }
            guard await pause(0.12) else { return false }
        }
        return true
    }

    private func reveal(guesser: Seat) {
        guard var view = room.purrtrait, let drawer = view.drawer else { return }
        view.phase = .reveal
        view.remainingMs = nil
        view.scores[guesser] += 1
        view.scores[drawer] += 1
        view.last = PurrLast(word: "cat", guesser: guesser, points: 1)
        room.purrtrait = view
        event(.guessed(drawer: drawer, guesser: guesser, points: 1, word: "cat"))
        snapshot()
    }

    private func nextTurn(_ turn: Int) {
        guard var view = room.purrtrait else { return }
        let drawer = turn % seats
        view.phase = .drawing
        view.drawer = drawer
        view.round = turn / seats % 2 + 1
        view.turn = "\(view.round):\(turn)"
        view.group = [PurrGroup.animals, .food, .outside, .things][turn % 4]
        view.remainingMs = 60_000
        view.last = nil
        room.purrtrait = view
        event(.turn(drawer: drawer, round: view.round))
        snapshot()
    }
}
#endif
