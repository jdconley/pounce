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
    /// picks the placement. Without it the cards' own order picks it when that
    /// order is a run (each Yarn keeps the spot the player gave it), else the
    /// lowest start that fits.
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
        let start = runStart ?? startFromOrder(decoded, lowest: lowest, highest: highest) ?? lowest
        guard start >= lowest, start <= highest else { return nil }

        var slots = [CardID?](repeating: nil, count: size)
        for n in naturals { slots[n.value - start] = n.id }
        var yarns = zip(cards, decoded).filter { $0.1 == .yarn }.map(\.0)[...]
        let ordered = slots.map { slot in slot ?? yarns.removeFirst() }
        return .run(cards: ordered, start: start, end: start + size - 1)
    }

    /// The start the cards' order spells out: every natural sits at index `value - start`
    /// for one start in `lowest...highest`. Nil when the order isn't a run.
    private static func startFromOrder(_ decoded: [Card], lowest: Int, highest: Int) -> Int? {
        var start: Int?
        for (i, card) in decoded.enumerated() {
            guard case .number(let value, _) = card else { continue }
            if let start, start != value - i { return nil }
            start = value - i
        }
        guard let start, start >= lowest, start <= highest else { return nil }
        return start
    }

    /// Whether `card` can be added to a laid-down group. Returns the extended
    /// group (the input is a value and is not mutated), or nil. For a run, `side`
    /// pins the end the card goes on and refuses it when that end can't take it;
    /// without it a natural goes where its value fits and a Yarn extends the
    /// end first, else the start. Sets and coats ignore `side`.
    public static func canHit(_ group: Group, card id: CardID, side: HitSide? = nil) -> Group? {
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
            let fitsEnd: Bool, fitsStart: Bool
            if case .number(let value, _) = card {
                (fitsEnd, fitsStart) = (value == end + 1, value == start - 1)
            } else {  // yarn
                (fitsEnd, fitsStart) = (end < maxValue, start > 1)
            }
            switch side {
            case .end: return fitsEnd ? atEnd : nil
            case .start: return fitsStart ? atStart : nil
            case nil: return fitsEnd ? atEnd : fitsStart ? atStart : nil
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
