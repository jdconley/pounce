/// What Birdwatch's table shows, derived from a `RoomView` playing it (design §5). Client-side
/// only: what may be played, bid or called comes from the server's view, never from rules here.
public struct BirdTableModel: Equatable, Sendable {
    public let room: RoomView
    public let view: BirdView

    /// Nil for a room that isn't dealing Birdwatch yet (its lobby, or another game).
    public init?(room: RoomView) {
        guard let view = room.birdwatch else { return nil }
        self.room = room
        self.view = view
    }

    public var seatCount: Int { view.seats }

    /// Seats this device controls.
    public var mySeats: [Seat] { room.seats.indices.filter { room.seats[$0].yours } }

    public var isMultiSeat: Bool { mySeats.count > 1 }

    public var isLive: Bool { room.status == .playing && view.status == .playing }

    /// The seat to act; nil between hands and once over.
    public var currentSeat: Seat? { isLive ? view.turn : nil }

    public var isMyTurn: Bool { currentSeat.map(mySeats.contains) ?? false }

    /// The seat drawn at the bottom: the revealed one, else this phone's only seat, else (a shared
    /// phone with nothing revealed) none, so no hand is drawn at all.
    public func bottomSeat(revealed: Seat?) -> Seat? {
        if let revealed, mySeats.contains(revealed) { return revealed }
        return mySeats.count == 1 ? mySeats.first : nil
    }

    /// The seats around the window, in play order after `bottom` (to its left first), or every
    /// seat when nothing is drawn at the bottom.
    public func barSeats(bottom: Seat?) -> [Seat] {
        guard let bottom, bottom >= 0, bottom < seatCount else { return Array(0..<seatCount) }
        return (1..<max(seatCount, 1)).map { (bottom + $0) % seatCount }
    }

    // MARK: cards

    /// The hand of a seat this device controls, sorted (fish, mouse, feather, bell, with trump
    /// last once named and the Bird with trump; low to high inside a suit). Nil for any other seat.
    public func hand(_ seat: Seat) -> [BirdCardID]? {
        view.hands[seat].map { Self.sorted($0, trump: view.trump) }
    }

    public static func sorted(_ cards: [BirdCardID], trump: BirdSuit?) -> [BirdCardID] {
        func key(_ id: BirdCardID) -> (Int, Int) {
            guard let card = BirdCard(id: id) else { return (99, id) }
            switch card {
            case .bird: return (5, 100)
            case .suited(let suit, _):
                var group = suit.index
                if suit == trump { group = 4 }
                return (group, card.order)
            }
        }
        return cards.sorted { key($0) < key($1) }
    }

    public func handCount(_ seat: Seat) -> Int { view.handCounts[safe: seat] ?? 0 }

    /// The cards `seat` may play now: the server's `playable`, only on that seat's move.
    public func playable(_ seat: Seat) -> Set<BirdCardID> {
        guard currentSeat == seat, view.phase == .play, mySeats.contains(seat) else { return [] }
        return Set(view.playable ?? [])
    }

    /// What VoiceOver says for a card: "10, fish, 10 points", "Bird, 20 points, top trump",
    /// "7, mouse" for one that scores nothing.
    public static func label(_ id: BirdCardID) -> String {
        guard let card = BirdCard(id: id) else { return "" }
        switch card {
        case .bird:
            return String(localized: "Bird, 20 points, top trump", comment: "VoiceOver: the Bird card")
        case .suited(let suit, let rank):
            let name = suitName(suit)
            let points = card.points
            guard points > 0 else { return "\(rank), \(name)" }
            return String(localized: "\(rank), \(name), \(points) points", comment: "VoiceOver: a card that scores, e.g. 10, fish, 10 points")
        }
    }

    /// A suit's name on screen and for VoiceOver.
    public static func suitName(_ suit: BirdSuit) -> String {
        switch suit {
        case .fish: String(localized: "fish", comment: "Birdwatch suit")
        case .mouse: String(localized: "mouse", comment: "Birdwatch suit")
        case .feather: String(localized: "feather", comment: "Birdwatch suit")
        case .bell: String(localized: "bell", comment: "Birdwatch suit")
        }
    }

    // MARK: sides

