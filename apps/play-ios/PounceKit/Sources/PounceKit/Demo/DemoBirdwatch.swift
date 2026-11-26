#if DEBUG
import Foundation

/// Birdwatch tables for the DEBUG demos, the TV's previews and the tests. Each is a room the
/// server could have sent: every card once, counts that add up, the choice fields only for the
/// seat on the move on this device.
extension DemoFixtures {
    public enum BirdDemo: String, CaseIterable, Sendable {
        /// Kiki bid 75; my move, 80 to 120.
        case bid
        /// I won at 85: the feeder's five cards are in my hand to put five back.
        case nest
        /// Naming trump.
        case trump
        /// Mid hand, trump is feathers; Leo led fish and two followed; my move, fish only.
        case play
        /// Mid hand, Leo's move: I watch.
        case watch
        /// Five players, Tucker: I won the bid and call a partner.
        case partner
        /// Five players: I hold the called card (the partner mark on my hand).
        case partnerMark = "partner-mark"
        /// Six players, Friesen, bidding; a House Cat plays for Otis, who left.
        case six
        /// Between hands: the summary.
        case between
        /// Game over.
        case over
        /// Two seats on this phone: the curtain is up for seat 0.
        case curtain
    }

    public static func birdID(_ suit: BirdSuit, _ rank: Int) -> BirdCardID { suit.index * 14 + rank - 1 }

    static func birdSeats(_ n: Int, mine: Set<Seat> = [0], leftSeat: Seat? = nil, bot: Seat? = nil) -> [SeatView] {
        (0..<n).map { i in
            if i == bot { return SeatView(kind: .bot) }
            let person = Person(id: "demo-\(i)", name: names[i], cat: cats[i])
            if i == leftSeat { return SeatView(kind: .bot, person: person, left: true) }
            return SeatView(kind: .human, person: person, yours: mine.contains(i), presence: .awake)
        }
    }

    /// The deck a table deals (design §4.2).
    public static func birdDeck(_ rules: BirdRules, seats: Int) -> [BirdCardID] {
        let low = seats == 4 ? 5 : 2
        let ranks = (rules == .official ? [] : [1]) + Array(low...14)
        return BirdSuit.allCases.flatMap { suit in ranks.map { birdID(suit, $0) } } + [BirdCard.birdID]
    }

    static func birdTeams(_ n: Int) -> [[Seat]] {
        switch n {
        case 4: [[0, 2], [1, 3]]
        case 6: [[0, 3], [1, 4], [2, 5]]
        default: (0..<n).map { [$0] }
        }
    }

