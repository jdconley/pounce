#if DEBUG
import Foundation
// DEBUG only: demo and test data never ships in a Release build.
/// Hand-made rooms for the app's DEBUG `-demo` screens, previews and UI tests.
/// Internally consistent (every visible card id unique, counts add up to the
/// deck, laid groups match their phase), so the screens never show a table the
/// server couldn't have sent.
public enum DemoFixtures {
    public static let code = "M3W7Z"
    /// Every demo table's name.
    public static let demoName = "Friday Night Cats"
    static let names = ["Mia", "Leo", "Kiki", "Otis", "Nova", "Ziggy"].enumerated().map { castName($0.offset, $0.element) }
    /// `POUNCE_DEMO_CAST=Jess,Sam,Grandma` in the launch environment renames the demo people in
    /// order (you, your person, then the rest of the table), for the App Store captures
    /// (`AppStore/capture.sh`). Without it every demo keeps its own names.
    static let cast: [String] = (ProcessInfo.processInfo.environment["POUNCE_DEMO_CAST"] ?? "")
        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    /// The cast's name at `index`, or `fallback` when the cast is shorter (or unset).
    public static func castName(_ index: Int, _ fallback: String) -> String {
        cast.indices.contains(index) ? cast[index] : fallback
    }
    /// Cat per seat; 3 (gray) is the House Cat, so humans skip it.
    static let cats = [0, 1, 6, 4, 5, 2]

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
        return RoomView(
            code: code, name: demoName, status: .playing, youAreHost: me == 0, seats: seatViews, game: game)
    }

    /// The busiest table the laid zone draws: six seats, every other seat laid down, with a
    /// twelve-card run, five-card sets and two-digit numbers (the DEBUG `-demo crowded`
    /// screen, for checking that laid cards stay readable on small phones).
    public static func crowded() -> RoomView {
        var room = table(seats: 6, mySeat: 0, phase: 2)
        let laid: [[Group]] = [
            [.run(cards: [id(1, .calico), id(2, .tabby), id(3, .gray), id(4, .tuxedo), 97, id(6, .calico),
                          id(7, .tabby), id(8, .tuxedo), id(9, .calico), id(10, .gray), id(11, .calico), id(12, .gray)],
                  start: 1, end: 12)],
            [.set(cards: [id(11, .tabby), id2(11, .tabby), id2(11, .tuxedo), id2(11, .calico), id(11, .gray)], value: 11),
             .set(cards: [id(12, .tuxedo), id2(12, .tuxedo), id(12, .calico)], value: 12)],
            [.coat(cards: [id2(1, .tuxedo), id2(3, .tuxedo), id2(4, .tuxedo), id(5, .tuxedo), id2(6, .tuxedo),
                           id2(9, .tuxedo), id2(10, .tuxedo)], coat: .tuxedo)],
            [.set(cards: [id(10, .tabby), id2(10, .tabby), id(10, .calico), id2(10, .gray)], value: 10),
             .run(cards: [id(3, .tabby), id(4, .tabby), id(5, .tabby), id(6, .tabby)], start: 3, end: 6)],
            [.set(cards: [id(8, .tabby), id2(8, .tabby), id(8, .calico), id2(8, .gray)], value: 8),
             .set(cards: [id(9, .tabby), id2(9, .tabby), id(9, .gray), id2(9, .gray)], value: 9)],
        ]
        room.game!.laid = [nil] + laid
        room.game!.phase = [2, 5, 9, 7, 2, 6]
        room.game!.handCounts = [myHand.count, 1, 2, 3, 2, 2]
        room.game!.pendingSkip = Array(repeating: false, count: 6)
        balance(&room.game!)
        return room
    }

    /// `crowded()` on my play step with my phase laid too (two sets of 3): six laid rows around
    /// the piles and a full hand with something for most groups (the DEBUG `-demo crowdedHit`
    /// screen, for profiling a drag over a busy laid zone).
    public static func crowdedHit() -> RoomView {
        var room = crowded()
        room.game!.step = .play
        room.game!.laid[0] = [
            .set(cards: [id2(5, .gray), id2(5, .calico), id2(5, .tabby)], value: 5),
            .set(cards: [id2(7, .gray), id2(7, .calico), id2(7, .tuxedo)], value: 7),
        ]
        room.game!.phase[0] = 0
        balance(&room.game!)
        return room
    }

    /// My play step with my phase laid (two sets) and four cards left: 2, 3, a Yarn and an 8.
    /// Leo has laid a set of 7s and the run 4-5-6-7, so the 3 fits only below the run, the 8
    /// only above, and the Yarn either end (the DEBUG `-demo hit` screen).
    public static func hitTable() -> RoomView {
        var room = table(seats: 4, mySeat: 0, phase: 0)
        let hand = [id(2, .gray), id(3, .calico), 96, id(8, .gray)]
        room.game!.step = .play
        room.game!.hands = [0: hand]
        room.game!.laid[0] = [
            .set(cards: [id2(9, .tabby), id2(9, .calico), id(9, .gray)], value: 9),
            .set(cards: [id2(10, .tabby), id2(10, .calico), id(10, .gray)], value: 10),
        ]
        room.game!.laid[1] = [
            laidPhaseOne[0],
            .run(cards: [id2(4, .gray), id2(5, .gray), id2(6, .tabby), id2(7, .calico)], start: 4, end: 7),
        ]
        room.game!.phase[1] = 1  // a set of 3 and a run of 4
        room.game!.handCounts[0] = hand.count
        room.game!.handCounts[1] = 3
        balance(&room.game!)
        return room
    }

    /// My play step on phase 2 (a set of 3, a run of 4), not laid yet: three 9s, a Yarn and
    /// 4-5-6 make the phase, so the Yarn can stand for 3 or 7 (the DEBUG `-demo lay` screen).
    public static func layTable() -> RoomView {
        var room = table(seats: 4, mySeat: 0, phase: 1)
        let hand = [id(9, .tabby), id(9, .gray), id(9, .calico), 96, id(4, .tuxedo), id(5, .gray),
                    id(6, .calico), id(11, .tabby), id(2, .gray)]
        room.game!.step = .play
        room.game!.hands = [0: hand]
        room.game!.handCounts[0] = hand.count
        balance(&room.game!)
        return room
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
        return RoomView(code: code, name: demoName, status: .lobby, youAreHost: true, seats: seats)
    }

    /// A full lobby: me (host), four more people on their own phones and a bot (the DEBUG
    /// `-demo lobbyFamily` screen, for the App Store captures).
    public static func familyLobby() -> RoomView {
        var seats: [SeatView] = (0..<5).map { i in
            SeatView(kind: .human, person: Person(id: "demo-\(i)", name: names[i], cat: cats[i]), yours: i == 0, presence: .awake)
        }
        seats.append(SeatView(kind: .bot))
        return RoomView(code: code, name: demoName, status: .lobby, youAreHost: true, seats: seats)
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

    /// The DEBUG `-demo celebrate` script, played after a `lobby()` snapshot. Each step is
    /// one server message batch (its events, then its snapshot):
    /// 0. the game starts (no events: the client plays the versus intro and the deal);
    /// 1. I lay down phase 9 and keep two cards; Kiki is down to one;
    /// 2. Kiki goes out: `roundOver` (points pop, Mia and Kiki leap a shelf);
    /// 3. the next round is dealt (`roundStarted`), as the server does 6 s later;
    /// 4. I lay down phase 10 and keep one card;
    /// 5. I discard it and go out: `roundOver`, then `gameOver` (`roundOverEvents()`).
    /// The last room is `table(seats: 4, mySeat: 0, phase: 9)` finished.
    public static func celebration() -> [ReplayStep] {
        let final = table(seats: 4, mySeat: 0, phase: 9)
        let base = final.game!
        guard case .roundOver(_, let lastPoints, _, _, let lastPhase)? = roundOverEvents().first,
              case .gameOver(let winners)? = roundOverEvents().last else { return [] }

        // Round 3 (the last) as dealt: nobody has laid down.
        var dealt = final
        dealt.game!.laid = Array(repeating: nil, count: 4)
        dealt.game!.handCounts = Array(repeating: 10, count: 4)
        balance(&dealt.game!)

        // Round 2: Kiki goes out, Mia and Kiki finish their phases.
        let points = [15, 40, 0, 15]
        let advanced: [Seat] = [0, 2]
        var start = dealt
        start.game!.round = 2
        start.game!.dealer = 2
        start.game!.turn = 3
        start.game!.phase = base.phase.indices.map { base.phase[$0] - (advanced.contains($0) ? 1 : 0) }
        start.game!.scores = zip(base.scores, points).map { $0 - $1 }
        balance(&start.game!)

        var down = start
        let mine: [Group] = [
            .set(cards: [id(6, .tabby), id(6, .tuxedo), id(6, .calico), id(6, .gray), id2(6, .tabby)], value: 6),
            .set(cards: [id(9, .gray), id2(9, .gray)], value: 9),
        ]
        let kikis: [Group] = [
            .set(cards: [id(11, .tabby), id(11, .calico), id(11, .gray), id2(11, .tabby)], value: 11),
            .run(cards: [id(1, .calico), id(2, .calico), id(3, .gray), id(4, .gray)], start: 1, end: 4),
        ]
        down.game!.laid[0] = mine
        down.game!.laid[2] = kikis
        down.game!.hands[0] = [id(2, .gray), id(10, .tuxedo)]
        down.game!.handCounts[0] = 2
        down.game!.handCounts[2] = 1
        down.game!.turn = 2
        down.game!.step = .play
        balance(&down.game!)

        var roundOver = down
        roundOver.game!.status = .roundOver
        roundOver.game!.handCounts[2] = 0
        roundOver.game!.discardTop = id2(12, .calico)
        roundOver.game!.discardCount += 1
        roundOver.game!.phase = base.phase
        roundOver.game!.scores = base.scores
        balance(&roundOver.game!)
        let kikiOut = GameEvent.roundOver(
            wentOut: 2, points: points, advanced: advanced, scores: base.scores, phase: base.phase)

        // Round 3: I lay down phase 10, then go out.
        var last = dealt
        let tens: [Group] = [
            .set(cards: [id(8, .tabby), id(8, .tuxedo), id(8, .calico), id2(8, .gray), id2(8, .tabby)], value: 8),
            .set(cards: [id2(3, .tabby), id2(3, .tuxedo), id2(3, .gray)], value: 3),
        ]
        last.game!.laid[0] = tens
        last.game!.hands[0] = [id(1, .tabby)]
        last.game!.handCounts[0] = 1
        last.game!.step = .play
        balance(&last.game!)

        var over = last
        over.status = .over
        over.game!.status = .gameOver
        over.game!.hands[0] = []
        over.game!.handCounts[0] = 0
        over.game!.discardTop = id(1, .tabby)
        over.game!.discardCount += 1
        over.game!.phase = lastPhase
        over.game!.scores = zip(base.scores, lastPoints).map { $0 + $1 }
        over.game!.winners = winners
        balance(&over.game!)

        return [
            ReplayStep(events: [], room: start),
            ReplayStep(events: [], room: down),
            ReplayStep(events: [kikiOut], room: roundOver),
            ReplayStep(events: [.roundStarted(round: 3, dealer: base.dealer)], room: dealt),
            ReplayStep(events: [], room: last),
            ReplayStep(
                events: [.discarded(seat: 0, card: id(1, .tabby), skipTarget: nil)] + roundOverEvents(), room: over),
        ]
    }

    /// Sets the deck count so every card is accounted for.
    static func balance(_ g: inout GameView) {
        let laid = g.laid.compactMap { $0 }.flatMap { $0 }.reduce(0) { $0 + $1.cards.count }
        g.deckCount = Card.deckSize - g.discardCount - g.handCounts.reduce(0, +) - laid
    }

    /// One server action in the replay: its events, then the snapshot that follows them.
    public struct ReplayStep: Equatable, Sendable {
        public let events: [GameEvent]
        public let room: RoomView

        public init(events: [GameEvent], room: RoomView) {
            self.events = events
            self.room = room
        }
    }

    /// A scripted loop over every game event kind for the DEBUG `-demo replay` screen, from
    /// `replayStart()` (4 seats, my phase 1, my turn to draw): I draw a Yarn, lay down, aim a
    /// Cucumber (two skips follow); the bot draws, lays down, hits and discards; I reshuffle
    /// and draw a Cucumber, discard; two more seats play; then a new round is dealt and the
    /// table is back at the start. Every step's room keeps the whole deck accounted for.
    public static func replay() -> [ReplayStep] {
        var room = replayStart()
        var steps: [ReplayStep] = []
        func step(_ events: [GameEvent], _ change: (inout GameView) -> Void) {
            change(&room.game!)
            steps.append(ReplayStep(events: events, room: room))
        }
        func take(_ g: inout GameView, _ seat: Seat, _ cards: [CardID]) {
            g.hands[seat]?.removeAll { cards.contains($0) }
            g.handCounts[seat] -= cards.count
        }
        func discard(_ g: inout GameView, _ seat: Seat, _ card: CardID) {
            take(&g, seat, [card])
            g.discardTop = card
            g.discardCount += 1
        }
        func draw(_ g: inout GameView, _ seat: Seat, _ card: CardID?) {
            if let card { g.hands[seat]?.append(card) }
            g.handCounts[seat] += 1
            g.deckCount -= 1
            g.step = .play
        }
        func turn(_ g: inout GameView, _ seat: Seat) {
            g.turn = seat
            g.step = .draw
        }

        let threes: Group = .set(cards: [id(3, .calico), id(3, .tabby), id(3, .tuxedo)], value: 3)
        let eights: Group = .set(cards: [id(8, .gray), id(8, .tabby), 97], value: 8)
        step([.drew(seat: 0, from: .deck, card: 97)]) { draw(&$0, 0, 97) }
        step([.laidDown(seat: 0, groups: [threes, eights])]) {
            take(&$0, 0, threes.cards + eights.cards)
            $0.laid[0] = [threes, eights]
        }
        step([.discarded(seat: 0, card: 104, skipTarget: 1), .skipped(seat: 1), .skipped(seat: 2), .turn(seat: 3)]) {
            discard(&$0, 0, 104)
            $0.pendingSkip[1] = false
            $0.pendingSkip[2] = false
            turn(&$0, 3)
        }
        step([.drew(seat: 3, from: .deck, card: nil)]) { draw(&$0, 3, nil) }
        let nines: Group = .set(cards: [id(9, .tabby), id(9, .tuxedo), id(9, .calico)], value: 9)
        let run: Group = .run(cards: [id(4, .gray), id(5, .gray), id(6, .tabby), id2(7, .calico)], start: 4, end: 7)
        step([.laidDown(seat: 3, groups: [nines, run])]) {
            $0.handCounts[3] -= 7
            $0.laid[3] = [nines, run]
        }
        let sevens: Group = .set(cards: laidPhaseOne[0].cards + [id2(7, .gray)], value: 7)
        step([.hit(seat: 3, card: id2(7, .gray), target: HitTarget(seat: 1, group: 0), group: sevens)]) {
            $0.handCounts[3] -= 1
            $0.laid[1]?[0] = sevens
        }
        step([.discarded(seat: 3, card: id2(11, .gray), skipTarget: nil), .turn(seat: 0)]) {
            discard(&$0, 3, id2(11, .gray))
            turn(&$0, 0)
        }
        let reshuffled = room.game!.deckCount + room.game!.discardCount - 1
        step([.reshuffled(deckCount: reshuffled), .drew(seat: 0, from: .deck, card: 105)]) {
            $0.deckCount = reshuffled
            $0.discardCount = 1
            draw(&$0, 0, 105)
        }
        step([.discarded(seat: 0, card: id(12, .tabby), skipTarget: nil), .turn(seat: 1)]) {
            discard(&$0, 0, id(12, .tabby))
            turn(&$0, 1)
        }
        step([.drew(seat: 1, from: .discard, card: id(12, .tabby))]) {
            $0.handCounts[1] += 1
            $0.discardTop = id2(11, .gray)
            $0.discardCount -= 1
            $0.step = .play
        }
        step([.discarded(seat: 1, card: id2(9, .calico), skipTarget: nil), .turn(seat: 2)]) {
            discard(&$0, 1, id2(9, .calico))
            turn(&$0, 2)
        }
        step([.drew(seat: 2, from: .deck, card: nil)]) { draw(&$0, 2, nil) }
        step([.discarded(seat: 2, card: id2(10, .tabby), skipTarget: nil), .turn(seat: 3)]) {
            discard(&$0, 2, id2(10, .tabby))
            turn(&$0, 3)
        }
        var next = replayStart()
        next.game?.round = 4
        steps.append(ReplayStep(events: [.roundStarted(round: 4, dealer: 3)], room: next))
        return steps
    }

    /// The replay's first table: `table(seats: 4, mySeat: 0, phase: 0)` with a hand that
    /// can make phase 1 (two sets of 3) once a Yarn is drawn.
    public static func replayStart() -> RoomView {
        var room = table(seats: 4, mySeat: 0, phase: 0)
        room.game?.hands[0] = replayHand
        return room
    }

    static let replayHand: [CardID] = [
        id(8, .gray), id(8, .tabby), id(3, .calico), id(3, .tabby), id(3, .tuxedo),
        id(12, .tabby), id(11, .tuxedo), id(1, .tabby), 104, id(10, .tuxedo),
    ]

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
#endif
