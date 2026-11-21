import Foundation

/// A Cat Nap board as a player works it: the marks so far, and a drag in progress. A value, so the
/// view's model holds one and tests drive it directly. Every change it makes is a `NapMove` for the
/// server, which applies the same rules (`CatNapRules`, the golden vectors).
///
/// Input: a tap cycles a cell (empty, "no cat", cat, empty). A drag that starts on an empty cell
/// marks "no cat" on every empty cell it crosses; one that starts on a "no cat" clears them. Cats
/// and hinted cats are never touched by a drag, and hinted cats not by a tap either.
public struct NapPlay: Sendable, Equatable {
    public let quilt: NapQuilt
    /// The board with every move made so far.
    public private(set) var state: NapState
    /// The drag in progress: what it paints, and the cells it crossed, in order.
    public private(set) var drag: (paint: NapTo, passed: [Int])?

    public init(quilt: NapQuilt, state: NapState? = nil) {
        self.quilt = quilt
        self.state = state ?? .empty(quilt)
    }

    public static func == (a: NapPlay, b: NapPlay) -> Bool {
        a.quilt == b.quilt && a.state == b.state && a.drag?.paint == b.drag?.paint && a.drag?.passed == b.drag?.passed
    }

    /// The board to draw: `state`, with a drag in progress painted on.
    public var shown: NapState {
        guard let drag, let move = CatNapRules.dragMove(state, paint: drag.paint, passed: drag.passed),
              let next = CatNapRules.apply(quilt, state, move)
        else { return state }
        return next
    }

    public func contains(_ cell: Int) -> Bool { cell >= 0 && cell < quilt.size }

    /// Cycles `cell`; the move to send, or nil when nothing changed (a hinted cat, a drag under way).
    public mutating func tap(_ cell: Int) -> NapMove? {
        guard drag == nil, contains(cell), let move = CatNapRules.tapMove(state, cell: cell),
              let next = CatNapRules.apply(quilt, state, move)
        else { return nil }
        state = next
        return move
    }

    /// Starts a drag at `cell`. False when a drag can't start there (a cat, a hinted cat).
    @discardableResult
    public mutating func dragBegan(at cell: Int) -> Bool {
        guard contains(cell), let paint = CatNapRules.dragPaint(state, start: cell) else {
            drag = nil
            return false
        }
        drag = (paint, [cell])
        return true
    }

    /// The drag crossed `cell`. True when the board shown changed.
    @discardableResult
    public mutating func dragMoved(to cell: Int) -> Bool {
        guard let drag, contains(cell), !drag.passed.contains(cell) else { return false }
        let before = shown
        self.drag = (drag.paint, drag.passed + [cell])
        return shown != before
    }

    /// Ends the drag; the move to send, or nil when it changed nothing.
    public mutating func dragEnded() -> NapMove? {
        guard let drag else { return nil }
        self.drag = nil
        guard let move = CatNapRules.dragMove(state, paint: drag.paint, passed: drag.passed),
              let next = CatNapRules.apply(quilt, state, move)
        else { return nil }
        state = next
        return move
    }

    /// A drag the system took away (a call, the app going to the background): nothing is sent.
    public mutating func dragCancelled() { drag = nil }

    /// The server's hint: its cat locked at `cell`, the cats clashing with it cleared.
    public mutating func hint(_ cell: Int) {
        guard contains(cell) else { return }
        state = CatNapRules.applyHint(quilt, state, cell: cell)
    }

    /// The server's board (a resumed run, another device's moves): it replaces ours.
    public mutating func load(_ server: NapState) {
        guard server.cells.count == quilt.size else { return }
        state = server
        drag = nil
    }
}
