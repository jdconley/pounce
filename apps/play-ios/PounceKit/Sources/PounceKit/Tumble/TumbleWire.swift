import Foundation

/// Toy Tumble's live wire (`docs/live-protocol.md`, play-api `tumble/wire.ts`): JSON like the rest
/// of the protocol, with events as short arrays. None of it is room state: it is relayed live and
/// never stored. Decoded on `RoomSocket`'s actor, off the main thread, like every message.

/// One event of a box's stream, in order.
public enum TumbleEvent: Codable, Equatable, Sendable {
    /// `["m", n, rot, x, y]`: toy `n` is here. Only the latest goes in a batch.
    case move(n: Int, rot: Int, x: Int, y: Int)
    /// `["l", n, rot, x, y, ms, landed]`: toy `n` set down here at `ms` on the round clock, then the junk `landed` landed.
    case land(n: Int, rot: Int, x: Int, y: Int, ms: Int, landed: [Int])
    /// `["a", id]`: hit `id` applied, or junk `id`'s wait started.
    case ack(id: Int)
    /// `["u", slot, seat]`: the trick in `slot` used on `seat`.
    case use(slot: Int, seat: Int)

    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let tag = try c.decode(String.self)
        switch tag {
        case "m":
            self = .move(n: try c.decode(Int.self), rot: try c.decode(Int.self), x: try c.decode(Int.self), y: try c.decode(Int.self))
        case "l":
            self = .land(
                n: try c.decode(Int.self), rot: try c.decode(Int.self), x: try c.decode(Int.self), y: try c.decode(Int.self),
                ms: try c.decode(Int.self), landed: try c.decode([Int].self))
        case "a":
            self = .ack(id: try c.decode(Int.self))
        case "u":
            self = .use(slot: try c.decode(Int.self), seat: try c.decode(Int.self))
        default:
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown tumble event \(tag)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.unkeyedContainer()
        switch self {
        case .move(let n, let rot, let x, let y):
            try c.encode("m")
            try c.encode(n)
            try c.encode(rot)
            try c.encode(x)
            try c.encode(y)
        case .land(let n, let rot, let x, let y, let ms, let landed):
            try c.encode("l")
            try c.encode(n)
            try c.encode(rot)
            try c.encode(x)
            try c.encode(y)
            try c.encode(ms)
            try c.encode(landed)
        case .ack(let id):
            try c.encode("a")
            try c.encode(id)
        case .use(let slot, let seat):
            try c.encode("u")
            try c.encode(slot)
            try c.encode(seat)
        }
    }
}

/// `{ t: "tumble", r, s, q, ev }`: one box's checked events, relayed to every other device and screen.
public struct TumbleRelay: Codable, Equatable, Sendable {
    public var r: Int
    public var s: Int
    public var q: Int
    public var ev: [TumbleEvent]
    public init(r: Int, s: Int, q: Int, ev: [TumbleEvent]) {
        self.r = r
        self.s = s
        self.q = q
        self.ev = ev
    }
}

/// A hit's kind: a trick, junk from a clear, or `napped` (a trick spent on a napping box, for the animation only).
public enum TumbleHitKind: String, Codable, Sendable, CaseIterable {
    case junk, hairball, swipe, catnip, scoop, settle, nap, bath, swap, napped
}

/// `{ t: "tumbleHit", r, id, from, to, k, x }`.
public struct TumbleHitWire: Equatable, Sendable {
    public var r: Int
    public var id: Int
    public var from: Int
    public var to: Int
    public var k: TumbleHitKind
    /// For `junk`: its rows and gap.
    public var junk: TumbleWaiting?
    /// For a trick: what it does to the target's box. Nil for `junk` and `napped`.
    public var hit: TumbleHit?

    public init(r: Int, id: Int, from: Int, to: Int, k: TumbleHitKind, junk: TumbleWaiting? = nil, hit: TumbleHit? = nil) {
        self.r = r
        self.id = id
        self.from = from
        self.to = to
        self.k = k
        self.junk = junk
        self.hit = hit
    }

    /// The trick this hit is, for the animation (nil for junk and `napped`).
    public var trick: TumbleTrick? { TumbleTrick(rawValue: k.rawValue) }

