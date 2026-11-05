import Foundation

/// A player's identity as the server sees it. `id` is a lowercase UUID string
/// generated on the device; `cat` is the avatar index 0-7.
public struct Person: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var cat: Int

    public init(id: String, name: String, cat: Int) {
        self.id = id
        self.name = name
        self.cat = cat
    }
}

public enum Presence: String, Codable, Sendable { case awake, away, asleep }
public enum SeatKind: String, Codable, Sendable { case open, closed, human, bot }
public enum RoomStatus: String, Codable, Sendable { case lobby, playing, over }
public enum TurnStep: String, Codable, Sendable { case draw, play }
public enum GameStatus: String, Codable, Sendable { case playing, roundOver, gameOver }
public enum DrawSource: String, Codable, Sendable { case deck, discard }

/// One lobby/table seat. `person` is absent (not null) for open, closed and
/// bot seats; `presence` is null for non-human seats.
public struct SeatView: Codable, Equatable, Sendable {
    public var kind: SeatKind
    public var person: Person?
    public var yours: Bool
    public var presence: Presence?

    public init(kind: SeatKind, person: Person? = nil, yours: Bool = false, presence: Presence? = nil) {
        self.kind = kind
        self.person = person
        self.yours = yours
        self.presence = presence
    }
}

/// Where a hit lands: seat `seat`'s laid group number `group`.
public struct HitTarget: Codable, Hashable, Sendable {
    public var seat: Seat
    public var group: Int

    public init(seat: Seat, group: Int) {
        self.seat = seat
        self.group = group
    }
}

/// Which end of a run a hit goes on: `start` below its lowest card, `end` above its highest.
public enum HitSide: String, Codable, Sendable {
    case start, end
}

/// What this device may see of a game. `hands` holds only the seats this
/// device controls; on the wire it is a JSON object keyed by seat number as a
/// string.
public struct GameView: Codable, Equatable, Sendable {
    public var round: Int
    public var dealer: Seat
    public var turn: Seat
    public var step: TurnStep
    public var status: GameStatus
    public var deckCount: Int
    public var discardTop: CardID?
    public var discardCount: Int
    public var phase: [Int]
    public var scores: [Int]
    public var laid: [[Group]?]
    public var handCounts: [Int]
    public var hands: [Seat: [CardID]]
    public var pendingSkip: [Bool]
    public var winners: [Seat]

    public init(
        round: Int, dealer: Seat, turn: Seat, step: TurnStep, status: GameStatus, deckCount: Int,
        discardTop: CardID?, discardCount: Int, phase: [Int], scores: [Int], laid: [[Group]?],
        handCounts: [Int], hands: [Seat: [CardID]], pendingSkip: [Bool], winners: [Seat]
    ) {
        self.round = round
        self.dealer = dealer
        self.turn = turn
        self.step = step
        self.status = status
        self.deckCount = deckCount
        self.discardTop = discardTop
        self.discardCount = discardCount
        self.phase = phase
        self.scores = scores
        self.laid = laid
        self.handCounts = handCounts
        self.hands = hands
        self.pendingSkip = pendingSkip
        self.winners = winners
    }

    private enum CodingKeys: String, CodingKey {
        case round, dealer, turn, step, status, deckCount, discardTop, discardCount, phase, scores
        case laid, handCounts, hands, pendingSkip, winners
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        round = try c.decode(Int.self, forKey: .round)
        dealer = try c.decode(Seat.self, forKey: .dealer)
        turn = try c.decode(Seat.self, forKey: .turn)
        step = try c.decode(TurnStep.self, forKey: .step)
        status = try c.decode(GameStatus.self, forKey: .status)
        deckCount = try c.decode(Int.self, forKey: .deckCount)
        discardTop = try c.decodeIfPresent(CardID.self, forKey: .discardTop)
        discardCount = try c.decode(Int.self, forKey: .discardCount)
        phase = try c.decode([Int].self, forKey: .phase)
        scores = try c.decode([Int].self, forKey: .scores)
        laid = try c.decode([[Group]?].self, forKey: .laid)
        handCounts = try c.decode([Int].self, forKey: .handCounts)
        hands = try c.decode(StringKeyedSeats.self, forKey: .hands).hands
        pendingSkip = try c.decode([Bool].self, forKey: .pendingSkip)
        winners = try c.decode([Seat].self, forKey: .winners)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(round, forKey: .round)
        try c.encode(dealer, forKey: .dealer)
        try c.encode(turn, forKey: .turn)
        try c.encode(step, forKey: .step)
        try c.encode(status, forKey: .status)
        try c.encode(deckCount, forKey: .deckCount)
        try c.encode(discardTop, forKey: .discardTop)  // null when the pile is empty
        try c.encode(discardCount, forKey: .discardCount)
        try c.encode(phase, forKey: .phase)
        try c.encode(scores, forKey: .scores)
        try c.encode(laid, forKey: .laid)
        try c.encode(handCounts, forKey: .handCounts)
        try c.encode(StringKeyedSeats(hands: hands), forKey: .hands)
        try c.encode(pendingSkip, forKey: .pendingSkip)
        try c.encode(winners, forKey: .winners)
    }
}

/// `[Seat: [CardID]]` as a JSON object with string keys.
private struct StringKeyedSeats: Codable {
    var hands: [Seat: [CardID]]

    init(hands: [Seat: [CardID]]) { self.hands = hands }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: [CardID]].self)
        var hands: [Seat: [CardID]] = [:]
        for (key, cards) in raw {
            guard let seat = Int(key) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath, debugDescription: "hands key is not a seat number: \(key)"))
            }
            hands[seat] = cards
        }
        self.hands = hands
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: hands.map { (String($0.key), $0.value) }))
    }
}

public struct RoomView: Codable, Equatable, Sendable {
    public var code: String
    /// The table's name. Every current server sends one; nil only from a server older than names.
    public var name: String?
    public var status: RoomStatus
    public var youAreHost: Bool
    public var seats: [SeatView]
    public var game: GameView?
    /// The table's rug and card back; nil from a server without looks (streaks off).
    public var look: Look?
    /// The Play again table's code, once someone dealt it (§10.4).
    public var rematch: String?

    public init(
        code: String, name: String? = nil, status: RoomStatus, youAreHost: Bool, seats: [SeatView],
        game: GameView? = nil, look: Look? = nil, rematch: String? = nil
    ) {
        self.code = code
        self.name = name
        self.status = status
        self.youAreHost = youAreHost
        self.seats = seats
        self.game = game
        self.look = look
        self.rematch = rematch
    }

    /// The name to show: the table's own, or `TableName.fallback` from an older server.
    public var title: String { name ?? TableName.fallback(code: code) }
}
