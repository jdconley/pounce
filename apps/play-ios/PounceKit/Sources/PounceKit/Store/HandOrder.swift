/// Local order of a hand (spec §5.7: sort toggle and free drag-to-reorder). The server's
/// order is only used for cards this order hasn't seen; nothing here is ever sent.
public struct HandOrder: Equatable, Sendable {
    public enum Sort: Equatable, Sendable { case number, coat }

    public private(set) var cards: [CardID] = []
    /// The sort applied last; a manual move clears it.
    public private(set) var sort: Sort?

    public init() {}

    /// Keeps the order of cards still in `hand` and appends new ones in the server's order.
    public mutating func sync(_ hand: [CardID]) {
        var remaining = hand
        var kept: [CardID] = []
        for card in cards {
            if let i = remaining.firstIndex(of: card) {
                kept.append(card)
                remaining.remove(at: i)
            }
        }
        cards = kept + remaining
    }

    /// Moves `card` to just before `before` (nil: the right end).
    public mutating func move(_ card: CardID, before: CardID?) {
        guard card != before, let from = cards.firstIndex(of: card) else { return }
        cards.remove(at: from)
        if let before, let to = cards.firstIndex(of: before) {
            cards.insert(card, at: to)
        } else {
            cards.append(card)
        }
        sort = nil
    }

    /// Number order, then coat order, then number again.
    public mutating func cycleSort() {
        let next: Sort = sort == .number ? .coat : .number
        cards.sort { Self.key($0, next).lexicographicallyPrecedes(Self.key($1, next)) }
        sort = next
    }

    /// Numbers first (by value then coat, or coat then value), then Yarn, then Cucumbers.
    static func key(_ id: CardID, _ sort: Sort) -> [Int] {
        switch Card.decode(id) {
        case .number(let value, let coat):
            let c = Coat.allCases.firstIndex(of: coat) ?? 0
            return sort == .number ? [0, value, c, id] : [0, c, value, id]
        case .yarn: return [1, 0, 0, id]
        default: return [2, 0, 0, id]
        }
    }
}
