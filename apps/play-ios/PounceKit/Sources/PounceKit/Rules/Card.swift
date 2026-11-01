/// A card id in 0-107. Ids are the only card representation on the wire.
public typealias CardID = Int
public typealias Seat = Int

public enum Coat: String, Codable, CaseIterable, Sendable {
    case tabby, tuxedo, calico, gray
}

/// Port of `apps/play-api/src/rules/cards.ts`.
///
/// Ids 0-95 are numbers: coat = id / 24, value = id % 12 + 1. 96-103 are Yarn
/// (wild), 104-107 are Cucumber (skip).
public enum Card: Equatable, Sendable {
    case number(value: Int, coat: Coat)
    case yarn
    case cucumber

    public static let deckSize = 108
    static let numberCards = 96
    static let cucumberStart = 104

    /// Decodes a valid id (0..<108). Traps on an out-of-range id; use ``decode(_:)`` for untrusted ids.
    public init(id: CardID) {
        guard let card = Card.decode(id) else { preconditionFailure("invalid card id: \(id)") }
        self = card
    }

    /// Non-trapping decode: nil for ids outside 0..<108 (the server throws RangeError there).
    static func decode(_ id: CardID) -> Card? {
        guard id >= 0, id < deckSize else { return nil }
        if id < numberCards {
            return .number(value: id % 12 + 1, coat: Coat.allCases[id / 24])
        }
        return id < cucumberStart ? .yarn : .cucumber
    }

    /// Scoring: 1-9 = 5, 10-12 = 10, Cucumber = 15, Yarn = 25.
    public static func points(_ id: CardID) -> Int {
        switch Card(id: id) {
        case .yarn: 25
        case .cucumber: 15
        case .number(let value, _): value >= 10 ? 10 : 5
        }
    }
}
