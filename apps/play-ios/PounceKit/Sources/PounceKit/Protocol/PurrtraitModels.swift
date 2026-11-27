import Foundation

// Purrtrait's wire (docs/superpowers/specs/2026-11-26-purrtrait-design.md §6, §10, and the server
// plan's "Wire contract"). The TV is the easel; the drawer's device sends ink; nobody types.

/// Where a Purrtrait turn stands.
public enum PurrPhase: String, Codable, Sendable {
    /// The drawer picks one of two words (10 seconds).
    case choosing
    case drawing
    /// The word on the TV for a few seconds, before the next drawer.
    case reveal
    case over
}

/// How hard a word is to draw: Easy scores 1, Tricky 2.
public enum PurrLevel: String, Codable, Sendable, CaseIterable {
    case easy, tricky

    public var points: Int { self == .easy ? 1 : 2 }
}

/// A word's group, the one hint the TV shows. A group this build doesn't know decodes as `other`,
/// never as a broken room.
public enum PurrGroup: String, Codable, Sendable, CaseIterable {
    case animals, food, home, outside, things, actions, jobs, places
    case other

    public init(from decoder: any Decoder) throws {
        self = PurrGroup(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }
}

/// The lobby's one choice: seconds a turn.
public enum PurrTimer: Int, Codable, Sendable, CaseIterable {
    case short = 45
    case normal = 60
    case long = 90

    public static let standard: PurrTimer = .normal
}

/// The turn that just ended: its word (now public), who got it (nil: nobody) and the points.
public struct PurrLast: Codable, Equatable, Sendable {
    public var word: String
    public var guesser: Seat?
    public var points: Int

    public init(word: String, guesser: Seat?, points: Int) {
        self.word = word
        self.guesser = guesser
        self.points = points
    }

    private enum CodingKeys: String, CodingKey { case word, guesser, points }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word)
        guesser = try c.decodeIfPresent(Seat.self, forKey: .guesser)
        points = try c.decode(Int.self, forKey: .points)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(word, forKey: .word)
        try c.encode(guesser, forKey: .guesser)  // null when nobody got it
        try c.encode(points, forKey: .points)
    }
}

/// The two words the drawer picks from. Only the devices that control the drawer's seat get them.
public struct PurrChoices: Codable, Equatable, Sendable {
    public var easy: String
    public var tricky: String

    public init(easy: String, tricky: String) {
        self.easy = easy
        self.tricky = tricky
    }

    public func word(_ level: PurrLevel) -> String { level == .easy ? easy : tricky }
}

/// What this device may see of a Purrtrait game. The word is only ever on the drawer's device
/// (`word`, `youDraw`) until the reveal (`last`).
public struct PurrView: Codable, Equatable, Sendable {
    public var seats: Int
    public var timer: Int
    public var rounds: Int
    public var phase: PurrPhase
    /// 1 or 2.
    public var round: Int
    /// Nil once the game is over.
    public var drawer: Seat?
    /// The drawing order: the seats still in.
    public var order: [Seat]
    public var scores: [Int]
    public var out: [Bool]
    /// Set once a word is chosen.
    public var group: PurrGroup?
    public var level: PurrLevel?
    /// The phase's clock when the snapshot was sent; counted down locally.
    public var remainingMs: Int?
    /// No TV connected: the clock is stopped.
    public var paused: Bool
    /// The turn's key, echoed in every `ink`.
    public var turn: String
    public var last: PurrLast?
    public var winners: [Seat]
    /// Choosing, on a device that controls the drawer's seat.
    public var choices: PurrChoices?
    /// Drawing, on the drawer's device only.
    public var word: String?
    /// This device owns the drawing turn.
    public var youDraw: Bool

