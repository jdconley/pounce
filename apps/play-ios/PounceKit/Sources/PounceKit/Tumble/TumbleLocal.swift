import Foundation

/// Something the scene shows, plays or buzzes for. The local box queues them; the scene drains them each frame.
public enum TumbleEffect: Equatable, Sendable {
    /// A toy set down; `rows` the rows it cleared (as they were before clearing), `sent` the junk it sent on.
    case setDown(rows: [Int], sent: Int, blocked: Int)
    case pocketed([TumbleTrick])
    /// Junk arrived and started waiting.
    case junkWaiting(rows: Int)
    /// Waiting junk landed under the stack.
    case junkLanded(rows: Int)
    /// A trick hit this box; `from` threw it.
    case hit(TumbleHitKind, from: Int)
    /// This box tipped over.
    case out
}

/// This device's own box on the frame clock (spec §4.2, §6.3): gravity, the set-down wait,
/// moves, turns and drops applied the moment they arrive, junk waits, hits, and the events out.
/// One step is well under half a millisecond, so it runs on the main thread with the scene; the
/// socket and its JSON stay in `RoomSocket`. Times are ms on the device's wall clock.
public final class TumbleLocal {
    public let r: Int
    public let seat: Int
    public let startsAt: Double
    public private(set) var box: TumbleBox
    /// The toy in hand, nil before the round starts, while waiting for a sync, and once out.
    public private(set) var toy: TumbleToyState?
    public private(set) var queue: TumbleQueue
    public private(set) var soft = false
    /// Waiting for the server's sync (after a return from the background, or a refusal).
    public private(set) var awaitingSync = false
    public private(set) var catnipUntil: Double = 0
    public private(set) var napUntil: Double = 0

    /// A batch to send as `{t:"tumble", r, ev}`.
    private let send: ([TumbleEvent]) -> Void
    private var pending: [TumbleEvent] = []
    private var urgent = false
    private var lastSent: Double = -.infinity
    private var lastMs = 0
    private var lastFall: Double = 0
    private var restSince: Double?
    private var resets = 0
    private var waitStart: [Int: Double] = [:]
    private var applied: Set<Int> = []
    private var syncAskedAt: Double = -.infinity
    private var effects: [TumbleEffect] = []

    /// A batch at most this often while something changes.
    public static let batchMs: Double = 50
    /// A set-down, trick or ack goes at once, but never closer than this to the last batch (30 a second at most).
    public static let urgentMs: Double = 34
    /// A sync asked for and not come is asked for again after this.
    public static let syncRetryMs: Double = 3000

    public init(r: Int, seat: Int, roundSeed: [UInt32], trickSeed: [UInt32], startsAt: Double, send: @escaping ([TumbleEvent]) -> Void) {
        self.r = r
        self.seat = seat
        self.startsAt = startsAt
        self.send = send
        box = TumbleBox(trickSeed: trickSeed)
        queue = TumbleQueue(roundSeed: roundSeed)
    }

    public var isOut: Bool { box.out }
    /// Nothing waits to be sent.
    public var isQuiet: Bool { pending.isEmpty }
    public var catnip: Bool { lastNow < catnipUntil }
    public var napping: Bool { lastNow < napUntil }
    private var lastNow: Double = 0

    /// The ms on the round clock now.
    public func roundMs(_ now: Double) -> Double { max(0, now - startsAt) }

    /// Where the toy in hand would rest: the paw-print outline's row.
    public var landing: Int? {
        guard let toy else { return nil }
        return Tumble.restingY(box, toy: toy.toy, rot: toy.spot.rot, x: toy.spot.x, from: toy.spot.y)
    }

    /// Each waiting junk's rows and the ms left of its wait.
    public func waiting(at now: Double) -> [(rows: Int, leftMs: Double)] {
        box.waiting.map { w in (w.rows, max(0, TumbleClock.junkWait - (now - (waitStart[w.id] ?? now)))) }
    }

    /// The effects since the last call, oldest first.
    public func drainEffects() -> [TumbleEffect] {
        defer { effects.removeAll(keepingCapacity: true) }
        return effects
    }

    // MARK: the frame

