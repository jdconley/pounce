import Foundation

// Birdwatch on the wire (docs/superpowers/notes/2026-11-25-birdwatch-wire.md; types in
// apps/play-api/src/birdwatch/{engine,view}.ts). The client never ports the rules: what may be
// played, bid or called comes from the view (`playable`, `bidRange`, `partnerChoices`).

/// A card id, 0 to 56. Suited: suit `id / 14`, rank `id % 14 + 1`. 56 is the Bird.
public typealias BirdCardID = Int

/// Birdwatch's suits are Tuna Tiles' toys: the same four, in the same order, with the same art.
public typealias BirdSuit = TileSuit

/// One Birdwatch card.
public enum BirdCard: Hashable, Sendable {
    case bird
    case suited(BirdSuit, rank: Int)

    public static let birdID: BirdCardID = 56
    /// Cards in the full deck.
    public static let deckSize = 57

    /// Nil for an id outside the deck.
    public init?(id: BirdCardID) {
        guard (0..<Self.deckSize).contains(id) else { return nil }
        if id == Self.birdID {
            self = .bird
        } else {
            self = .suited(BirdSuit.allCases[id / 14], rank: id % 14 + 1)
        }
    }

    public var id: BirdCardID {
        switch self {
        case .bird: Self.birdID
        case .suited(let suit, let rank): suit.index * 14 + rank - 1
        }
    }

    /// What the card counts for: 5s are 5, 10s and 14s are 10, 1s are 15, the Bird is 20.
    public var points: Int {
        switch self {
        case .bird: 20
        case .suited(_, let rank):
            switch rank {
            case 5: 5
            case 10, 14: 10
            case 1: 15
            default: 0
            }
        }
    }

    public var suit: BirdSuit? {
        if case .suited(let suit, _) = self { return suit }
        return nil
    }

    public var rank: Int? {
        if case .suited(_, let rank) = self { return rank }
        return nil
    }

    /// Where the rank sits low to high: 2 to 14, then the 1 on top (1s exist only in Tucker and
    /// Friesen). The Bird is above everything.
    public var order: Int {
        switch self {
        case .bird: 100
        case .suited(_, let rank): rank == 1 ? 15 : rank
        }
    }
}

/// The table's rule set (design §4.1).
public enum BirdRules: String, Codable, CaseIterable, Sendable {
    case official, tucker, friesen
}

/// Where a hand is (design §7).
public enum BirdPhase: String, Codable, Sendable {
    case bidding, nest, trump, partner, play, between, over
}

public enum BirdStatus: String, Codable, Sendable { case playing, over }

/// Why a Birdwatch game ended: someone reached the target, or every person left.
public enum BirdEndReason: String, Codable, Sendable { case target, left }

/// A game option a room carries (`room.options`), set in the lobby by the host.
public struct RoomOptions: Codable, Equatable, Sendable {
    public var rules: BirdRules?
    /// Toy Tumble's House Cat level.
    public var cats: TumbleCats?
    /// Purrtrait's seconds a turn (45, 60 or 90).
    public var timer: Int?

    public init(rules: BirdRules? = nil, cats: TumbleCats? = nil, timer: Int? = nil) {
        self.rules = rules
        self.cats = cats
        self.timer = timer
    }

    private enum CodingKeys: String, CodingKey { case rules, cats, timer }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A rule set or level this build doesn't know reads as none, never as a broken room.
        rules = (try? c.decodeIfPresent(String.self, forKey: .rules)).flatMap(BirdRules.init(rawValue:))
        cats = (try? c.decodeIfPresent(String.self, forKey: .cats)).flatMap(TumbleCats.init(rawValue:))
        timer = (try? c.decodeIfPresent(Int.self, forKey: .timer)) ?? nil
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(rules, forKey: .rules)
        try c.encodeIfPresent(cats, forKey: .cats)
        try c.encodeIfPresent(timer, forKey: .timer)
    }
}

public struct BirdHigh: Codable, Equatable, Sendable {
    public var seat: Seat
    public var amount: Int