    public init(
        seats: Int, timer: Int = 60, rounds: Int = 2, phase: PurrPhase, round: Int = 1, drawer: Seat?, order: [Seat],
        scores: [Int], out: [Bool]? = nil, group: PurrGroup? = nil, level: PurrLevel? = nil, remainingMs: Int? = nil,
        paused: Bool = false, turn: String = "1:0", last: PurrLast? = nil, winners: [Seat] = [], choices: PurrChoices? = nil,
        word: String? = nil, youDraw: Bool = false
    ) {
        self.seats = seats
        self.timer = timer
        self.rounds = rounds
        self.phase = phase
        self.round = round
        self.drawer = drawer
        self.order = order
        self.scores = scores
        self.out = out ?? Array(repeating: false, count: seats)
        self.group = group
        self.level = level
        self.remainingMs = remainingMs
        self.paused = paused
        self.turn = turn
        self.last = last
        self.winners = winners
        self.choices = choices
        self.word = word
        self.youDraw = youDraw
    }

    private enum CodingKeys: String, CodingKey {
        case seats, timer, rounds, phase, round, drawer, order, scores, out, group, level, remainingMs, paused, turn
        case last, winners, choices, word, youDraw
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seats = try c.decode(Int.self, forKey: .seats)
        timer = try c.decodeIfPresent(Int.self, forKey: .timer) ?? PurrTimer.standard.rawValue
        rounds = try c.decodeIfPresent(Int.self, forKey: .rounds) ?? 2
        phase = try c.decode(PurrPhase.self, forKey: .phase)
        round = try c.decodeIfPresent(Int.self, forKey: .round) ?? 1
        drawer = try c.decodeIfPresent(Seat.self, forKey: .drawer)
        order = try c.decodeIfPresent([Seat].self, forKey: .order) ?? []
        scores = try c.decode([Int].self, forKey: .scores)
        out = try c.decodeIfPresent([Bool].self, forKey: .out) ?? Array(repeating: false, count: seats)
        group = try c.decodeIfPresent(PurrGroup.self, forKey: .group)
        level = (try? c.decodeIfPresent(String.self, forKey: .level)).flatMap(PurrLevel.init(rawValue:))
        remainingMs = try c.decodeMillis(forKey: .remainingMs)
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        turn = try c.decodeIfPresent(String.self, forKey: .turn) ?? ""
        last = try c.decodeIfPresent(PurrLast.self, forKey: .last)
        winners = try c.decodeIfPresent([Seat].self, forKey: .winners) ?? []
        choices = try c.decodeIfPresent(PurrChoices.self, forKey: .choices)
        word = try c.decodeIfPresent(String.self, forKey: .word)
        youDraw = try c.decodeIfPresent(Bool.self, forKey: .youDraw) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seats, forKey: .seats)
        try c.encode(timer, forKey: .timer)
        try c.encode(rounds, forKey: .rounds)
        try c.encode(phase, forKey: .phase)
        try c.encode(round, forKey: .round)
        try c.encode(drawer, forKey: .drawer)
        try c.encode(order, forKey: .order)
        try c.encode(scores, forKey: .scores)
        try c.encode(out, forKey: .out)
        try c.encode(group, forKey: .group)
        try c.encode(level, forKey: .level)
        try c.encode(remainingMs, forKey: .remainingMs)
        try c.encode(paused, forKey: .paused)
        try c.encode(turn, forKey: .turn)
        try c.encode(last, forKey: .last)
        try c.encode(winners, forKey: .winners)
        try c.encodeIfPresent(choices, forKey: .choices)
        try c.encodeIfPresent(word, forKey: .word)
        if youDraw { try c.encode(true, forKey: .youDraw) }
    }

    /// The game is still going.
    public var isLive: Bool { phase != .over }

    /// True when `seat` left or was removed.
    public func isOut(_ seat: Seat) -> Bool { out.indices.contains(seat) && out[seat] }

    /// Who draws after the current drawer, in `order` (nil on the game's last turn or once over).
    public var nextDrawer: Seat? {
        guard let drawer, let i = order.firstIndex(of: drawer), !order.isEmpty else { return nil }
        let lastTurn = round >= rounds && i == order.count - 1
        guard !lastTurn else { return nil }
        return order[(i + 1) % order.count]
    }
}

