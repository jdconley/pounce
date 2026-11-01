/// Hand-made rooms for the app's DEBUG `-demo` screens, previews and UI tests.
/// Internally consistent (every visible card id unique, counts add up to the
/// deck, laid groups match their phase), so the screens never show a table the
/// server couldn't have sent.
public enum DemoFixtures {
    public static let code = "M3W7Z"
    static let names = ["Mia", "Leo", "Kiki", "Otis", "Nova", "Ziggy"]
    /// Cat per seat; 3 (gray) is the House Cat, so humans skip it.
    static let cats = [0, 1, 2, 4, 5, 6]

    /// A game in round 3 on `mySeat`'s draw step. `phase` is `mySeat`'s phase
    /// index (0 = phase 1, as in `GameView.phase`). The seat after mine has laid
    /// down phase 1; the one after that is asleep with a skip pending; at 4+
    /// seats the last seat is a bot.
    public static func table(seats: Int, mySeat: Seat, phase: Int) -> RoomView {
        let n = min(max(seats, 2), 6)
        let me = min(max(mySeat, 0), n - 1)
        let laidSeat = (me + 1) % n
        let sleepy = n >= 3 ? (me + 2) % n : nil
        let bot = n >= 4 ? n - 1 : nil

        let seatViews: [SeatView] = (0..<n).map { i in
            if i == bot && i != me { return SeatView(kind: .bot) }
            return SeatView(
                kind: .human, person: Person(id: "demo-\(i)", name: names[i], cat: cats[i]),
                yours: i == me, presence: i == sleepy ? .asleep : .awake)
        }

        var phases = (0..<n).map { (phase + 7 * $0) % 10 }
        phases[me] = min(max(phase, 0), 9)
        phases[laidSeat] = 0  // phase 1: two sets of 3

        var laid: [[Group]?] = Array(repeating: nil, count: n)
        laid[laidSeat] = laidPhaseOne
        var handCounts = Array(repeating: 10, count: n)
        handCounts[laidSeat] = 10 - laidPhaseOne.reduce(0) { $0 + $1.cards.count }
        var pendingSkip = Array(repeating: false, count: n)
        if let sleepy { pendingSkip[sleepy] = true }

        let discardTop = id(7, .gray)
        let discardCount = 6
        let laidCount = laidPhaseOne.reduce(0) { $0 + $1.cards.count }
        let deckCount = Card.deckSize - discardCount - handCounts.reduce(0, +) - laidCount

        let game = GameView(
            round: 3, dealer: (me + n - 1) % n, turn: me, step: .draw, status: .playing,
            deckCount: deckCount, discardTop: discardTop, discardCount: discardCount,
            phase: phases, scores: (0..<n).map { 5 * (($0 * 7 + 3) % 13) },
            laid: laid, handCounts: handCounts, hands: [me: myHand],
            pendingSkip: pendingSkip, winners: [])
        return RoomView(code: code, status: .playing, youAreHost: me == 0, seats: seatViews, game: game)
    }

    /// The lobby before a game: me (host), a friend on another phone, a bot, an
    /// open seat and two closed ones.
    public static func lobby() -> RoomView {
        let seats: [SeatView] = [
            SeatView(kind: .human, person: Person(id: "demo-0", name: names[0], cat: cats[0]), yours: true, presence: .awake),
            SeatView(kind: .human, person: Person(id: "demo-1", name: names[1], cat: cats[1]), yours: false, presence: .awake),
            SeatView(kind: .bot),
            SeatView(kind: .open),
            SeatView(kind: .closed),
            SeatView(kind: .closed),
        ]
        return RoomView(code: code, status: .lobby, youAreHost: true, seats: seats)
    }

    /// A pass-and-play table: seats 0 and 2 are on this phone and it is seat
    /// 0's turn, but no hand has been revealed yet (the curtain is up).
    public static func curtain() -> RoomView {
        var room = table(seats: 4, mySeat: 0, phase: 2)
        room.seats[2].yours = true
        room.seats[2].presence = .awake
        room.game?.hands[2] = secondHand
        room.game?.handCounts[2] = secondHand.count
        room.game?.pendingSkip[2] = false
        return room
    }

    /// The end of the game on `table(seats: 4, mySeat: 0, phase: 9)`: seat 0
    /// goes out finishing phase 10 and seat 1 advances, then seat 0 wins.
    public static func roundOverEvents() -> [GameEvent] {
        let base = table(seats: 4, mySeat: 0, phase: 9).game!
        let points = [0, 20, 45, 65]
        let advanced: [Seat] = [0, 1]
        let scores = zip(base.scores, points).map { $0 + $1 }
        let phase = base.phase.indices.map { base.phase[$0] + (advanced.contains($0) ? 1 : 0) }
        return [
            .roundOver(wentOut: 0, points: points, advanced: advanced, scores: scores, phase: phase),
            .gameOver(winners: [0]),
        ]
    }

    // MARK: cards

    /// First copy of a number card.
    static func id(_ value: Int, _ coat: Coat) -> CardID {
        Coat.allCases.firstIndex(of: coat)! * 24 + value - 1
    }

    /// Second copy of a number card.
    static func id2(_ value: Int, _ coat: Coat) -> CardID {
        id(value, coat) + 12
    }

    /// The mockup's hand, minus one 8: 2 1 10 4 8 12 3 11, a Yarn and a Cucumber.
    static let myHand: [CardID] = [
        id(2, .gray), id(1, .tabby), id(10, .tuxedo), id(4, .calico), id(8, .gray),
        id(12, .tabby), id(3, .calico), id(11, .tuxedo), 96, 104,
    ]

    static let secondHand: [CardID] = [
        id(5, .gray), id(6, .gray), id(9, .tabby), id(9, .tuxedo), id2(2, .calico),
        id2(11, .gray), id2(12, .tuxedo), id2(1, .tabby), 97, 105,
    ]

    /// Phase 1 laid by the seat after mine: three 7s and three 5s.
    static let laidPhaseOne: [Group] = [
        .set(cards: [id(7, .tabby), id(7, .tuxedo), id(7, .calico)], value: 7),
        .set(cards: [id2(5, .tabby), id(5, .tuxedo), id(5, .calico)], value: 5),
    ]
}