    private enum Keys: String, CodingKey { case r, id, from, to, k, x }
    private enum X: String, CodingKey { case rows, gap, shifts, cells, tricks }

    init(from c: KeyedDecodingContainer<ServerMessage.TumbleKeys>) throws {
        r = try c.decode(Int.self, forKey: .r)
        id = try c.decode(Int.self, forKey: .id)
        from = try c.decode(Int.self, forKey: .from)
        to = try c.decode(Int.self, forKey: .to)
        k = try c.decode(TumbleHitKind.self, forKey: .k)
        junk = nil
        hit = nil
        let x = try? c.nestedContainer(keyedBy: X.self, forKey: .x)
        switch k {
        case .junk:
            guard let x else { throw DecodingError.keyNotFound(ServerMessage.TumbleKeys.x, .init(codingPath: c.codingPath, debugDescription: "junk without x")) }
            junk = TumbleWaiting(id: id, rows: try x.decode(Int.self, forKey: .rows), gap: try x.decode(Int.self, forKey: .gap))
        case .hairball:
            guard let x else { throw DecodingError.keyNotFound(ServerMessage.TumbleKeys.x, .init(codingPath: c.codingPath, debugDescription: "hairball without x")) }
            hit = .hairball(gap: try x.decode(Int.self, forKey: .gap))
        case .swipe:
            guard let x else { throw DecodingError.keyNotFound(ServerMessage.TumbleKeys.x, .init(codingPath: c.codingPath, debugDescription: "swipe without x")) }
            hit = .swipe(shifts: try x.decode([Int].self, forKey: .shifts))
        case .swap:
            guard let x else { throw DecodingError.keyNotFound(ServerMessage.TumbleKeys.x, .init(codingPath: c.codingPath, debugDescription: "swap without x")) }
            hit = .swap(cells: try x.decode([Int].self, forKey: .cells), tricks: try x.decode([Int].self, forKey: .tricks))
        case .catnip: hit = .catnip
        case .scoop: hit = .scoop
        case .settle: hit = .settle
        case .nap: hit = .nap
        case .bath: hit = .bath
        case .napped: break
        }
    }
}

/// One whole box in a `tumbleSync`.
public struct TumbleBoxSync: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case ok, lag, out }
    public var s: Int
    public var box: TumbleBox
    /// The last `q` relayed for this box.
    public var q: Int
    /// For each waiting junk, in order, the ms left of its 2-second wait.
    public var waitingLeft: [Double]
    public var catnipLeft: Double
    public var napLeft: Double
    public var status: Status

    public init(s: Int, box: TumbleBox, q: Int, waitingLeft: [Double] = [], catnipLeft: Double = 0, napLeft: Double = 0, status: Status = .ok) {
        self.s = s
        self.box = box
        self.q = q
        self.waitingLeft = waitingLeft
        self.catnipLeft = catnipLeft
        self.napLeft = napLeft
        self.status = status
    }
}

/// `{ t: "tumbleSync", r, boxes }`.
public struct TumbleSync: Codable, Equatable, Sendable {
    public var r: Int
    public var boxes: [TumbleBoxSync]
    public init(r: Int, boxes: [TumbleBoxSync]) {
        self.r = r
        self.boxes = boxes
    }
}

/// `{ t: "tumbleSeat", r, s, st }`: a seat's device is lagging (`lag`) or back (`ok`).
public struct TumbleSeat: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case ok, lag }
    public var r: Int
    public var s: Int
    public var st: State
    public init(r: Int, s: Int, st: State) {
        self.r = r
        self.s = s
        self.st = st
    }
}

/// Every live Toy Tumble message the server sends.
public enum TumbleMessage: Equatable, Sendable {
    case relay(TumbleRelay)
    case hit(TumbleHitWire)
    case sync(TumbleSync)
    case seat(TumbleSeat)

    public var round: Int {
        switch self {
        case .relay(let m): m.r
        case .hit(let m): m.r
        case .sync(let m): m.r
        case .seat(let m): m.r
        }
    }
}