/// The TV's join key (`room.near`, the screen's snapshot only): the QR's `near=<key>` and the
/// 8-character typed fallback, good for 30 to 60 seconds.
public struct RoomNear: Codable, Equatable, Sendable {
    public var key: String
    /// The room code plus the key's first 3 characters, as one 8-character code.
    public var code: String
    /// Milliseconds until a new key, from the snapshot.
    public var expiresIn: Int

    public init(key: String, code: String, expiresIn: Int) {
        self.key = key
        self.code = code
        self.expiresIn = expiresIn
    }

    private enum CodingKeys: String, CodingKey { case key, code, expiresIn }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        expiresIn = try c.decodeMillis(forKey: .expiresIn) ?? 30_000
    }
}

/// A Purrtrait move (`act`'s `action`). `timeUp` and `nextTurn` are the room's own, never sent.
public enum PurrAction: Encodable, Equatable, Sendable {
    case choose(PurrLevel)
    case gotIt(Seat)
    case giveUp
    case forfeit

    private enum CodingKeys: String, CodingKey { case type, level, seat }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .choose(let level):
            try c.encode("choose", forKey: .type)
            try c.encode(level, forKey: .level)
        case .gotIt(let seat):
            try c.encode("gotIt", forKey: .type)
            try c.encode(seat, forKey: .seat)
        case .giveUp:
            try c.encode("giveUp", forKey: .type)
        case .forfeit:
            try c.encode("forfeit", forKey: .type)
        }
    }
}

/// Why a turn ended with nobody scoring.
public enum PurrMissReason: String, Codable, Sendable {
    case time, gaveUp, left
    case other

    public init(from decoder: any Decoder) throws {
        self = PurrMissReason(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }
}

/// A Purrtrait event (`{"kind":"purrtrait","event":{…}}`).
public enum PurrEvent: Codable, Equatable, Sendable {
    case turn(drawer: Seat, round: Int)
    case chosen(drawer: Seat, group: PurrGroup, level: PurrLevel)
    case guessed(drawer: Seat, guesser: Seat, points: Int, word: String)
    case missed(drawer: Seat, word: String, reason: PurrMissReason)
    case over(winners: [Seat], scores: [Int])
    /// A type this build doesn't know: skipped, the snapshot after it carries the truth.
    case unknown(String)

    private enum CodingKeys: String, CodingKey { case type, drawer, round, group, level, guesser, points, word, reason, winners, scores }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "turn":
            self = .turn(drawer: try c.decode(Seat.self, forKey: .drawer), round: try c.decode(Int.self, forKey: .round))
        case "chosen":
            self = .chosen(drawer: try c.decode(Seat.self, forKey: .drawer), group: try c.decode(PurrGroup.self, forKey: .group),
                           level: try c.decode(PurrLevel.self, forKey: .level))
        case "guessed":
            self = .guessed(drawer: try c.decode(Seat.self, forKey: .drawer), guesser: try c.decode(Seat.self, forKey: .guesser),
                            points: try c.decode(Int.self, forKey: .points), word: try c.decode(String.self, forKey: .word))
        case "missed":
            self = .missed(drawer: try c.decode(Seat.self, forKey: .drawer), word: try c.decode(String.self, forKey: .word),
                           reason: try c.decode(PurrMissReason.self, forKey: .reason))
        case "over":
            self = .over(winners: try c.decode([Seat].self, forKey: .winners), scores: try c.decode([Int].self, forKey: .scores))
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .turn(let drawer, let round):
            try c.encode("turn", forKey: .type)
            try c.encode(drawer, forKey: .drawer)
            try c.encode(round, forKey: .round)
        case .chosen(let drawer, let group, let level):
            try c.encode("chosen", forKey: .type)
            try c.encode(drawer, forKey: .drawer)
            try c.encode(group, forKey: .group)
            try c.encode(level, forKey: .level)
        case .guessed(let drawer, let guesser, let points, let word):
            try c.encode("guessed", forKey: .type)
            try c.encode(drawer, forKey: .drawer)
            try c.encode(guesser, forKey: .guesser)
            try c.encode(points, forKey: .points)
            try c.encode(word, forKey: .word)
        case .missed(let drawer, let word, let reason):
            try c.encode("missed", forKey: .type)
            try c.encode(drawer, forKey: .drawer)
            try c.encode(word, forKey: .word)
            try c.encode(reason, forKey: .reason)
        case .over(let winners, let scores):
            try c.encode("over", forKey: .type)
            try c.encode(winners, forKey: .winners)
            try c.encode(scores, forKey: .scores)
        case .unknown(let type):
            try c.encode(type, forKey: .type)
        }
    }
}

