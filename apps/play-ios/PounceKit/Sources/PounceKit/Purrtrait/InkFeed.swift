import Foundation

/// The ink a room's socket brought this device for the turn on now (Purrtrait spec §6.4): the TV's
/// stream from the drawer, or the drawer's own drawing back after a reconnect. Kept in memory
/// only, for this turn only: a new turn drops it. Not observed by SwiftUI: the easel listens to
/// `onChange` and draws, so a stream of points never re-renders a view.
@MainActor public final class InkFeed {
    /// What came in.
    public enum Change: Equatable, Sendable {
        /// A new turn, or the room's whole drawing (`inkSync`): draw `ops` from blank.
        case reset
        /// More ops from the drawer, in order.
        case ops([InkOp])
        /// The room lost the turn's ink; the drawer's device sends it all again.
        case resend(turn: String)
    }

    /// The turn the ops belong to.
    public private(set) var turn: String?
    /// Every op this turn, since the last reset (compact it to draw).
    public private(set) var ops: [InkOp] = []
    /// Each change, as it comes. One listener: the easel on screen, or the drawer's model.
    public var onChange: ((Change) -> Void)?
    /// Goes up with every change (tests, and the debug probe).
    public private(set) var serial = 0

    public init() {}

    /// The turn on now is `turn` (nil: no drawing turn). Another turn than the feed's drops it.
    public func follow(turn: String?) {
        guard turn != self.turn else { return }
        self.turn = turn
        guard !ops.isEmpty else { return }
        ops = []
        changed(.reset)
    }

    func relay(turn: String, ops new: [InkOp]) {
        guard !new.isEmpty else { return }
        if turn != self.turn {
            self.turn = turn
            ops = []
            changed(.reset)
        }
        ops.append(contentsOf: new)
        changed(.ops(new))
    }

    func sync(turn: String, ops new: [InkOp]) {
        self.turn = turn
        ops = InkCodec.compact(new)
        changed(.reset)
    }

    func resend(turn: String) {
        changed(.resend(turn: turn))
    }

    /// The picture so far, as the fewest ops.
    public var compacted: [InkOp] { InkCodec.compact(ops) }

    private func changed(_ change: Change) {
        serial += 1
        onChange?(change)
    }
}