/// Toy Tumble's actions in the room's `act` envelope (the server plan's Task 6): `{k:"leave"}`
/// leaves the game for good (its `forfeitAction`), and the host's `{k:"playWithout"}` seats a
/// missing player as Away after 20 seconds of waiting.
public enum TumbleAction: String, Codable, Equatable, Sendable {
    case leave, playWithout

    private enum Keys: String, CodingKey { case k }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(rawValue, forKey: .k)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard let a = TumbleAction(rawValue: try c.decode(String.self, forKey: .k)) else {
            throw DecodingError.dataCorruptedError(forKey: .k, in: c, debugDescription: "unknown tumble action")
        }
        self = a
    }
}

// MARK: - Room state: the snapshot's `tumble` field

/// The House Cats' level (spec §6.9), the room's `cats` option.
public enum TumbleCats: String, Codable, Sendable, CaseIterable {
    case easy, quick
}

/// `room.tumble`: the slow state of a Toy Tumble game, with a `seq` like every game's.
public struct TumbleView: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case countdown, playing, between, over }

    public var seats: Int
    public var cats: TumbleCats
    public var wins: [Int]
    public var left: [Bool]
    public var away: [Bool]
    public var status: Status
    public var r: Int
    /// Server time (ms since 1970) the round starts: the end of the 3-2-1.
    public var startsAt: Double?
    public var roundSeed: [UInt32]?
    public var trickSeeds: [[UInt32]]?
    /// The seats out this round, in order.
    public var outs: [Int]
    /// The round's winner, once it ends; nil for a round nobody won.
    public var winner: Int?
    /// When a countdown began waiting for a missing device.
    public var waitingSince: Double?

    public init(
        seats: Int, cats: TumbleCats = .easy, wins: [Int], left: [Bool]? = nil, away: [Bool]? = nil, status: Status, r: Int,
        startsAt: Double? = nil, roundSeed: [UInt32]? = nil, trickSeeds: [[UInt32]]? = nil, outs: [Int] = [], winner: Int? = nil,
        waitingSince: Double? = nil
    ) {
        self.seats = seats
        self.cats = cats
        self.wins = wins
        self.left = left ?? Array(repeating: false, count: seats)
        self.away = away ?? Array(repeating: false, count: seats)
        self.status = status
        self.r = r
        self.startsAt = startsAt
        self.roundSeed = roundSeed
        self.trickSeeds = trickSeeds
        self.outs = outs
        self.winner = winner
        self.waitingSince = waitingSince
    }

    private enum CodingKeys: String, CodingKey {
        case seats, cats, wins, left, away, status, r, startsAt, roundSeed, trickSeeds, outs, winner, waitingSince
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seats = try c.decode(Int.self, forKey: .seats)
        // A level this build doesn't know reads as Easy, never as a broken room.
        cats = (try? c.decodeIfPresent(TumbleCats.self, forKey: .cats)) ?? .easy
        wins = try c.decodeIfPresent([Int].self, forKey: .wins) ?? Array(repeating: 0, count: seats)
        left = try c.decodeIfPresent([Bool].self, forKey: .left) ?? Array(repeating: false, count: seats)
        away = try c.decodeIfPresent([Bool].self, forKey: .away) ?? Array(repeating: false, count: seats)
        status = try c.decode(Status.self, forKey: .status)
        r = try c.decodeIfPresent(Int.self, forKey: .r) ?? 0
        startsAt = try c.decodeIfPresent(Double.self, forKey: .startsAt)
        roundSeed = try c.decodeIfPresent([UInt32].self, forKey: .roundSeed)
        trickSeeds = try c.decodeIfPresent([[UInt32]].self, forKey: .trickSeeds)
        outs = try c.decodeIfPresent([Int].self, forKey: .outs) ?? []
        winner = try c.decodeIfPresent(Int.self, forKey: .winner)
        waitingSince = try c.decodeIfPresent(Double.self, forKey: .waitingSince)
    }

    /// The leader's wins, for Home's table card.
    public var topWins: Int { wins.max() ?? 0 }

    /// Seats still in this round: not out, not left, not away.
    public func inRound(_ seat: Int) -> Bool {
        seat >= 0 && seat < seats && !outs.contains(seat) && !(left.indices.contains(seat) && left[seat])
            && !(away.indices.contains(seat) && away[seat])
    }
}
