/// One legal hit for a picked card, as a phone whose table is on a TV lists it (the hit list on
/// Cards): the group, what kind it is, whose, and how much its label has to say to be told apart
/// from the others listed. The words are the app's (`HitList`).
public struct HitChoice: Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        /// A set of `value`s ("Mom's 3s").
        case set(value: Int)
        /// A run from `start` up ("Your run", "Ava's run of 7s").
        case run(start: Int)
        /// One coat ("Leo's tabbies").
        case coat(Coat)
    }

    /// How much the label says. A set always names its number and a coat its coat; a run names
    /// its start only when its owner has another run listed. `ordinal` (1, 2, …) is the last
    /// resort, for two groups that would still read the same.
    public enum Detail: Equatable, Hashable, Sendable {
        case plain
        case number
        case ordinal(Int)
    }

    public let target: HitTarget
    public let kind: Kind
    /// The picking seat's own group ("Your …").
    public let mine: Bool
    public let detail: Detail

    public init(target: HitTarget, kind: Kind, mine: Bool, detail: Detail) {
        self.target = target
        self.kind = kind
        self.mine = mine
        self.detail = detail
    }
}

public enum HitChoices {
    /// The groups `card` can hit for `seat` (`TableModel.hitTargets`, the table's own rule): the
    /// seat's own first, then the others in turn order after it, each owner's in laid order.
    public static func choices(model: TableModel, card: CardID, seat: Seat) -> [HitChoice] {
        choices(model: model, targets: model.hitTargets(card: card, seat: seat), seat: seat)
    }

    /// `targets` (some of `model`'s laid groups) as a list for `seat` to pick from.
    public static func choices(model: TableModel, targets: [HitTarget], seat: Seat) -> [HitChoice] {
        guard let game = model.game else { return [] }
        let n = max(game.laid.count, 1)
        let ordered = targets.sorted { a, b in
            let ra = (a.seat - seat + n) % n, rb = (b.seat - seat + n) % n
            return ra != rb ? ra < rb : a.group < b.group
        }
        let groups: [(HitTarget, HitChoice.Kind)] = ordered.compactMap { target in
            guard game.laid.indices.contains(target.seat), let laid = game.laid[target.seat],
                  laid.indices.contains(target.group) else { return nil }
            return (target, kind(laid[target.group]))
        }
        // A run names its start when its owner has another run listed.
        var runs: [Seat: Int] = [:]
        for (target, kind) in groups { if case .run = kind { runs[target.seat, default: 0] += 1 } }
        let first: [(HitTarget, HitChoice.Kind, HitChoice.Detail)] = groups.map { target, kind in
            if case .run = kind { return (target, kind, (runs[target.seat] ?? 0) > 1 ? .number : .plain) }
            return (target, kind, .number)
        }
        // Still the same words (two sets of 9s of one owner): numbered in list order.
        var seen: [Key: Int] = [:]
        var total: [Key: Int] = [:]
        for (target, kind, detail) in first { total[Key(target.seat, kind, detail), default: 0] += 1 }
        return first.map { target, kind, detail in
            let key = Key(target.seat, kind, detail)
            var shown = detail
            if (total[key] ?? 0) > 1 {
                seen[key, default: 0] += 1
                shown = .ordinal(seen[key] ?? 1)
            }
            return HitChoice(target: target, kind: kind, mine: target.seat == seat, detail: shown)
        }
    }

    /// What a label with this much detail says, as a comparable value.
    private struct Key: Hashable {
        let owner: Seat
        let kind: HitChoice.Kind?
        init(_ owner: Seat, _ kind: HitChoice.Kind, _ detail: HitChoice.Detail) {
            self.owner = owner
            // A plain run says only "run": every plain run of one owner reads the same.
            if case .run = kind, detail == .plain { self.kind = nil } else { self.kind = kind }
        }
    }

    private static func kind(_ group: Group) -> HitChoice.Kind {
        switch group {
        case .set(_, let value): .set(value: value)
        case .run(_, let start, _): .run(start: start)
        case .coat(_, let coat): .coat(coat)
        }
    }
}
