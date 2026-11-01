/// A greedy phase finder for the e2e driver. Not optimal, but anything it
/// returns has been accepted by `Rules.matchPhase`.
public enum Solver {
    /// Groups in `Rules.phases` order, or nil when no lay-down is found.
    public static func findPhase(hand: [CardID], phaseIndex: Int) -> [LayGroup]? {
        guard Rules.phases.indices.contains(phaseIndex) else { return nil }
        let unique = Array(Set(hand)).sorted()
        let naturals = unique.filter { $0 < 96 }
        let yarns = unique.filter { $0 >= 96 && $0 < 104 }  // never Cucumbers
        guard let groups = search(Rules.phases[phaseIndex][...], naturals: naturals, yarns: yarns),
              Rules.matchPhase(phaseIndex, groups: groups) != nil else { return nil }
        return groups
    }

    /// Hits that can be played in order from `hand` onto `laid` (indexed by
    /// seat). Naturals go first, and each hit extends the working copy so a
    /// later card can build on an earlier one.
    public static func hits(hand: [CardID], laid: [[Group]?]) -> [(card: CardID, target: HitTarget)] {
        var board = laid
        let hittable = hand.filter { $0 < 104 }
        var remaining = hittable.filter { $0 < 96 }.sorted() + hittable.filter { $0 >= 96 }.sorted()
        var result: [(card: CardID, target: HitTarget)] = []
        var progressed = true
        while progressed {
            progressed = false
            for card in remaining {
                if let target = firstTarget(card, board: board),
                   let current = board[target.seat]?[target.group],
                   let extended = Rules.canHit(current, card: card) {
                    board[target.seat]?[target.group] = extended
                    result.append((card, target))
                    remaining.removeAll { $0 == card }
                    progressed = true
                    break
                }
            }
        }
        return result
    }

    private static func firstTarget(_ card: CardID, board: [[Group]?]) -> HitTarget? {
        for (seat, groups) in board.enumerated() {
            for (index, group) in (groups ?? []).enumerated() where Rules.canHit(group, card: card) != nil {
                return HitTarget(seat: seat, group: index)
            }
        }
        return nil
    }

    // MARK: search

    private static func search(_ reqs: ArraySlice<Requirement>, naturals: [CardID], yarns: [CardID]) -> [LayGroup]? {
        guard let req = reqs.first else { return [] }
        for candidate in candidates(for: req, naturals: naturals, yarns: yarns) {
            let used = Set(candidate.cards)
            let rest = search(reqs.dropFirst(), naturals: naturals.filter { !used.contains($0) },
                              yarns: yarns.filter { !used.contains($0) })
            if let rest { return [candidate] + rest }
        }
        return nil
    }

    /// Candidate groups for one requirement, fewest Yarn first.
    private static func candidates(for req: Requirement, naturals: [CardID], yarns: [CardID]) -> [LayGroup] {
        var found: [(yarns: Int, tie: Int, group: LayGroup)] = []
        func add(_ picked: [CardID], need: Int, tie: Int, runStart: Int? = nil, ordered: [CardID]? = nil) {
            guard need <= yarns.count else { return }
            let cards = ordered ?? (picked + yarns.prefix(need))
            found.append((need, tie, LayGroup(cards: cards, runStart: runStart)))
        }

        switch req.kind {
        case .set:
            for value in 1...Rules.maxValue {
                let matching = naturals.filter { $0 % 12 + 1 == value }
                guard !matching.isEmpty else { continue }
                let picked = Array(matching.prefix(req.size))
                add(picked, need: req.size - picked.count, tie: value)
            }
        case .coat:
            for coat in 0..<4 {
                let matching = naturals.filter { $0 / 24 == coat }
                guard !matching.isEmpty else { continue }
                let picked = Array(matching.prefix(req.size))
                // Most-common coat first.
                add(picked, need: req.size - picked.count, tie: -matching.count)
            }
        case .run:
            guard req.size <= Rules.maxValue else { break }
            for start in 1...(Rules.maxValue + 1 - req.size) {
                var cards: [CardID] = []
                var yarnUsed = 0
                var naturalCount = 0
                for value in start..<(start + req.size) {
                    if let natural = naturals.first(where: { $0 % 12 + 1 == value }) {
                        cards.append(natural)
                        naturalCount += 1
                    } else {
                        guard yarnUsed < yarns.count else { break }
                        cards.append(yarns[yarnUsed])
                        yarnUsed += 1
                    }
                }
                guard cards.count == req.size, naturalCount > 0 else { continue }
                add([], need: yarnUsed, tie: start, runStart: start, ordered: cards)
            }
        }
        return found.sorted { ($0.yarns, $0.tie) < ($1.yarns, $1.tie) }.map(\.group)
    }
}