    public init(seat: Seat, amount: Int) {
        self.seat = seat
        self.amount = amount
    }
}

public struct BirdTrickCard: Codable, Equatable, Sendable {
    public var seat: Seat
    public var card: BirdCardID

    public init(seat: Seat, card: BirdCardID) {
        self.seat = seat
        self.card = card
    }
}

public struct BirdLastTrick: Codable, Equatable, Sendable {
    public var cards: [BirdTrickCard]
    public var winner: Seat

    public init(cards: [BirdTrickCard], winner: Seat) {
        self.cards = cards
        self.winner = winner
    }
}

/// The bids the seat on the move may make now (pass is always allowed).
public struct BirdBidRange: Codable, Equatable, Sendable {
    public var min: Int
    public var max: Int
    public var step: Int

    public init(min: Int, max: Int, step: Int = 5) {
        self.min = min
        self.max = max
        self.step = step
    }
}

/// One finished hand. `taken`, `change` and `totals` are per side (`BirdView.teams`).
public struct BirdHandResult: Codable, Equatable, Sendable {
    public var hand: Int
    public var bidder: Seat
    public var bid: Int
    /// Five players only: the called card's holder; nil when the bidder played alone (or in a
    /// team game).
    public var partner: Seat?
    public var trump: BirdSuit
    public var made: Bool
    public var taken: [Int]
    public var change: [Int]
    public var totals: [Int]

    public init(
        hand: Int, bidder: Seat, bid: Int, partner: Seat? = nil, trump: BirdSuit, made: Bool, taken: [Int], change: [Int],
        totals: [Int]
    ) {
        self.hand = hand
        self.bidder = bidder
        self.bid = bid
        self.partner = partner
        self.trump = trump
        self.made = made
        self.taken = taken
        self.change = change
        self.totals = totals
    }

    private enum CodingKeys: String, CodingKey { case hand, bidder, bid, partner, trump, made, taken, change, totals }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hand, forKey: .hand)
        try c.encode(bidder, forKey: .bidder)
        try c.encode(bid, forKey: .bid)
        try c.encode(partner, forKey: .partner)  // null: alone, or a team game
        try c.encode(trump, forKey: .trump)
        try c.encode(made, forKey: .made)
        try c.encode(taken, forKey: .taken)
        try c.encode(change, forKey: .change)
        try c.encode(totals, forKey: .totals)
    }
}

/// What this device may see of a Birdwatch game. `hands` holds only this device's seats (a JSON
/// object keyed by seat number as a string); the nest, the cards put back mid-hand and who holds
/// a called card never reach a device that may not see them. The optional choice fields come
/// only to the device holding the seat that may use them.
public struct BirdView: Codable, Equatable, Sendable {
    public var rules: BirdRules
    public var seats: Int
    public var target: Int
    public var minBid: Int
    public var maxBid: Int
    public var nestSize: Int
    /// The sides, each a list of seats: 4 players `[[0,2],[1,3]]`, 6 `[[0,3],[1,4],[2,5]]`, 5 one per seat.
    public var teams: [[Seat]]
    /// Per side.
    public var scores: [Int]
    public var history: [BirdHandResult]
    public var status: BirdStatus
    public var phase: BirdPhase
    /// 1-based.
    public var hand: Int
    public var dealer: Seat
    /// Nil between hands and once over.
    public var turn: Seat?
    public var handCounts: [Int]
    public var hands: [Seat: [BirdCardID]]
    /// Each seat's last bid this hand (nil: none yet).
    public var bids: [Int?]
    public var passed: [Bool]
    /// The high bid; after bidding, the hand's bid.
    public var high: BirdHigh?
    public var trump: BirdSuit?
    /// Five players: the card the bid winner called (public).
    public var called: BirdCardID?
    /// Five players: the partner, once the called card is played (or at the hand's end).
    public var partner: Seat?
    public var trick: [BirdTrickCard]
    public var leader: Seat?
    public var lastTrick: BirdLastTrick?
    /// Cards played this hand, in order.
    public var played: [BirdCardID]
    /// Per seat, this hand: counters taken.
    public var points: [Int]
    /// Per seat, this hand: tricks taken.
    public var tricks: [Int]
    public var winners: [Seat]
    public var playable: [BirdCardID]?
    public var bidRange: BirdBidRange?
    public var fromNest: [BirdCardID]?
    public var putBack: [BirdCardID]?
    public var partnerChoices: [BirdCardID]?
    /// The seat on this device that holds the called card (five players): the partner mark,
    /// shown only behind that seat's curtain.
    public var youArePartner: Seat?
    public var endReason: BirdEndReason?

