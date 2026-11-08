/// What the phase chip on a seat's cat says (the table's top bar): "P4" on a gold pill, or a
/// trophy once every phase is done, with the "laid down" sticker while this round's phase is
/// down. The card count rides on a mini card back on the other corner, so the two never read
/// alike.
public struct PhaseMark: Hashable, Sendable {
    /// 1...`Rules.phases.count`; nil once every phase is done.
    public let number: Int?
    /// Laid this round's phase down (never once every phase is done).
    public let laid: Bool

    /// `index` as in `GameView.phase` (0 = phase 1, `Rules.phases.count` or more = done).
    public init(index: Int, laid: Bool) {
        let i = max(index, 0)
        number = i < Rules.phases.count ? i + 1 : nil
        self.laid = number != nil && laid
    }

    /// A seat's mark in `game`; nil for a seat the game doesn't have.
    public static func seat(_ seat: Seat, in game: GameView) -> PhaseMark? {
        guard game.phase.indices.contains(seat) else { return nil }
        let laid = game.laid.indices.contains(seat) && game.laid[seat] != nil
        return PhaseMark(index: game.phase[seat], laid: laid)
    }

    /// Every phase is done (the chip wears a trophy).
    public var isDone: Bool { number == nil }

    /// "P4"; nil once every phase is done.
    public var text: String? { number.map { "P\($0)" } }

    /// How far along: the phase number, one past the last phase once done.
    public var rank: Int { number ?? Rules.phases.count + 1 }

    /// True when this is a later phase than `old` (the chip pops). The first mark a cat gets
    /// never pops, and laying down within a phase isn't a new phase.
    public func advanced(from old: PhaseMark?) -> Bool {
        guard let old else { return false }
        return rank > old.rank
    }
}
