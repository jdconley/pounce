#if DEBUG
import Foundation

/// Purrtrait tables for the DEBUG demos, the TV's previews and the tests: rooms the server could
/// have sent to this phone (the word only on the drawer's device, the key only on the TV's).
extension DemoFixtures {
    public enum PurrDemo: String, CaseIterable, Sendable {
        /// My turn: two words to pick from.
        case pick
        /// I'm drawing "pizza".
        case draw
        /// Leo draws; I look at the TV.
        case watch
        /// Leo draws, and I draw next.
        case next
        /// The TV dropped: the clock stopped.
        case paused
        /// Kiki got it: the word, big.
        case reveal
        /// Nobody got it.
        case missed
        /// Game over: a tie at the top.
        case over
        /// Two seats on this phone, mine draws: the curtain is down.
        case curtain
        /// The lobby, host, three seated.
        case lobby
        /// Ten at the table, drawing (the Got it sheet is full).
        case crowd
    }

    static let purrNames = ["Mia", "Leo", "Kiki", "Otis", "Nova", "Ziggy", "Bea", "Remy", "Juno", "Pip"]
        .enumerated().map { castName($0.offset, $0.element) }

    static func purrSeats(_ n: Int, mine: Set<Seat> = [0], total: Int = 10) -> [SeatView] {
        (0..<total).map { i in
            guard i < n else { return SeatView(kind: .open) }
            let person = Person(id: "demo-\(i)", name: purrNames[i], cat: cats[i % cats.count])
            return SeatView(kind: .human, person: person, yours: mine.contains(i), presence: .awake)
        }
    }

    public static func purrLobby(seated: Int = 3, timer: Int = 60, host: Bool = true) -> RoomView {
        RoomView(
            code: code, name: demoName, status: .lobby, youAreHost: host, seats: purrSeats(seated), gameId: GameID.purrtrait,
            screen: true, options: RoomOptions(timer: timer))
    }

    /// A game of `seats` in the given state, seen from this phone (seat 0, or `mine`).
    public static func purrRoom(_ demo: PurrDemo, seats: Int = 4) -> RoomView {
        let n = demo == .crowd ? 10 : seats
        var mine: Set<Seat> = [0]
        if demo == .curtain { mine = [0, 2] }
        var view = PurrView(
            seats: n, timer: 60, phase: .drawing, round: 1, drawer: 0, order: Array(0..<n),
            scores: (0..<n).map { [3, 1, 2, 0, 4, 1, 0, 2, 1, 3][$0 % 10] }, group: .food, level: .easy,
            remainingMs: 42_000, turn: "1:3")
        switch demo {
        case .pick, .curtain:
            view.phase = .choosing
            view.group = nil
            view.level = nil
            view.remainingMs = 10_000
            view.choices = PurrChoices(easy: "pizza", tricky: "sandcastle")
        case .draw, .crowd:
            view.word = "pizza"
            view.youDraw = true
        case .watch:
            view.drawer = 1
            view.group = .animals
            view.turn = "1:1"
            view.order = Array(0..<n)
            view.round = 2
        case .next:
            view.drawer = n - 1
            view.group = .outside
            view.turn = "1:\(n - 1)"
        case .paused:
            view.drawer = 1
            view.paused = true
            view.remainingMs = 31_000
        case .reveal:
            view.phase = .reveal
            view.remainingMs = nil
            view.last = PurrLast(word: "pizza", guesser: 2, points: 1)
        case .missed:
            view.phase = .reveal
            view.drawer = 1
            view.remainingMs = nil
            view.last = PurrLast(word: "sandcastle", guesser: nil, points: 0)
        case .over:
            view.phase = .over
            view.drawer = nil
            view.round = 2
            view.remainingMs = nil
            view.scores = Array([7, 4, 7, 2].prefix(n)) + Array(repeating: 1, count: max(n - 4, 0))
            view.winners = [0, 2]
            view.last = PurrLast(word: "rainbow", guesser: 0, points: 2)
        case .lobby:
            return purrLobby()
        }
        return RoomView(
            code: code, name: demoName, status: demo == .over ? .over : .playing, youAreHost: true,
            seats: purrSeats(n, mine: mine, total: max(n, 4)), gameId: GameID.purrtrait, screen: true,
            options: RoomOptions(timer: 60), purrtrait: view)
    }

    /// The TV's view of a Purrtrait table: no word, the join key.
    public static func purrScreen(_ demo: PurrDemo, seats: Int = 4) -> RoomView {
        var room = purrRoom(demo, seats: seats)
        for i in room.seats.indices { room.seats[i].yours = false }
        room.youAreHost = false
        room.purrtrait?.choices = nil
        room.purrtrait?.word = nil
        room.purrtrait?.youDraw = false
        room.near = RoomNear(key: "H4TR9WQZ", code: "\(code)H4T", expiresIn: 30_000)
        return room
    }

    /// A drawing of a cat in a few strokes (grid units), for the TV's previews and screenshots.
    public static let purrCatOps: [InkOp] = {
        func stroke(_ id: Int, _ color: Int, _ width: Int, _ pts: [(Int, Int)]) -> InkOp {
            let points = pts.map { InkPoint($0.0, $0.1) }
            return .stroke(id: id, color: color, width: width, start: points[0],
                           deltas: InkCodec.deltas(from: points[0], through: Array(points.dropFirst())))
        }
        func circle(_ cx: Int, _ cy: Int, _ r: Int, steps: Int = 28) -> [(Int, Int)] {
            (0...steps).map { i in
                let a = Double(i) / Double(steps) * 2 * .pi
                return (cx + Int(Double(r) * cos(a)), cy + Int(Double(r) * sin(a)))
            }
        }
        return [
            stroke(0, 2, 2, circle(384, 470, 210)),
            stroke(1, 2, 2, [(214, 340), (240, 150), (330, 285)]),
            stroke(2, 2, 2, [(438, 285), (528, 150), (554, 340)]),
            stroke(3, 0, 1, circle(300, 430, 26, steps: 14)),
            stroke(4, 0, 1, circle(468, 430, 26, steps: 14)),
            stroke(5, 1, 1, [(370, 500), (398, 500), (384, 520), (370, 500)]),
            stroke(6, 0, 0, [(384, 520), (384, 560), (350, 585)]),
            stroke(7, 0, 0, [(384, 560), (418, 585)]),
            stroke(8, 0, 0, [(250, 520), (130, 505)]),
            stroke(9, 0, 0, [(252, 545), (128, 560)]),
            stroke(10, 0, 0, [(518, 520), (638, 505)]),
            stroke(11, 0, 0, [(516, 545), (640, 560)]),
            stroke(12, 5, 2, [(200, 760), (300, 720), (400, 760), (500, 720), (600, 760)]),
            stroke(13, 4, 2, [(120, 980), (180, 900), (240, 980), (300, 900), (360, 980)]),
        ]
    }()
}
#endif