    public init(
        rules: BirdRules = .official, seats: Int, target: Int = 300, minBid: Int = 70, maxBid: Int = 120, nestSize: Int = 5,
        teams: [[Seat]], scores: [Int], history: [BirdHandResult] = [], status: BirdStatus = .playing,
        phase: BirdPhase, hand: Int = 1, dealer: Seat = 0, turn: Seat?, handCounts: [Int],
        hands: [Seat: [BirdCardID]] = [:], bids: [Int?]? = nil, passed: [Bool]? = nil, high: BirdHigh? = nil,
        trump: BirdSuit? = nil, called: BirdCardID? = nil, partner: Seat? = nil, trick: [BirdTrickCard] = [],
        leader: Seat? = nil, lastTrick: BirdLastTrick? = nil, played: [BirdCardID] = [], points: [Int]? = nil,
        tricks: [Int]? = nil, winners: [Seat] = [], playable: [BirdCardID]? = nil, bidRange: BirdBidRange? = nil,
        fromNest: [BirdCardID]? = nil, putBack: [BirdCardID]? = nil, partnerChoices: [BirdCardID]? = nil,
        youArePartner: Seat? = nil, endReason: BirdEndReason? = nil
    ) {
        self.rules = rules
        self.seats = seats
        self.target = target
        self.minBid = minBid
        self.maxBid = maxBid
        self.nestSize = nestSize
        self.teams = teams
        self.scores = scores
        self.history = history
        self.status = status
        self.phase = phase
        self.hand = hand
        self.dealer = dealer
        self.turn = turn
        self.handCounts = handCounts
        self.hands = hands
        self.bids = bids ?? Array(repeating: nil, count: seats)
        self.passed = passed ?? Array(repeating: false, count: seats)
        self.high = high
        self.trump = trump
        self.called = called
        self.partner = partner
        self.trick = trick
        self.leader = leader
        self.lastTrick = lastTrick
        self.played = played
        self.points = points ?? Array(repeating: 0, count: seats)
        self.tricks = tricks ?? Array(repeating: 0, count: seats)
        self.winners = winners
        self.playable = playable
        self.bidRange = bidRange
        self.fromNest = fromNest
        self.putBack = putBack
        self.partnerChoices = partnerChoices
        self.youArePartner = youArePartner
        self.endReason = endReason
    }

