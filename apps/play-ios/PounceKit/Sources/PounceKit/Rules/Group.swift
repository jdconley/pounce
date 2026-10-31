public enum GroupKind: String, Codable, Sendable {
    case set, run, coat
}

public struct Requirement: Equatable, Hashable, Sendable {
    public let kind: GroupKind
    public let size: Int

    public init(kind: GroupKind, size: Int) {
        self.kind = kind
        self.size = size
    }
}

/// A laid-down group. `cards` are in display order: runs ascend, Yarn sits at
/// the value it stands for. JSON shape matches the server exactly.
public enum Group: Equatable, Codable, Sendable {
    case set(cards: [CardID], value: Int)
    case run(cards: [CardID], start: Int, end: Int)
    case coat(cards: [CardID], coat: Coat)

    public var cards: [CardID] {
        switch self {
        case .set(let cards, _), .run(let cards, _, _), .coat(let cards, _): cards
        }
    }

    public var kind: GroupKind {
        switch self {
        case .set: .set
        case .run: .run
        case .coat: .coat
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, cards, value, start, end, coat
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cards = try c.decode([CardID].self, forKey: .cards)
        switch try c.decode(GroupKind.self, forKey: .kind) {
        case .set:
            self = .set(cards: cards, value: try c.decode(Int.self, forKey: .value))
        case .run:
            self = .run(cards: cards, start: try c.decode(Int.self, forKey: .start),
                        end: try c.decode(Int.self, forKey: .end))
        case .coat:
            self = .coat(cards: cards, coat: try c.decode(Coat.self, forKey: .coat))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(cards, forKey: .cards)
        switch self {
        case .set(_, let value):
            try c.encode(value, forKey: .value)
        case .run(_, let start, let end):
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
        case .coat(_, let coat):
            try c.encode(coat, forKey: .coat)
        }
    }
}

/// A group as sent in a lay-down. `runStart` is omitted from JSON when nil.
public struct LayGroup: Codable, Equatable, Sendable {
    public var cards: [CardID]
    public var runStart: Int?

    public init(cards: [CardID], runStart: Int? = nil) {
        self.cards = cards
        self.runStart = runStart
    }
}
