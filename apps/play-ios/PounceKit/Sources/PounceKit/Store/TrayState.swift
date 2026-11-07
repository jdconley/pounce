/// The lay-down trays before a seat lays its phase (spec §5.8): one tray per requirement in
/// the server's phase order, validated live with `Rules`. Local only; the server decides.
///
/// `slots` are in display order. A run tray keeps its naturals ascending. A Yarn keeps the
/// spot the player gave it (dropped there, or moved there with `moveYarn`): in a tray that
/// isn't a run yet it stays beside the same naturals, and once the tray holds a valid run the
/// start that best matches the spots is picked, with each Yarn at the value it stands for. A
/// Yarn with no spot (added by tap) takes the server's default, the lowest start that fits.
public struct TrayState: Equatable, Sendable {
    public let requirements: [Requirement]
    public private(set) var slots: [[CardID]]
    /// The start a valid run tray uses (always sent, so the cards land where the tray shows them).
    private var runStarts: [Int?]
    /// Where the player put each placed Yarn, on the value line: 6.5 is "after the 6", 3 is
    /// "standing for 3". Yarns with no entry have no spot.
    private var spots: [CardID: Double] = [:]

    public init(requirements: [Requirement]) {
        self.requirements = requirements
        slots = Array(repeating: [], count: requirements.count)
        runStarts = Array(repeating: nil, count: requirements.count)
    }

    public var cardsInTrays: Set<CardID> { Set(slots.joined()) }

    /// The tray holding `card`, if any.
    public func tray(of card: CardID) -> Int? {
        slots.firstIndex { $0.contains(card) }
    }

    public func isFull(_ tray: Int) -> Bool {
        guard requirements.indices.contains(tray) else { return true }
        return slots[tray].count >= requirements[tray].size
    }

    /// Puts `card` in `tray`, taking it out of any other tray first. `index` is the display
    /// slot it was dropped on (nil: no spot, as on the tap path); a Yarn dropped in a run tray
    /// keeps that spot. Other trays add at the end. A full tray or a bad tray index leaves
    /// everything as it was.
    public mutating func add(_ card: CardID, to tray: Int, at index: Int? = nil) {
        guard requirements.indices.contains(tray), !slots[tray].contains(card), !isFull(tray) else { return }
        remove(card)
        let run = requirements[tray].kind == .run
        let at = min(max((run ? index : nil) ?? slots[tray].count, 0), slots[tray].count)
        if run, index != nil, Card.decode(card) == .yarn {
            spots[card] = spot(before: at, in: slots[tray])
        }
        slots[tray].insert(card, at: at)
        normalize(tray)
    }

    public mutating func remove(_ card: CardID) {
        spots[card] = nil
        guard let tray = tray(of: card) else { return }
        slots[tray].removeAll { $0 == card }
        normalize(tray)
    }

    /// Drops every tray card that isn't in `hand` (it was played or the hand changed).
    public mutating func keep(only hand: Set<CardID>) {
        for card in cardsInTrays where !hand.contains(card) { remove(card) }
    }

    public func isValid(_ tray: Int) -> Bool { built(tray) != nil }

    public var allValid: Bool {
        !requirements.isEmpty && requirements.indices.allSatisfy(isValid)
    }

    /// The lay-down in phase order. Runs carry their start so the cards land where the tray
    /// shows them.
    public func layGroups() -> [LayGroup] {
        requirements.indices.map { tray in
            guard requirements[tray].kind == .run else { return LayGroup(cards: slots[tray]) }
            if case .run(let cards, let start, _) = built(tray) { return LayGroup(cards: cards, runStart: start) }
            return LayGroup(cards: slots[tray], runStart: runStarts[tray])
        }
    }

    /// A Yarn in a valid run tray, which `moveYarn` can place (the tap path selects it, then a
    /// tap on another slot of that tray moves it there).
    public func canMoveYarn(_ card: CardID, inTray tray: Int) -> Bool {
        guard requirements.indices.contains(tray), requirements[tray].kind == .run,
              Card.decode(card) == .yarn, slots[tray].contains(card) else { return false }
        return isValid(tray)
    }

