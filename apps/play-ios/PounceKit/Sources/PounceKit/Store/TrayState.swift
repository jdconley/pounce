/// The lay-down trays before a seat lays its phase (spec §5.8): one tray per requirement in
/// the server's phase order, validated live with `Rules`. Local only; the server decides.
///
/// `slots` are in display order. A run tray keeps its cards sorted ascending; once it holds a
/// valid run, each Yarn sits at the value it stands for. Without an explicit `moveYarn` the
/// run uses the server's default placement (the lowest start that fits).
public struct TrayState: Equatable, Sendable {
    public let requirements: [Requirement]
    public private(set) var slots: [[CardID]]
    /// An explicit run start per tray, set by `moveYarn` and cleared by any other change.
    private var runStarts: [Int?]

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

    /// Puts `card` in `tray`, taking it out of any other tray first. A full tray or a bad
    /// index leaves everything as it was.
    public mutating func add(_ card: CardID, to tray: Int) {
        guard requirements.indices.contains(tray), !slots[tray].contains(card), !isFull(tray) else { return }
        remove(card)
        slots[tray].append(card)
        runStarts[tray] = nil
        normalize(tray)
    }

    public mutating func remove(_ card: CardID) {
        guard let tray = tray(of: card) else { return }
        slots[tray].removeAll { $0 == card }
        runStarts[tray] = nil
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

    /// The lay-down in phase order. Runs carry their start (the explicit placement, else the
    /// server's default) so the cards land where the tray shows them.
    public func layGroups() -> [LayGroup] {
        requirements.indices.map { tray in
            guard requirements[tray].kind == .run else { return LayGroup(cards: slots[tray]) }
            if case .run(let cards, let start, _) = built(tray) { return LayGroup(cards: cards, runStart: start) }
            return LayGroup(cards: slots[tray], runStart: runStarts[tray])
        }
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
    }

    // MARK: private

    private func built(_ tray: Int) -> Group? {
        guard requirements.indices.contains(tray) else { return nil }
        let req = requirements[tray]
        return Rules.buildGroup(req, cards: slots[tray], runStart: req.kind == .run ? runStarts[tray] : nil)
    }

    /// Run trays show sorted: the built run when valid, else naturals ascending, then Yarn,
    /// then anything else.
    private mutating func normalize(_ tray: Int) {
        guard requirements[tray].kind == .run else { return }
        if case .run(let cards, _, _) = built(tray) {
            slots[tray] = cards
            return
        }
        func rank(_ id: CardID) -> Int {
            switch Card.decode(id) {
            case .number(let value, _): value
            case .yarn: 100
            default: 200
            }
        }
        slots[tray] = slots[tray].enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }
}
