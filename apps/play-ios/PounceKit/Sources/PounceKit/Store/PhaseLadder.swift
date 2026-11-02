/// All ten phases with every seat on the one it is working on (the tower sheet): what each
/// player is collecting, at a glance.
public struct PhaseLadder: Equatable, Sendable {
    public struct Rung: Equatable, Sendable {
        /// 0 = phase 1.
        public let index: Int
        /// The phase in plain words (`Rules.describe(phase:)`).
        public let text: String
        /// Seats working on this phase, in seat order.
        public let seats: [Seat]
        /// `focus` is working on this phase.
        public let isFocus: Bool
        /// `focus` has already climbed past this phase.
        public let isDone: Bool
    }

    public let rungs: [Rung]
    /// The seat the ladder is drawn for (highlighted, its done phases checked), or nil on a
    /// phone with no seat.
    public let focus: Seat?
    /// Seats that laid their phase down this round: they climb a shelf when it ends, and
    /// meanwhile only hit.
    public let laid: Set<Seat>

    /// The ladder for `model`'s game. A seat past the last phase sits on the last one, done.
    public init(model: TableModel, focus: Seat?) {
        let phases = model.game?.phase ?? []
        let last = Rules.phases.count - 1
        let laidSeats = model.game?.laid ?? []
        self.focus = focus.flatMap { phases.indices.contains($0) ? $0 : nil }
        laid = Set(phases.indices.filter { seat in
            phases[seat] > last || (laidSeats.indices.contains(seat) && laidSeats[seat] != nil)
        })
        let focusPhase = self.focus.map { phases[$0] }
        rungs = Rules.phases.indices.map { i in
            Rung(
                index: i, text: Rules.describe(phase: i),
                seats: phases.indices.filter { min(max(phases[$0], 0), last) == i },
                isFocus: focusPhase.map { min($0, last) == i } ?? false,
                isDone: focusPhase.map { i < $0 } ?? false)
        }
    }
}
