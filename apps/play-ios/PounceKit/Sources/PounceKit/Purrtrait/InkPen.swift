import Foundation

/// The drawer's side of ink (spec §6.3): touches become the local picture at once, and batches of
/// ops for the server, every 50 ms while drawing and at once when a stroke ends, at most 25 a
/// second. Pure and clock-driven, so it is tested without a screen; the app calls it from touch
/// handlers and a display link.
///
/// - `drawing` is what the drawer sees: every point kept (2 grid units apart). What goes to the
///   server is each batch simplified (Ramer-Douglas-Peucker, 1 unit), so the TV's lines sit within
///   a unit of the drawer's.
/// - Ops leave in the order they were made. A batch held back by the rate limit goes later with
///   everything that came meanwhile.
public struct InkPen: Sendable {
    public private(set) var drawing = InkDrawing()
    /// The id the next stroke gets.
    public private(set) var nextID = 0
    public var color = 0
    public var width = 1

    /// The stroke a finger is drawing.
    public private(set) var strokeID: Int?
    private var strokeSent = false
    private var lastSent: InkPoint?
    private var pending: [InkPoint] = []
    /// Ops made and not sent yet, in order (the stroke's newest points are in `pending`).
    private var queue: [InkOp] = []
    /// Something in the queue goes at once (a stroke ended, an undo, a clear).
    private var urgent = false
    private var lastBatch: Duration?
    private var sendTimes: [Duration] = []

    public init() {}

    public var isDrawing: Bool { strokeID != nil }

    /// Something is waiting to go.
    public var hasPending: Bool { !pending.isEmpty || !queue.isEmpty }

    // MARK: input

    /// A finger went down at `p` (grid units): a new stroke.
    public mutating func down(_ p: InkPoint) {
        if strokeID != nil { up() }
        let p = InkGrid.clamp(p)
        let id = nextID
        nextID += 1
        strokeID = id
        strokeSent = false
        lastSent = nil
        pending = [p]
        drawing.apply(.stroke(id: id, color: color, width: width, start: p, deltas: []))
    }

    /// The finger moved through `points` (every coalesced sample, in order). Returns how many were
    /// kept, so the caller knows whether the picture changed.
    @discardableResult public mutating func move(_ points: [InkPoint]) -> Int {
        guard let id = strokeID else { return 0 }
        let last = drawing.live?.points.last
        let kept = InkCodec.filter(points.map(InkGrid.clamp), after: last)
        guard !kept.isEmpty, let from = last else { return 0 }
        drawing.apply(.extend(id: id, deltas: InkCodec.deltas(from: from, through: kept)))
        pending.append(contentsOf: kept)
        return kept.count
    }

    /// The finger lifted (or the touch was cancelled, or the app went away): the stroke ends and
    /// its last points go at once.
    public mutating func up() {
        guard strokeID != nil else { return }
        flushPoints()
        strokeID = nil
        urgent = true
    }

    /// Takes back the newest stroke. False when there's none.
    @discardableResult public mutating func undo() -> Bool {
        if strokeID != nil { up() }
        guard let last = drawing.strokes.last else { return false }
        flushPoints()
        drawing.apply(.undo(id: last.id))
        queue.append(.undo(id: last.id))
        urgent = true
        return true
    }

    /// Wipes the easel. False when it's already blank.
    @discardableResult public mutating func clear() -> Bool {
        if strokeID != nil { up() }
        guard !drawing.isEmpty else { return false }
        flushPoints()
        drawing.apply(.clear)
        queue.append(.clear)
        urgent = true
        return true
    }

    // MARK: sending

    /// The ops to send now, or nil: nothing waits, the 50 ms aren't up (and nothing is urgent),
    /// or 25 messages already went in the last second. Each call that returns ops counts as one
    /// message.
    public mutating func take(now: Duration) -> [InkOp]? {
        guard hasPending else { return nil }
        let due = urgent || lastBatch.map { now - $0 >= InkGrid.batchEvery } ?? true
        guard due else { return nil }
        sendTimes.removeAll { now - $0 >= .seconds(1) }
        guard sendTimes.count < InkGrid.perSecond else { return nil }
        flushPoints()
        let ops = queue
        queue = []
        urgent = false
        lastBatch = now
        sendTimes.append(now)
        return ops
    }

    /// When the next `take` could send, if something waits (for a timer between frames).
    public func nextSend(now: Duration) -> Duration? {
        guard hasPending else { return nil }
        var at = urgent ? now : (lastBatch.map { $0 + InkGrid.batchEvery } ?? now)
        let recent = sendTimes.filter { now - $0 < .seconds(1) }
        if recent.count >= InkGrid.perSecond, let oldest = recent.min() { at = max(at, oldest + .seconds(1)) }
        return at
    }

    /// The pending points as one op on the queue: the stroke's `s` the first time, then `p`.
    private mutating func flushPoints() {
        guard let id = strokeID ?? drawing.live?.id, !pending.isEmpty else { return }
        if !strokeSent, let live = drawing.strokes.last(where: { $0.id == id }) {
            let pts = InkCodec.simplify(pending)
            queue.append(.stroke(id: id, color: live.color, width: live.width, start: pts[0],
                                 deltas: InkCodec.deltas(from: pts[0], through: Array(pts.dropFirst()))))
            strokeSent = true
            lastSent = pts.last
        } else if let from = lastSent {
            let pts = Array(InkCodec.simplify([from] + pending).dropFirst())
            if !pts.isEmpty {
                queue.append(.extend(id: id, deltas: InkCodec.deltas(from: from, through: pts)))
                lastSent = pts.last
            }
        }
        pending = []
    }

    // MARK: the server lost it, or the device did

    /// The whole picture again, for `inkResend` (spec §6.5, the server's wire rules): a clear, then
    /// every stroke with its own id (ids only have to go up), split into messages under the size
    /// limit; the caller marks the last one `last`. The next stroke follows the highest id resent,
    /// so the room's easel, which knows only these, sees ids that go up by one. Nothing already
    /// queued goes after it.
    public mutating func resend() -> [[InkOp]] {
        var ops: [InkOp] = [.clear]
        for s in drawing.strokes {
            let pts = InkCodec.simplify(s.points)
            ops.append(.stroke(id: s.id, color: s.color, width: s.width, start: pts[0],
                               deltas: InkCodec.deltas(from: pts[0], through: Array(pts.dropFirst()))))
            if s.id == strokeID { lastSent = pts.last }
        }
        if let top = drawing.strokes.map(\.id).max() { nextID = top + 1 } else { nextID = 0 }
        if let id = strokeID { nextID = max(nextID, id + 1) }
        strokeSent = strokeID != nil
        pending = []
        queue = []
        urgent = false
        return InkCodec.chunk(ops)
    }

    /// The server refused a batch with `easel_full`: what waits to go would be refused too. The
    /// stroke ends and the queue empties, so the next message (Clear) goes on its own.
    public mutating func dropQueued() {
        if strokeID != nil { up() }
        pending = []
        queue = []
        urgent = false
    }

    /// A drawing the server kept (`inkSync`), taken only when this device has none of its own for
    /// the turn (it came back after being closed). Returns true when it was taken.
    @discardableResult public mutating func adopt(_ ops: [InkOp]) -> Bool {
        guard nextID == 0, drawing.isEmpty, !hasPending else { return false }
        let picture = InkDrawing(ops: InkCodec.compact(ops))
        drawing = picture
        nextID = picture.highestID + 1
        return true
    }
}
