/// The laid groups a held card can hit, worked out once when it is picked up, and where it
/// would land on each, worked out the first time the finger reaches that group's end. A drag
/// asks on every touch move (60 to 120 times a second); the rules run only when the finger
/// gets somewhere new, never again for the same group and end.
public struct HitAims: Sendable {
    public let card: CardID
    /// `TableModel.hitTargets(card:seat:)`; empty when no seat can act.
    public let targets: Set<HitTarget>

    private let model: TableModel
    private var plans: [Key: HitPlan?] = [:]

    private struct Key: Hashable {
        let target: HitTarget
        let toward: HitSide
    }

    /// How many times the rules ran: `hitTargets` once, plus one plan per group and end the
    /// finger reached that can take the card (for tests and the DEBUG drag profiler).
    public private(set) var ruleRuns = 0

    public init(model: TableModel, card: CardID, seat: Seat?) {
        self.card = card
        self.model = model
        targets = seat.map { Set(model.hitTargets(card: card, seat: $0)) } ?? []
        ruleRuns = 1
    }

    /// `TableModel.hitPlan` for the held card: nil for a group that can't take it.
    public mutating func plan(target: HitTarget, toward: HitSide) -> HitPlan? {
        guard targets.contains(target) else { return nil }
        let key = Key(target: target, toward: toward)
        if let known = plans[key] { return known }
        ruleRuns += 1
        let plan = model.plannedHit(card: card, target: target, toward: toward)
        plans[key] = plan
        return plan
    }
}
