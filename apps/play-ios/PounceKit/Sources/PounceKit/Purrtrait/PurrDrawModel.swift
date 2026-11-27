import Foundation
import Observation

/// The drawer's turn on this device (Purrtrait spec §6.3, §6.5, §7): the pen, what goes to the
/// room and when, and the few things the tools show (Undo, Clear, Easel full). The canvas feeds it
/// touches and ticks it every frame while something waits to go; it hands ink to `send`, which
/// reports a message that never left so it goes again after the reconnect.
///
/// One model per drawing turn: a new turn makes a new one, so nothing of the last drawing stays.
@MainActor @Observable public final class PurrDrawModel {
    public let seat: Seat
    public let turn: String

    /// The pen's colour, 0-7, or 8 for the eraser.
    public var color = 0 {
        didSet { pen.color = color }
    }
    /// 0, 1 or 2.
    public var width = 1 {
        didSet { pen.width = width }
    }
    public private(set) var canUndo = false
    public private(set) var canClear = false
    /// The server said the easel holds all it takes this turn: only Clear helps.
    public private(set) var full = false
    /// Strokes this turn (the tips count them).
    public private(set) var strokes = 0
    /// Strokes on the easel now (observed: the debug probe and tests read it).
    public private(set) var visible = 0

    @ObservationIgnored public private(set) var pen = InkPen()
    /// Ops whose message never left the device, oldest first.
    @ObservationIgnored private var unsent: [[InkOp]] = []
    @ObservationIgnored private let send: @MainActor (_ ops: [InkOp], _ last: Bool, _ failed: @escaping @MainActor () -> Void) -> Void
    @ObservationIgnored private let clock: () -> Duration

    /// `send` gets each message's ops (for `seat` and `turn`), whether it ends a resend reply
    /// (`last`), and a closure to call if it never left.
    public init(
        seat: Seat, turn: String, clock: @escaping () -> Duration = { ContinuousClock.now - PurrDrawModel.origin },
        send: @escaping @MainActor (_ ops: [InkOp], _ last: Bool, _ failed: @escaping @MainActor () -> Void) -> Void
    ) {
        self.seat = seat
        self.turn = turn
        self.clock = clock
        self.send = send
        pen.width = width
    }

    public nonisolated static let origin = ContinuousClock.now

    public var drawing: InkDrawing { pen.drawing }

    /// A finger is down, or ink waits to go: tick every frame.
    public var needsTicks: Bool { pen.isDrawing || pen.hasPending }

    // MARK: input

    /// A finger went down. False while the easel is full (nothing is drawn).
    @discardableResult public func down(_ p: InkPoint) -> Bool {
        guard !full else { return false }
        pen.down(p)
        strokes += 1
        sync()
        tick()
        return true
    }

    /// The finger moved through `points`; true when the picture changed.
    @discardableResult public func move(_ points: [InkPoint]) -> Bool {
        pen.move(points) > 0
    }

    /// The finger lifted, or the touch was cancelled: the stroke ends and goes at once.
    public func up() {
        guard pen.isDrawing else { return }
        pen.up()
        tick()
    }

    /// The app is going away (background, a call, the screen locking): the stroke ends cleanly.
    public func background() { up() }

    @discardableResult public func undo() -> Bool {
        guard pen.undo() else { return false }
        sync()
        tick()
        return true
    }

    @discardableResult public func clear() -> Bool {
        let cleared = pen.clear()
        full = false
        guard cleared else { return false }
        sync()
        tick()
        return true
    }

    // MARK: sending

    /// Sends what is due now (every 50 ms while drawing, at once at a stroke's end, 25 a second
    /// at most). Call it every frame while `needsTicks`.
    public func tick() {
        guard let ops = pen.take(now: clock()) else { return }
        for message in InkCodec.chunk(ops) { out(message) }
    }

    private func out(_ ops: [InkOp], last: Bool = false) {
        send(ops, last) { [weak self] in self?.unsent.append(ops) }
    }

    /// The socket is back: whatever never left goes now, in order (the room drops it if the turn
    /// moved on).
    public func reconnected() {
        let pending = unsent
        unsent = []
        for ops in pending { out(ops) }
    }

    /// The room lost the turn's ink (`inkResend`): the whole picture again, starting with a clear,
    /// its final message marked `last` (even when there is only one).
    public func resend() {
        unsent = []
        let messages = pen.resend()
        for (i, message) in messages.enumerated() { out(message, last: i == messages.count - 1) }
        sync()
    }

    /// The room's copy of this turn (`inkSync`), taken only when this device has none of its
    /// own (the app came back after being closed). True when it was taken.
    @discardableResult public func adopt(_ ops: [InkOp]) -> Bool {
        guard pen.adopt(ops) else { return false }
        sync()
        return true
    }

    /// The server's `easel_full`: it refused the batch whole, and would refuse what waits too. The
    /// next message is Clear, on its own.
    public func easelFull() {
        pen.dropQueued()
        unsent = []
        full = true
    }

    private func sync() {
        if visible != pen.drawing.strokes.count { visible = pen.drawing.strokes.count }
        let undo = !pen.drawing.isEmpty
        if canUndo != undo { canUndo = undo }
        if canClear != undo { canClear = undo }
    }
}