// MARK: ink

/// A point on the easel's 768 × 1024 grid, or a step between two (on the wire, two integers).
public struct InkPoint: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public static func + (a: InkPoint, b: InkPoint) -> InkPoint { InkPoint(a.x + b.x, a.y + b.y) }
    public static func - (a: InkPoint, b: InkPoint) -> InkPoint { InkPoint(a.x - b.x, a.y - b.y) }
}

/// One ink op as it goes over the wire (spec §6.2): JSON arrays led by a one-letter tag.
/// `["s", id, colour, width, x, y, dx, dy, …]`, `["p", id, dx, dy, …]`, `["u", id]`, `["c"]`.
/// Deltas run from the stroke's previous point.
public enum InkOp: Codable, Equatable, Sendable {
    case stroke(id: Int, color: Int, width: Int, start: InkPoint, deltas: [InkPoint])
    case extend(id: Int, deltas: [InkPoint])
    case undo(id: Int)
    case clear

    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let tag = try c.decode(String.self)
        func ints() throws -> [Int] {
            var out: [Int] = []
            while !c.isAtEnd { out.append(try c.decode(Int.self)) }
            return out
        }
        func pairs(_ flat: ArraySlice<Int>) throws -> [InkPoint] {
            guard flat.count.isMultiple(of: 2) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "ink: an odd number of coordinates")
            }
            var out: [InkPoint] = []
            out.reserveCapacity(flat.count / 2)
            var i = flat.startIndex
            while i < flat.endIndex {
                out.append(InkPoint(flat[i], flat[i + 1]))
                i += 2
            }
            return out
        }
        switch tag {
        case "s":
            let n = try ints()
            guard n.count >= 5 else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "ink: a short stroke") }
            self = .stroke(id: n[0], color: n[1], width: n[2], start: InkPoint(n[3], n[4]), deltas: try pairs(n[5...]))
        case "p":
            let n = try ints()
            guard n.count >= 1 else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "ink: no stroke id") }
            self = .extend(id: n[0], deltas: try pairs(n[1...]))
        case "u":
            let n = try ints()
            guard n.count == 1 else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "ink: undo takes one id") }
            self = .undo(id: n[0])
        case "c":
            guard c.isAtEnd else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "ink: clear takes nothing") }
            self = .clear
        default:
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "ink: unknown op \(tag)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.unkeyedContainer()
        switch self {
        case .stroke(let id, let color, let width, let start, let deltas):
            try c.encode("s")
            try c.encode(id)
            try c.encode(color)
            try c.encode(width)
            try c.encode(start.x)
            try c.encode(start.y)
            for d in deltas {
                try c.encode(d.x)
                try c.encode(d.y)
            }
        case .extend(let id, let deltas):
            try c.encode("p")
            try c.encode(id)
            for d in deltas {
                try c.encode(d.x)
                try c.encode(d.y)
            }
        case .undo(let id):
            try c.encode("u")
            try c.encode(id)
        case .clear:
            try c.encode("c")
        }
    }

    /// The points this op adds (a stroke's start counts).
    public var pointCount: Int {
        switch self {
        case .stroke(_, _, _, _, let deltas): deltas.count + 1
        case .extend(_, let deltas): deltas.count
        case .undo, .clear: 0
        }
    }
}

extension KeyedDecodingContainer {
    /// A count of milliseconds: whole, as the server sends them, or with a fraction (a dev server
    /// running its clock fast scales them), rounded. Nil when absent or null.
    fileprivate func decodeMillis(forKey key: Key) throws -> Int? {
        if let whole = try? decodeIfPresent(Int.self, forKey: key) { return whole }
        return try decodeIfPresent(Double.self, forKey: key).map { Int($0.rounded()) }
    }
}