    /// Advances to `now`: spawns the first toy at the start, falls by the frame clock, sets down
    /// after the wait, and sends a batch when one is due.
    public func step(_ now: Double) {
        lastNow = now
        defer { flush(now) }
        if awaitingSync {
            if now - syncAskedAt >= Self.syncRetryMs { askSync(now) }
            return
        }
        guard !box.out, now >= startsAt else { return }
        if toy == nil { spawn(now) }
        guard var t = toy else { return }
        let interval = soft ? min(TumbleClock.softMs, fallMs(now)) : fallMs(now)
        while now - lastFall >= interval {
            if Tumble.fits(box, toy: t.toy, rot: t.spot.rot, x: t.spot.x, y: t.spot.y - 1) {
                t.spot.y -= 1
                lastFall += interval
                restSince = nil
            } else {
                lastFall = now
                break
            }
        }
        if t.spot != toy?.spot {
            toy = t
            queueMove()
        }
        let resting = !Tumble.fits(box, toy: t.toy, rot: t.spot.rot, x: t.spot.x, y: t.spot.y - 1)
        if resting {
            if restSince == nil { restSince = now }
            if let since = restSince, now - since >= TumbleClock.setDownMs { setDown(now) }
        } else {
            restSince = nil
        }
    }

    private func fallMs(_ now: Double) -> Double { TumbleClock.gravityMs(roundMs(now), catnip: now < catnipUntil) }

    private func spawn(_ now: Double) {
        let id = queue.toy(box.next)
        toy = TumbleToyState(n: box.next, toy: id, spot: TumbleToys.spawn(id))
        lastFall = max(now, startsAt)
        restSince = nil
        resets = 0
        queueMove()
    }

    // MARK: input

    /// One column left (-1) or right (1). False when it doesn't fit.
    @discardableResult public func move(_ dx: Int) -> Bool {
        guard var t = toy, !awaitingSync else { return false }
        guard Tumble.fits(box, toy: t.toy, rot: t.spot.rot, x: t.spot.x + dx, y: t.spot.y) else { return false }
        t.spot.x += dx
        moved(t)
        return true
    }

    /// A quarter turn, 1 clockwise, -1 counter-clockwise, with the first nudge that fits.
    @discardableResult public func turn(_ dir: Int) -> Bool {
        guard var t = toy, !awaitingSync else { return false }
        guard let to = Tumble.turn(box, toy: t.toy, rot: t.spot.rot, x: t.spot.x, y: t.spot.y, dir: dir) else { return false }
        t.spot = to
        moved(t)
        return true
    }

    private func moved(_ t: TumbleToyState) {
        toy = t
        if restSince != nil, resets < TumbleClock.setDownResets {
            resets += 1
            restSince = lastNow
        }
        queueMove()
    }

    /// Soft drop while held.
    public func setSoft(_ on: Bool) {
        guard on != soft else { return }
        soft = on
        if on { lastFall = min(lastFall, lastNow - TumbleClock.softMs) }
    }

    /// Straight down and set down at once.
    public func drop(_ now: Double) {
        guard var t = toy, !awaitingSync, let y = landing else { return }
        lastNow = now
        t.spot.y = y
        toy = t
        queueMove()
        setDown(now)
        flush(now)
    }

    /// Uses the trick in `slot` on `target`. The server sends the hit back to whoever it lands on.
    @discardableResult public func use(slot: Int, on target: Int, now: Double) -> TumbleTrick? {
        guard !awaitingSync, let used = Tumble.useTrick(box, slot: slot) else { return nil }
        box = used.box
        pending.append(.use(slot: slot, seat: target))
        urgent = true
        flush(now)
        return used.trick
    }

    // MARK: setting down

    private func setDown(_ now: Double) {
        guard let t = toy else { return }
        let ms = min(600_000, max(lastMs, Int(roundMs(now))))
        lastMs = ms
        var done: TumbleSetDown
        switch Tumble.setDown(box, queue: &queue, n: t.n, rot: t.spot.rot, x: t.spot.x, y: t.spot.y, landed: []) {
        case .failure:
            // Can't happen for a toy the box let fall here; ask the server for the truth.
            askSync(now)
            return
        case .success(let r): done = r
        }
        var landed: [Int] = []
        if done.cleared == 0 {
            landed = box.waiting.prefix { now - (waitStart[$0.id] ?? now) >= TumbleClock.junkWait }.map(\.id)
            if !landed.isEmpty, case .success(let r) = Tumble.setDown(box, queue: &queue, n: t.n, rot: t.spot.rot, x: t.spot.x, y: t.spot.y, landed: landed) {
                done = r
            } else {
                landed = []
            }
        }
        let landedRows = box.waiting.filter { landed.contains($0.id) }.map(\.rows).reduce(0, +)
        box = done.box
        waitStart = waitStart.filter { id, _ in box.waiting.contains { $0.id == id } }
        pending.append(.land(n: t.n, rot: t.spot.rot, x: t.spot.x, y: t.spot.y, ms: ms, landed: landed))
        urgent = true
        effects.append(.setDown(rows: done.clearedRows, sent: done.sent, blocked: done.blocked.map(\.rows).reduce(0, +)))
        if !done.pocketed.isEmpty { effects.append(.pocketed(done.pocketed)) }
        if landedRows > 0 { effects.append(.junkLanded(rows: landedRows)) }
        toy = nil
        restSince = nil
        if box.out {
            effects.append(.out)
        } else {
            spawn(now)
        }
    }