    /// The ribbon a seat's name tag wears.
    public enum Ribbon: Int, CaseIterable, Sendable {
        case orange, teal, magenta
        /// Five players: the bid winner and their partner, once the partner is known.
        case gold
    }

    /// Four and six players: the seat's team colour. Five: gold for the bid winner and the
    /// partner once the table knows the partner, otherwise none.
    public func ribbon(of seat: Seat) -> Ribbon? {
        if view.isFive {
            guard let partner = view.partner, let bidder = view.high?.seat, seat == partner || seat == bidder,
                  view.phase != .bidding else { return nil }
            return .gold
        }
        return view.side(of: seat).flatMap { Ribbon(rawValue: $0) }
    }

    /// A chip on the score strip: one per side (each seat in a five-player game).
    public struct Side: Equatable, Sendable {
        public var index: Int
        public var seats: [Seat]
        public var score: Int
        /// The counters this side has taken this hand.
        public var taken: Int
        public var ribbon: Ribbon?
        /// The bid winner is on this side.
        public var bidding: Bool
    }

    public var sides: [Side] {
        view.teams.enumerated().map { index, seats in
            Side(
                index: index, seats: seats, score: view.scores[safe: index] ?? 0,
                taken: seats.reduce(0) { $0 + (view.points[safe: $1] ?? 0) },
                ribbon: view.isFive ? nil : Ribbon(rawValue: index),
                bidding: view.high.map { seats.contains($0.seat) } ?? false)
        }
    }

    // MARK: signs

    /// What a seat's cat holds up.
    public enum Sign: Equatable, Sendable {
        case bid(Int)
        case pass
        /// The hand's bid, made (between hands).
        case made(Int)
        /// The hand's bid, missed: the cat droops.
        case missed(Int)
    }

    public func sign(_ seat: Seat) -> Sign? {
        switch view.phase {
        case .bidding:
            if view.passed[safe: seat] == true { return .pass }
            return view.bids[safe: seat].flatMap { $0 }.map(Sign.bid)
        case .nest, .trump, .partner, .play:
            guard let high = view.high, high.seat == seat else { return nil }
            return .bid(high.amount)
        case .between, .over:
            guard let last = view.history.last, last.hand == view.hand, last.bidder == seat else { return nil }
            return last.made ? .made(last.bid) : .missed(last.bid)
        }
    }

    // MARK: the hand's phases

    /// The controls `seat` gets now (nil: none, or play, which the hand itself takes).
    public enum Panel: Equatable, Sendable {
        case bid(BirdBidRange)
        /// Put back `count` cards; `fromNest` glow.
        case nest(count: Int, fromNest: [BirdCardID])
        case trump(hint: BirdSuit?)
        case partner(choices: [BirdCardID])
        /// Someone else is choosing: say who and what.
        case waiting(phase: BirdPhase, seat: Seat)
    }

    /// The panel for the hand drawn at the bottom (`seat`), or for nobody (a TV, a shared phone
    /// with no hand up): then only `waiting`.
    public func panel(for seat: Seat?) -> Panel? {
        guard isLive, let turn = view.turn else { return nil }
        guard let seat, seat == turn, mySeats.contains(seat) else {
            switch view.phase {
            case .bidding, .nest, .trump, .partner: return .waiting(phase: view.phase, seat: turn)
            default: return nil
            }
        }
        switch view.phase {
        case .bidding:
            return view.bidRange.map(Panel.bid)
        case .nest:
            return .nest(count: view.nestSize, fromNest: view.fromNest ?? [])
        case .trump:
            return .trump(hint: trumpHint(seat))
        case .partner:
            return .partner(choices: view.partnerChoices ?? [])
        case .play, .between, .over:
            return nil
        }
    }

    /// The suit `seat` holds most of (ties: more counters, then suit order): the trump picker's
    /// hint ring.
    public func trumpHint(_ seat: Seat) -> BirdSuit? {
        guard let cards = view.hands[seat], !cards.isEmpty else { return nil }
        var count: [BirdSuit: (Int, Int)] = [:]
        for id in cards {
            guard let card = BirdCard(id: id), let suit = card.suit else { continue }
            let old = count[suit] ?? (0, 0)
            count[suit] = (old.0 + 1, old.1 + card.points)
        }
        return BirdSuit.allCases.max { a, b in
            let x = count[a] ?? (0, 0)
            let y = count[b] ?? (0, 0)
            if x.0 != y.0 { return x.0 < y.0 }
            if x.1 != y.1 { return x.1 < y.1 }
            return a.index > b.index
        }.flatMap { count[$0] == nil ? nil : $0 }
    }