    /// Moves a Yarn in a valid run tray to display slot `toIndex`, which picks the run's start.
    /// A placement no start allows (or a natural card, or a non-run tray) changes nothing.
    public mutating func moveYarn(_ card: CardID, inTray tray: Int, toIndex index: Int) {
        guard requirements.indices.contains(tray), requirements[tray].kind == .run,
              Card.decode(card) == .yarn, slots[tray].contains(card),
              case .run(_, let current, _) = built(tray) else { return }
        let size = requirements[tray].size
        guard index >= 0, index < size else { return }
        var naturals: [(id: CardID, value: Int)] = []
        for id in slots[tray] {
            if case .number(let value, _) = Card.decode(id) { naturals.append((id, value)) }
        }
        let values = naturals.map(\.value)
        guard let maxValue = values.max(), let minValue = values.min() else { return }
        let lowest = max(1, maxValue - size + 1)
        let highest = min(minValue, Rules.maxValue + 1 - size)
        let fits = (lowest...max(lowest, highest)).filter { start in
            start <= highest && !values.contains(start + index)
        }
        guard let start = fits.min(by: { abs($0 - current) < abs($1 - current) }) else { return }

        var order = [CardID?](repeating: nil, count: size)
        for n in naturals { order[n.value - start] = n.id }
        order[index] = card
        var others = slots[tray].filter { Card.decode($0) == .yarn && $0 != card }[...]
        let cards = order.map { $0 ?? others.removeFirst() }
        slots[tray] = cards
        runStarts[tray] = start
        // Every Yarn in the tray now has the spot it shows: the value it stands for.
        for (i, id) in cards.enumerated() where Card.decode(id) == .yarn { spots[id] = Double(start + i) }
    }

    // MARK: private

    private func built(_ tray: Int) -> Group? {
        guard requirements.indices.contains(tray) else { return nil }
        let req = requirements[tray]
        return Rules.buildGroup(req, cards: slots[tray], runStart: req.kind == .run ? runStarts[tray] : nil)
    }

    /// The spot for a Yarn dropped at display index `at` of `cards`: just after the natural
    /// before it, else just before the natural after it; nil in a tray with no naturals.
    private func spot(before at: Int, in cards: [CardID]) -> Double? {
        func value(_ id: CardID) -> Int? {
            if case .number(let v, _) = Card.decode(id) { v } else { nil }
        }
        if let prev = cards[..<at].reversed().lazy.compactMap(value).first { return Double(prev) + 0.5 }
        if let next = cards[at...].lazy.compactMap(value).first { return Double(next) - 0.5 }
        return nil
    }

    /// A run tray's order. Valid: the run, at the start that best matches the Yarns' spots (a
    /// tie keeps the start it had, else the lowest), placed Yarns at the values nearest their
    /// spots and the others in the remaining gaps. Not yet valid: naturals ascending, each
    /// placed Yarn beside the naturals it was put by, then unplaced Yarns, then anything else.
    private mutating func normalize(_ tray: Int) {
        guard requirements[tray].kind == .run else { return }
        let req = requirements[tray]
        let cards = slots[tray]
        let previous = runStarts[tray]
        runStarts[tray] = nil
        let starts = (1...Rules.maxValue).filter { Rules.buildGroup(req, cards: cards, runStart: $0) != nil }
        guard !starts.isEmpty else {
            func rank(_ id: CardID) -> Double {
                switch Card.decode(id) {
                case .number(let value, _): Double(value)
                case .yarn: spots[id] ?? 100
                default: 200
                }
            }
            slots[tray] = cards.enumerated()
                .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
                .map(\.element)
            return
        }
        var naturals: [Int: CardID] = [:]
        for id in cards { if case .number(let v, _) = Card.decode(id) { naturals[v] = id } }
        let yarns = cards.filter { Card.decode($0) == .yarn }
        let placed = yarns.filter { spots[$0] != nil }.sorted { spots[$0]! < spots[$1]! }
        let unplaced = yarns.filter { spots[$0] == nil }

        var best: (start: Int, cost: Double, picks: [Int])?
        for start in starts {
            let gaps = (start..<start + req.size).filter { naturals[$0] == nil }
            let (cost, picks) = Self.match(placed.map { spots[$0]! }, to: gaps)
            let better = best.map { cost < $0.cost - 1e-9 || (abs(cost - $0.cost) < 1e-9 && start == previous) } ?? true
            if better { best = (start, cost, picks) }
        }
        guard let best else { return }
        var byValue = naturals
        for (yarn, value) in zip(placed, best.picks) { byValue[value] = yarn }
        var rest = unplaced[...]
        slots[tray] = (best.start..<best.start + req.size).map { byValue[$0] ?? rest.removeFirst() }
        runStarts[tray] = best.start
    }

    /// The gaps (ascending) for spots (ascending) that keep their order and are nearest them
    /// in total. A run has at most a handful of gaps, so every choice is tried.
    private static func match(_ spots: [Double], to gaps: [Int]) -> (cost: Double, picks: [Int]) {
        guard !spots.isEmpty else { return (0, []) }
        var best: (cost: Double, picks: [Int]) = (.infinity, [])
        func pick(_ i: Int, from: Int, cost: Double, picks: [Int]) {
            if i == spots.count {
                if cost < best.cost - 1e-9 { best = (cost, picks) }
                return
            }
            guard from < gaps.count else { return }
            for g in from..<gaps.count {
                pick(i + 1, from: g + 1, cost: cost + abs(Double(gaps[g]) - spots[i]), picks: picks + [gaps[g]])
            }
        }
        pick(0, from: 0, cost: 0, picks: [])
        return best
    }
}