    // MARK: from the server

    /// A hit for this box: junk starts waiting, a trick applies now. Either is acked at once.
    public func hit(_ h: TumbleHitWire, now: Double) {
        guard h.r == r, h.to == seat, !applied.contains(h.id) else { return }
        lastNow = now
        if h.k == .napped {
            effects.append(.hit(.napped, from: h.from))
            return
        }
        applied.insert(h.id)
        if let junk = h.junk {
            box = Tumble.receiveJunk(box, junk)
            if !box.out {
                waitStart[junk.id] = now
                effects.append(.junkWaiting(rows: junk.rows))
            }
        } else if let trick = h.hit {
            let wasOut = box.out
            let r = Tumble.applyHit(box, trick)
            box = r.box
            if !r.pocketed.isEmpty { effects.append(.pocketed(r.pocketed)) }
            if h.k == .catnip { catnipUntil = now + TumbleClock.effectLength }
            if h.k == .nap { napUntil = now + TumbleClock.effectLength }
            if h.k == .bath { waitStart = [:] }
            effects.append(.hit(h.k, from: h.from))
            if box.out, !wasOut {
                toy = nil
                effects.append(.out)
            } else {
                unstick()
            }
        }
        pending.append(.ack(id: h.id))
        urgent = true
        flush(now)
    }

    /// A hit that pushed the stack into the falling toy lifts the toy row by row until it fits
    /// again, and says where it went (`docs/live-protocol.md`).
    private func unstick() {
        guard var t = toy else { return }
        var lifts = 0
        while !Tumble.fits(box, toy: t.toy, rot: t.spot.rot, x: t.spot.x, y: t.spot.y), lifts < Tumble.total {
            t.spot.y += 1
            lifts += 1
        }
        toy = t
        if lifts > 0 { queueMove() }
    }

    /// The server's whole box: snap to it. The toy in hand restarts at the top.
    public func sync(_ s: TumbleBoxSync, now: Double) {
        guard s.s == seat else { return }
        lastNow = now
        let wasOut = box.out
        box = s.box
        waitStart = [:]
        for (i, w) in box.waiting.enumerated() {
            let left = i < s.waitingLeft.count ? s.waitingLeft[i] : TumbleClock.junkWait
            waitStart[w.id] = now - (TumbleClock.junkWait - left)
        }
        catnipUntil = s.catnipLeft > 0 ? now + s.catnipLeft : 0
        napUntil = s.napLeft > 0 ? now + s.napLeft : 0
        awaitingSync = false
        toy = nil
        restSince = nil
        if box.out || s.status == .out {
            if !wasOut { effects.append(.out) }
            return
        }
        if now >= startsAt { spawn(now) }
    }

    /// The app went to the background: the socket drops and nothing steps until the server's sync.
    public func suspend() {
        awaitingSync = true
        toy = nil
        pending.removeAll()
    }

    /// Back from the background: ask for a sync (an empty batch) before any step.
    public func resume(_ now: Double) {
        guard awaitingSync else { return }
        askSync(now)
    }

    private func askSync(_ now: Double) {
        awaitingSync = true
        toy = nil
        pending.removeAll()
        syncAskedAt = now
        lastSent = now
        send([])
    }

    // MARK: sending

    private func queueMove() {
        guard let t = toy else { return }
        pending.removeAll { if case .move = $0 { true } else { false } }
        pending.append(.move(n: t.n, rot: t.spot.rot, x: t.spot.x, y: t.spot.y))
    }

    private func flush(_ now: Double) {
        guard !pending.isEmpty else { return }
        let wait = urgent ? Self.urgentMs : Self.batchMs
        guard now - lastSent >= wait else { return }
        send(pending)
        pending.removeAll(keepingCapacity: true)
        urgent = false
        lastSent = now
    }
}

/// The toy in hand: its queue index, kind and spot.
public struct TumbleToyState: Equatable, Sendable {
    public var n: Int
    public var toy: TumbleToy
    public var spot: TumbleSpot
    public init(n: Int, toy: TumbleToy, spot: TumbleSpot) {
        self.n = n
        self.toy = toy
        self.spot = spot
    }

    public var cells: [TumbleCell] {
        TumbleToys.cells(toy, rot: spot.rot).map { TumbleCell(spot.x + $0.x, spot.y + $0.y) }
    }
}