    private enum CodingKeys: String, CodingKey {
        case rules, seats, target, minBid, maxBid, nestSize, teams, scores, history, status, phase, hand, dealer, turn
        case handCounts, hands, bids, passed, high, trump, called, partner, trick, leader, lastTrick, played, points
        case tricks, winners, playable, bidRange, fromNest, putBack, partnerChoices, youArePartner, endReason
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decode(BirdRules.self, forKey: .rules)
        seats = try c.decode(Int.self, forKey: .seats)
        target = try c.decode(Int.self, forKey: .target)
        minBid = try c.decode(Int.self, forKey: .minBid)
        maxBid = try c.decode(Int.self, forKey: .maxBid)
        nestSize = try c.decode(Int.self, forKey: .nestSize)
        teams = try c.decode([[Seat]].self, forKey: .teams)
        scores = try c.decode([Int].self, forKey: .scores)
        history = try c.decode([BirdHandResult].self, forKey: .history)
        status = try c.decode(BirdStatus.self, forKey: .status)
        phase = try c.decode(BirdPhase.self, forKey: .phase)
        hand = try c.decode(Int.self, forKey: .hand)
        dealer = try c.decode(Seat.self, forKey: .dealer)
        turn = try c.decodeIfPresent(Seat.self, forKey: .turn)
        handCounts = try c.decode([Int].self, forKey: .handCounts)
        hands = try c.decode(StringKeyedSeats.self, forKey: .hands).hands
        bids = try c.decode([Int?].self, forKey: .bids)
        passed = try c.decode([Bool].self, forKey: .passed)
        high = try c.decodeIfPresent(BirdHigh.self, forKey: .high)
        trump = try c.decodeIfPresent(BirdSuit.self, forKey: .trump)
        called = try c.decodeIfPresent(BirdCardID.self, forKey: .called)
        partner = try c.decodeIfPresent(Seat.self, forKey: .partner)
        trick = try c.decode([BirdTrickCard].self, forKey: .trick)
        leader = try c.decodeIfPresent(Seat.self, forKey: .leader)
        lastTrick = try c.decodeIfPresent(BirdLastTrick.self, forKey: .lastTrick)
        played = try c.decode([BirdCardID].self, forKey: .played)
        points = try c.decode([Int].self, forKey: .points)
        tricks = try c.decode([Int].self, forKey: .tricks)
        winners = try c.decode([Seat].self, forKey: .winners)
        playable = try c.decodeIfPresent([BirdCardID].self, forKey: .playable)
        bidRange = try c.decodeIfPresent(BirdBidRange.self, forKey: .bidRange)
        fromNest = try c.decodeIfPresent([BirdCardID].self, forKey: .fromNest)
        putBack = try c.decodeIfPresent([BirdCardID].self, forKey: .putBack)
        partnerChoices = try c.decodeIfPresent([BirdCardID].self, forKey: .partnerChoices)
        youArePartner = try c.decodeIfPresent(Seat.self, forKey: .youArePartner)
        endReason = (try? c.decodeIfPresent(String.self, forKey: .endReason)).flatMap(BirdEndReason.init(rawValue:))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rules, forKey: .rules)
        try c.encode(seats, forKey: .seats)
        try c.encode(target, forKey: .target)
        try c.encode(minBid, forKey: .minBid)
        try c.encode(maxBid, forKey: .maxBid)
        try c.encode(nestSize, forKey: .nestSize)
        try c.encode(teams, forKey: .teams)
        try c.encode(scores, forKey: .scores)
        try c.encode(history, forKey: .history)
        try c.encode(status, forKey: .status)
        try c.encode(phase, forKey: .phase)
        try c.encode(hand, forKey: .hand)
        try c.encode(dealer, forKey: .dealer)
        try c.encode(turn, forKey: .turn)
        try c.encode(handCounts, forKey: .handCounts)
        try c.encode(StringKeyedSeats(hands: hands), forKey: .hands)
        try c.encode(bids, forKey: .bids)
        try c.encode(passed, forKey: .passed)
        try c.encode(high, forKey: .high)
        try c.encode(trump, forKey: .trump)
        try c.encode(called, forKey: .called)
        try c.encode(partner, forKey: .partner)
        try c.encode(trick, forKey: .trick)
        try c.encode(leader, forKey: .leader)
        try c.encode(lastTrick, forKey: .lastTrick)
        try c.encode(played, forKey: .played)
        try c.encode(points, forKey: .points)
        try c.encode(tricks, forKey: .tricks)
        try c.encode(winners, forKey: .winners)
        try c.encodeIfPresent(playable, forKey: .playable)
        try c.encodeIfPresent(bidRange, forKey: .bidRange)
        try c.encodeIfPresent(fromNest, forKey: .fromNest)
        try c.encodeIfPresent(putBack, forKey: .putBack)
        try c.encodeIfPresent(partnerChoices, forKey: .partnerChoices)
        try c.encodeIfPresent(youArePartner, forKey: .youArePartner)
        try c.encodeIfPresent(endReason, forKey: .endReason)
    }

    /// The side `seat` is on (an index into `teams` and `scores`).
    public func side(of seat: Seat) -> Int? { teams.firstIndex { $0.contains(seat) } }

    public var isFive: Bool { seats == 5 }
}

