/// Port of `apps/play-api/src/rules/groups.ts` and `phases.ts`. The server is
/// the authority; this only drives client-side glow hints.
public enum Rules {
    static let maxValue = 12

    private static func set(_ size: Int) -> Requirement { Requirement(kind: .set, size: size) }
    private static func run(_ size: Int) -> Requirement { Requirement(kind: .run, size: size) }
    private static func coat(_ size: Int) -> Requirement { Requirement(kind: .coat, size: size) }

    /// The 10 phases; index 0 = phase 1.
    public static let phases: [[Requirement]] = [
        [set(3), set(3)],
        [set(3), run(4)],
        [set(4), run(4)],
        [run(7)],
        [run(8)],
        [run(9)],
        [set(4), set(4)],
        [coat(7)],
        [set(5), set(2)],
        [set(5), set(3)],
    ]

    /// Build a group for `req` from `cards`, or nil if invalid. Needs exactly
    /// `req.size` distinct cards, no Cucumbers and at least one natural card.
    /// For a run containing Yarn, `runStart` (the value of the first card)
    /// picks the placement; without it the lowest start that fits is used.
    public static func buildGroup(_ req: Requirement, cards: [CardID], runStart: Int? = nil) -> Group? {
        guard cards.count == req.size, Set(cards).count == cards.count else { return nil }
        var decoded: [Card] = []
        for id in cards {
            guard let card = Card.decode(id) else { return nil }
            decoded.append(card)
        }
        if decoded.contains(.cucumber) { return nil }
        // (id, value, coat) of each natural, in input order.
        var naturals: [(id: CardID, value: Int, coat: Coat)] = []
        for (id, card) in zip(cards, decoded) {
            if case .number(let value, let coat) = card { naturals.append((id, value, coat)) }
        }
        guard let first = naturals.first else { return nil }

        switch req.kind {
        case .set:
            return naturals.allSatisfy { $0.value == first.value }
                ? .set(cards: cards, value: first.value) : nil
        case .coat:
            return naturals.allSatisfy { $0.coat == first.coat }
                ? .coat(cards: cards, coat: first.coat) : nil
        case .run:
            return buildRun(cards: cards, decoded: decoded, naturals: naturals, runStart: runStart)
        }
    }

    private static func buildRun(
        cards: [CardID],
        decoded: [Card],
        naturals: [(id: CardID, value: Int, coat: Coat)],
        runStart: Int?
    ) -> Group? {
        let size = cards.count
        let values = naturals.map(\.value)
        if Set(values).count != values.count { return nil }
        // A start fits when every natural lies in start..start+size-1 and the
        // whole run stays within 1...12.
        let lowest = max(1, values.max()! - size + 1)
        let highest = min(values.min()!, maxValue + 1 - size)
        let start = runStart ?? lowest
        guard start >= lowest, start <= highest else { return nil }

        var slots = [CardID?](repeating: nil, count: size)
        for n in naturals { slots[n.value - start] = n.id }
        var yarns = zip(cards, decoded).filter { $0.1 == .yarn }.map(\.0)[...]
        let ordered = slots.map { slot in slot ?? yarns.removeFirst() }
        return .run(cards: ordered, start: start, end: start + size - 1)
    }

    /// Whether `card` can be added to a laid-down group. Returns the extended
    /// group (the input is a value and is not mutated), or nil.
    public static func canHit(_ group: Group, card id: CardID) -> Group? {
        guard let card = Card.decode(id), card != .cucumber else { return nil }
        switch group {
        case .set(let cards, let value):
            if case .number(let v, _) = card, v != value { return nil }
            return .set(cards: cards + [id], value: value)
        case .coat(let cards, let coat):
            if case .number(_, let c) = card, c != coat { return nil }
            return .coat(cards: cards + [id], coat: coat)
        case .run(let cards, let start, let end):
            let atEnd = Group.run(cards: cards + [id], start: start, end: end + 1)
            let atStart = Group.run(cards: [id] + cards, start: start - 1, end: end)
            switch card {
            case .number(let value, _):
                if value == end + 1 { return atEnd }
                if value == start - 1 { return atStart }
                return nil
            default: // yarn: extend the end first, else the start
                if end < maxValue { return atEnd }
                return start > 1 ? atStart : nil
            }
        }
    }

    /// Validate a lay-down against a phase. `groups` must be in `phases[phaseIndex]`
    /// order and share no cards. Returns the built groups, or nil if anything is invalid.
    public static func matchPhase(_ phaseIndex: Int, groups: [LayGroup]) -> [Group]? {
        guard phases.indices.contains(phaseIndex) else { return nil }
        let reqs = phases[phaseIndex]
        guard groups.count == reqs.count else { return nil }
        var seen = Set<CardID>()
        var built: [Group] = []
        for (req, g) in zip(reqs, groups) {
            for id in g.cards where !seen.insert(id).inserted { return nil }
            guard let group = buildGroup(req, cards: g.cards, runStart: g.runStart) else { return nil }
            built.append(group)
        }
        return built
    }
}