    /// Partner choices by suit row, trump's row first, then the others in suit order; the Bird
    /// rides with trump (or alone at the end before trump is known).
    public static func partnerRows(_ choices: [BirdCardID], trump: BirdSuit?) -> [(suit: BirdSuit?, cards: [BirdCardID])] {
        var suits = BirdSuit.allCases
        if let trump, let i = suits.firstIndex(of: trump) { suits.insert(suits.remove(at: i), at: 0) }
        var rows: [(suit: BirdSuit?, cards: [BirdCardID])] = suits.map { suit in
            (suit, choices.filter { BirdCard(id: $0)?.suit == suit }.sorted { BirdCard(id: $0)!.order > BirdCard(id: $1)!.order })
        }
        if choices.contains(BirdCard.birdID) {
            if trump != nil {
                rows[0].cards.insert(BirdCard.birdID, at: 0)
            } else {
                rows.append((nil, [BirdCard.birdID]))
            }
        }
        return rows.filter { !$0.cards.isEmpty }
    }

    /// The partner mark for `seat`: this device holds the called card in that seat, and the
    /// seat's hand is face up (`revealed`, or this phone's only seat). A shared phone never
    /// shows it before that seat's curtain.
    public func partnerMark(for seat: Seat, revealed: Seat?) -> Bool {
        guard view.youArePartner == seat, mySeats.contains(seat) else { return false }
        return mySeats.count == 1 || revealed == seat
    }

    /// The bid winner, while a hand is on (after bidding).
    public var bidder: Seat? {
        switch view.phase {
        case .bidding: nil
        default: view.high?.seat
        }
    }

    // MARK: the end

    /// The finished game's sides, best first: winners, then by score.
    public var standings: [Side] {
        sides.sorted { a, b in
            let aw = a.seats.contains { view.winners.contains($0) }
            let bw = b.seats.contains { view.winners.contains($0) }
            if aw != bw { return aw }
            if a.score != b.score { return a.score > b.score }
            return a.index < b.index
        }
    }

    /// The seat a forfeit from this phone's menu applies to: the hand that is up, else the seat to
    /// act, else this phone's first seat.
    public func forfeitSeat(shown: Seat?) -> Seat? {
        guard isLive else { return nil }
        let mine = mySeats.filter { !(room.seats[safe: $0]?.isTakenOver ?? false) }
        if let shown, mine.contains(shown) { return shown }
        if let turn = view.turn, mine.contains(turn) { return turn }
        return mine.first
    }
}

// MARK: - The lobby

extension TableModel {
    /// The cats the game at this table takes (Cat Tower and Tuna Tiles: 2 and up; Birdwatch 4 to 6).
    public var seatRange: ClosedRange<Int> {
        guard let entry = room.gameId.flatMap(GameCatalog.entry(id:)) else { return Self.minPlayers...6 }
        return entry.minPlayers...entry.maxPlayers
    }

    /// The fewest cats this table's game needs.
    public var neededPlayers: Int { max(seatRange.lowerBound, Self.minPlayers) }

    /// A Birdwatch lobby: each filled seat's team ribbon, counted the way the server will once it
    /// deals (filled seats in order: four play 0 and 2 against 1 and 3, six 0 and 3, 1 and 4,
    /// 2 and 5). Nil for an empty seat, a five-player table, or another game.
    public func lobbyRibbon(_ seat: Seat) -> BirdTableModel.Ribbon? {
        guard room.isBirdwatch, room.status == .lobby else { return nil }
        let filled = room.seats.indices.filter { room.seats[$0].kind == .human || room.seats[$0].kind == .bot }
        guard let place = filled.firstIndex(of: seat) else { return nil }
        switch filled.count {
        case 4: return BirdTableModel.Ribbon(rawValue: place % 2)
        case 6: return BirdTableModel.Ribbon(rawValue: place % 3)
        default: return nil
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