/// A Birdwatch event as broadcast by the server (discriminator key `kind`), wrapped in the room
/// event `{"kind":"birdwatch","event":…}`. Cards in it reach only the device that may see them.
public enum BirdEvent: Codable, Equatable, Sendable {
    case dealt(hand: Int, dealer: Seat, handCounts: [Int], hands: [Seat: [BirdCardID]])
    case bid(seat: Seat, amount: Int)
    case passed(seat: Seat)
    case bidWon(seat: Seat, amount: Int)
    /// The bid winner took the nest; `cards` only on that seat's device.
    case nest(seat: Seat, cards: [BirdCardID]?)
    /// The bid winner put cards back; `cards` only on that seat's device.
    case putBack(seat: Seat, count: Int, cards: [BirdCardID]?)
    case trump(seat: Seat, suit: BirdSuit)
    /// Five players: the bid winner called a card.
    case called(seat: Seat, card: BirdCardID)
    case turn(seat: Seat)
    case played(seat: Seat, card: BirdCardID)
    /// Five players: the called card was just played by `seat`.
    case partner(seat: Seat)
    case trick(winner: Seat, cards: [BirdTrickCard], points: Int)
    case handOver(result: BirdHandResult, putBack: [BirdCardID])
    case gameOver(winners: [Seat], scores: [Int], reason: BirdEndReason)