    public static func birdRoom(_ demo: BirdDemo) -> RoomView {
        let f = BirdSuit.fish, m = BirdSuit.mouse, fe = BirdSuit.feather, b = BirdSuit.bell
        let id = birdID
        // My nine (official, four players): two fish, three mice, two feathers, a bell and the Bird.
        let mine = [id(f, 9), id(f, 14), id(m, 5), id(m, 10), id(m, 13), id(fe, 7), id(fe, 14), id(b, 11), BirdCard.birdID]
        let nest = [id(f, 6), id(m, 8), id(fe, 10), id(fe, 12), id(b, 5)]
        var view: BirdView
        var seats = birdSeats(4)
        var options = RoomOptions(rules: .official)
        var status = RoomStatus.playing
        switch demo {
        case .bid:
            view = BirdView(
                seats: 4, teams: birdTeams(4), scores: [45, 75], phase: .bidding, hand: 2, dealer: 2, turn: 0,
                handCounts: [9, 9, 9, 9], hands: [0: mine], bids: [nil, nil, nil, 75], high: BirdHigh(seat: 3, amount: 75),
                bidRange: BirdBidRange(min: 80, max: 120))
        case .nest:
            view = BirdView(
                seats: 4, teams: birdTeams(4), scores: [45, 75], phase: .nest, hand: 2, dealer: 2, turn: 0,
                handCounts: [14, 9, 9, 9], hands: [0: mine + nest], bids: [85, nil, nil, 75],
                passed: [false, true, true, true], high: BirdHigh(seat: 0, amount: 85), fromNest: nest)
        case .trump:
            view = BirdView(
                seats: 4, teams: birdTeams(4), scores: [45, 75], phase: .trump, hand: 2, dealer: 2, turn: 0,
                handCounts: [9, 9, 9, 9], hands: [0: mine], bids: [85, nil, nil, 75], passed: [false, true, true, true],
                high: BirdHigh(seat: 0, amount: 85), putBack: nest)
        case .play, .watch, .curtain:
            // Two tricks gone; Leo led the 12 of fish, Kiki and Otis followed.
            let hand = [id(f, 9), id(f, 14), id(m, 10), id(m, 13), id(fe, 7), id(fe, 14), BirdCard.birdID]
            let trick = [BirdTrickCard(seat: 1, card: id(f, 12)), BirdTrickCard(seat: 2, card: id(f, 5)), BirdTrickCard(seat: 3, card: id(f, 7))]
            let mineToPlay = demo != .watch
            view = BirdView(
                seats: 4, teams: birdTeams(4), scores: [45, 75], phase: .play, hand: 2, dealer: 2, turn: mineToPlay ? 0 : 1,
                handCounts: mineToPlay ? [7, 6, 6, 6] : [7, 7, 7, 7], hands: [0: hand], bids: [85, nil, nil, 75],
                passed: [false, true, true, true], high: BirdHigh(seat: 0, amount: 85), trump: fe,
                trick: mineToPlay ? trick : [], leader: 1,
                lastTrick: BirdLastTrick(cards: [BirdTrickCard(seat: 0, card: id(m, 5)), BirdTrickCard(seat: 1, card: id(m, 14))], winner: 1),
                played: [id(m, 5), id(m, 14), id(m, 6), id(m, 7), id(b, 11), id(b, 6), id(b, 9), id(b, 14)] + (mineToPlay ? trick.map(\.card) : []),
                points: [0, 20, 0, 10], tricks: [0, 1, 0, 1],
                playable: mineToPlay ? [id(f, 9), id(f, 14), BirdCard.birdID] : nil, putBack: nest)
            if demo == .curtain {
                seats = birdSeats(4, mine: [0, 2])
                view.hands = [0: hand, 2: [id(f, 10), id(m, 11), id(m, 12), id(fe, 5), id(fe, 6), id(b, 8)]]
            }
        case .partner, .partnerMark:
            options = RoomOptions(rules: .tucker)
            seats = birdSeats(5)
            let five = [id(f, 1), id(f, 13), id(m, 10), id(fe, 1), id(fe, 14), id(fe, 13), id(fe, 9), id(b, 5), id(b, 12), BirdCard.birdID]
            let deck = birdDeck(.tucker, seats: 5)
            let calling = demo == .partner
            view = BirdView(
                rules: .tucker, seats: 5, target: 500, maxBid: 180, nestSize: 7, teams: birdTeams(5), scores: [120, 35, 0, 95, 60],
                phase: calling ? .partner : .play, hand: 3, dealer: 4, turn: calling ? 0 : 1, handCounts: [10, 10, 10, 10, 10],
                hands: [0: five], bids: calling ? [110, nil, nil, nil, 95] : [nil, 110, nil, nil, 95], passed: [false, true, true, true, true],
                high: BirdHigh(seat: calling ? 0 : 1, amount: 110), trump: fe, called: calling ? nil : id(fe, 1), leader: calling ? nil : 1,
                partnerChoices: calling ? deck.filter { !five.contains($0) } : nil, youArePartner: calling ? nil : 0)
            if !calling {
                view.hands = [0: five]
                view.passed = [true, false, true, true, true]
            }
        case .six:
            options = RoomOptions(rules: .friesen)
            seats = birdSeats(6, leftSeat: 3)
            let six = [id(f, 2), id(f, 11), id(m, 1), id(m, 4), id(fe, 10), id(fe, 13), id(b, 1), id(b, 14), BirdCard.birdID]
            view = BirdView(
                rules: .friesen, seats: 6, target: 500, maxBid: 180, nestSize: 3, teams: birdTeams(6), scores: [210, 145, 95],
                phase: .bidding, hand: 4, dealer: 4, turn: 0, handCounts: [9, 9, 9, 9, 9, 9], hands: [0: six],
                bids: [nil, nil, nil, nil, nil, 90], passed: [false, false, false, false, false, false], high: BirdHigh(seat: 5, amount: 90),
                bidRange: BirdBidRange(min: 95, max: 180))
        case .between:
            let result = BirdHandResult(hand: 2, bidder: 0, bid: 85, trump: fe, made: true, taken: [95, 25], change: [95, 25], totals: [140, 100])
            view = BirdView(
                seats: 4, teams: birdTeams(4), scores: [140, 100],
                history: [BirdHandResult(hand: 1, bidder: 3, bid: 75, trump: b, made: true, taken: [45, 75], change: [45, 75], totals: [45, 75]), result],
                phase: .between, hand: 2, dealer: 2, turn: nil, handCounts: [0, 0, 0, 0], hands: [0: []], bids: [85, nil, nil, 75],
                passed: [false, true, true, true], high: BirdHigh(seat: 0, amount: 85), trump: fe, points: [60, 25, 35, 0],
                tricks: [4, 1, 3, 1], putBack: nest)
        case .over:
            status = .over
            view = BirdView(
                seats: 4, teams: birdTeams(4), scores: [315, 180],
                history: [
                    BirdHandResult(hand: 1, bidder: 3, bid: 75, trump: b, made: true, taken: [45, 75], change: [45, 75], totals: [45, 75]),
                    BirdHandResult(hand: 2, bidder: 0, bid: 85, trump: fe, made: true, taken: [95, 25], change: [95, 25], totals: [140, 100]),
                    BirdHandResult(hand: 3, bidder: 1, bid: 90, trump: f, made: false, taken: [80, 40], change: [80, -90], totals: [220, 10]),
                    BirdHandResult(hand: 4, bidder: 2, bid: 80, trump: m, made: true, taken: [95, 25], change: [95, 170], totals: [315, 180]),
                ],
                status: .over, phase: .over, hand: 4, dealer: 1, turn: nil, handCounts: [0, 0, 0, 0], hands: [0: []],
                bids: [nil, nil, 80, nil], passed: [true, true, false, true], high: BirdHigh(seat: 2, amount: 80), trump: m,
                winners: [0, 2], endReason: .target)
        }
        return RoomView(
            code: code, name: demoName, status: status, youAreHost: true, seats: seats, gameId: GameID.birdwatch,
            birdwatch: view, options: options)
    }

    /// A Birdwatch lobby: me and two others, three seats open of six (`seated` people in all).
    public static func birdLobby(seated: Int = 3, rules: BirdRules = .official) -> RoomView {
        var seats = birdSeats(6)
        for i in seats.indices where i >= seated { seats[i] = SeatView(kind: i < 4 ? .open : .closed) }
        return RoomView(
            code: code, name: demoName, status: .lobby, youAreHost: true, seats: seats, gameId: GameID.birdwatch,
            options: RoomOptions(rules: rules))
    }
}
#endif