    private enum CodingKeys: String, CodingKey {
        case kind, hand, dealer, handCounts, hands, seat, amount, cards, count, suit, card, winner, points, result
        case putBack, winners, scores, reason
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "dealt":
            self = .dealt(hand: try c.decode(Int.self, forKey: .hand), dealer: try c.decode(Seat.self, forKey: .dealer),
                          handCounts: try c.decode([Int].self, forKey: .handCounts),
                          hands: try c.decode(StringKeyedSeats.self, forKey: .hands).hands)
        case "bid":
            self = .bid(seat: try c.decode(Seat.self, forKey: .seat), amount: try c.decode(Int.self, forKey: .amount))
        case "passed":
            self = .passed(seat: try c.decode(Seat.self, forKey: .seat))
        case "bidWon":
            self = .bidWon(seat: try c.decode(Seat.self, forKey: .seat), amount: try c.decode(Int.self, forKey: .amount))
        case "nest":
            self = .nest(seat: try c.decode(Seat.self, forKey: .seat), cards: try c.decodeIfPresent([BirdCardID].self, forKey: .cards))
        case "putBack":
            self = .putBack(seat: try c.decode(Seat.self, forKey: .seat), count: try c.decode(Int.self, forKey: .count),
                            cards: try c.decodeIfPresent([BirdCardID].self, forKey: .cards))
        case "trump":
            self = .trump(seat: try c.decode(Seat.self, forKey: .seat), suit: try c.decode(BirdSuit.self, forKey: .suit))
        case "called":
            self = .called(seat: try c.decode(Seat.self, forKey: .seat), card: try c.decode(BirdCardID.self, forKey: .card))
        case "turn":
            self = .turn(seat: try c.decode(Seat.self, forKey: .seat))
        case "played":
            self = .played(seat: try c.decode(Seat.self, forKey: .seat), card: try c.decode(BirdCardID.self, forKey: .card))
        case "partner":
            self = .partner(seat: try c.decode(Seat.self, forKey: .seat))
        case "trick":
            self = .trick(winner: try c.decode(Seat.self, forKey: .winner), cards: try c.decode([BirdTrickCard].self, forKey: .cards),
                          points: try c.decode(Int.self, forKey: .points))
        case "handOver":
            self = .handOver(result: try c.decode(BirdHandResult.self, forKey: .result),
                             putBack: try c.decode([BirdCardID].self, forKey: .putBack))
        case "gameOver":
            self = .gameOver(winners: try c.decode([Seat].self, forKey: .winners), scores: try c.decode([Int].self, forKey: .scores),
                             reason: try c.decode(BirdEndReason.self, forKey: .reason))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown birdwatch event kind: \(kind)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dealt(let hand, let dealer, let handCounts, let hands):
            try c.encode("dealt", forKey: .kind)
            try c.encode(hand, forKey: .hand)
            try c.encode(dealer, forKey: .dealer)
            try c.encode(handCounts, forKey: .handCounts)
            try c.encode(StringKeyedSeats(hands: hands), forKey: .hands)
        case .bid(let seat, let amount):
            try c.encode("bid", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(amount, forKey: .amount)
        case .passed(let seat):
            try c.encode("passed", forKey: .kind)
            try c.encode(seat, forKey: .seat)
        case .bidWon(let seat, let amount):
            try c.encode("bidWon", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(amount, forKey: .amount)
        case .nest(let seat, let cards):
            try c.encode("nest", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encodeIfPresent(cards, forKey: .cards)
        case .putBack(let seat, let count, let cards):
            try c.encode("putBack", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(count, forKey: .count)
            try c.encodeIfPresent(cards, forKey: .cards)
        case .trump(let seat, let suit):
            try c.encode("trump", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(suit, forKey: .suit)
        case .called(let seat, let card):
            try c.encode("called", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(card, forKey: .card)
        case .turn(let seat):
            try c.encode("turn", forKey: .kind)
            try c.encode(seat, forKey: .seat)
        case .played(let seat, let card):
            try c.encode("played", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(card, forKey: .card)
        case .partner(let seat):
            try c.encode("partner", forKey: .kind)
            try c.encode(seat, forKey: .seat)
        case .trick(let winner, let cards, let points):
            try c.encode("trick", forKey: .kind)
            try c.encode(winner, forKey: .winner)
            try c.encode(cards, forKey: .cards)
            try c.encode(points, forKey: .points)
        case .handOver(let result, let putBack):
            try c.encode("handOver", forKey: .kind)
            try c.encode(result, forKey: .result)
            try c.encode(putBack, forKey: .putBack)
        case .gameOver(let winners, let scores, let reason):
            try c.encode("gameOver", forKey: .kind)
            try c.encode(winners, forKey: .winners)
            try c.encode(scores, forKey: .scores)
            try c.encode(reason, forKey: .reason)
        }
    }
}

/// A Birdwatch move (discriminator key `type`), sent in the `{"t":"act"}` envelope.
public enum BirdAction: Encodable, Equatable, Sendable {
    /// A multiple of 5 in the seat's `bidRange`.
    case bid(Int)
    case pass
    /// The bid winner's put-back: exactly `nestSize` cards from their hand.
    case nest([BirdCardID])
    case trump(BirdSuit)
    /// Five players: the card whose holder partners the bid winner.
    case partner(BirdCardID)
    case play(BirdCardID)
    /// Leave: a House Cat takes the seat for the rest of the game.
    case forfeit

    private enum CodingKeys: String, CodingKey { case type, amount, discard, suit, card }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bid(let amount):
            try c.encode("bid", forKey: .type)
            try c.encode(amount, forKey: .amount)
        case .pass:
            try c.encode("pass", forKey: .type)
        case .nest(let discard):
            try c.encode("nest", forKey: .type)
            try c.encode(discard, forKey: .discard)
        case .trump(let suit):
            try c.encode("trump", forKey: .type)
            try c.encode(suit, forKey: .suit)
        case .partner(let card):
            try c.encode("partner", forKey: .type)
            try c.encode(card, forKey: .card)
        case .play(let card):
            try c.encode("play", forKey: .type)
            try c.encode(card, forKey: .card)
        case .forfeit:
            try c.encode("forfeit", forKey: .type)
        }
    }
}
