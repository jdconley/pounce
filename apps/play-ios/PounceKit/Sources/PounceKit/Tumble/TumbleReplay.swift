import Foundation

/// Every other box at the table, replayed from the server's relays (spec §6.4): set-downs, the
/// toy's position, tricks used, and each hit applied when the box's own device acked it, so every
/// copy of a box applies hits in the order its device did. A gap in a box's `q` asks for a sync
/// and nothing more is replayed for that box until it comes. Times are ms on the device's clock.
public final class TumbleReplay {
    public struct Seat: Equatable, Sendable {
        public var box: TumbleBox
        /// The last relay applied; nil before the first (a fresh box at the round's start).
        public var q: Int?
        /// The toy where its device last said, and when that arrived.
        public var toy: TumbleToyState?
        public var toyAt: Double = 0
        public var status: TumbleBoxSync.Status = .ok
        /// Each waiting junk's wait start, by id, as the device's ack arrived.
        public var waitStart: [Int: Double] = [:]
        public var catnipUntil: Double = 0
        public var napUntil: Double = 0
        /// Waiting for a sync: a relay was missed or didn't replay.
        public var stale = false
    }

    /// Something to animate on another box.
    public enum Effect: Equatable, Sendable {
        case setDown(seat: Int, rows: [Int])
        case hit(seat: Int, kind: TumbleHitKind, from: Int)
        case out(seat: Int)
    }

    public let r: Int
    public private(set) var queue: TumbleQueue
    public private(set) var seats: [Int: Seat] = [:]
    /// Hits issued and not yet acked by their target's device, by id.
    private var hits: [Int: TumbleHitWire] = [:]
    private var effects: [Effect] = []
    private var asked = false

    /// `trickSeeds` for every seat; `skip` is this device's own seat (the local box), if any.
    public init(r: Int, roundSeed: [UInt32], trickSeeds: [[UInt32]], skip: Int?) {
        self.r = r
        queue = TumbleQueue(roundSeed: roundSeed)
        for (s, seed) in trickSeeds.enumerated() where s != skip {
            seats[s] = Seat(box: TumbleBox(trickSeed: seed))
        }
    }

    /// True once a gap or a refusal means the device should ask for a sync. Reading it clears it.
    public func takeSyncRequest() -> Bool {
        defer { asked = false }
        return asked
    }

    public var needsSync: Bool { asked }

    public func box(_ seat: Int) -> TumbleBox? { seats[seat]?.box }

    public func drainEffects() -> [Effect] {
        defer { effects.removeAll(keepingCapacity: true) }
        return effects
    }

    public func apply(_ message: TumbleMessage, now: Double) {
        guard message.round == r else { return }
        switch message {
        case .relay(let relay): applyRelay(relay, now: now)
        case .hit(let h):
            if h.k == .napped {
                effects.append(.hit(seat: h.to, kind: .napped, from: h.from))
            } else if seats[h.to] != nil {
                hits[h.id] = h
            }
        case .sync(let sync):
            for b in sync.boxes { applySync(b, now: now) }
        case .seat(let s):
            guard var seat = seats[s.s], seat.status != .out else { return }
            seat.status = s.st == .lag ? .lag : .ok
            seats[s.s] = seat
        }
    }

    private func applyRelay(_ relay: TumbleRelay, now: Double) {
        guard var seat = seats[relay.s], !seat.stale else { return }
        let expected = (seat.q ?? 0) + 1
        // The first relay of a fresh box may be numbered 0 or 1; after that, one up each time.
        let inOrder = relay.q == expected || (seat.q == nil && relay.q == 0)
        guard inOrder else {
            if relay.q > expected { markStale(relay.s, &seat) }
            return
        }
        seat.q = relay.q
        for ev in relay.ev {
            guard replay(ev, on: relay.s, &seat, now: now) else {
                markStale(relay.s, &seat)
                return
            }
        }
        seats[relay.s] = seat
    }

    private func markStale(_ s: Int, _ seat: inout Seat) {
        seat.stale = true
        seats[s] = seat
        asked = true
    }

    /// One event on another box; false when it doesn't replay (this copy has split from the server's).
    private func replay(_ ev: TumbleEvent, on s: Int, _ seat: inout Seat, now: Double) -> Bool {
        switch ev {
        case .move(let n, let rot, let x, let y):
            guard n == seat.box.next else { return true }
            seat.toy = TumbleToyState(n: n, toy: queue.toy(n), spot: TumbleSpot(rot: rot, x: x, y: y))
            seat.toyAt = now
        case .land(let n, let rot, let x, let y, _, let landed):
            switch Tumble.setDown(seat.box, queue: &queue, n: n, rot: rot, x: x, y: y, landed: landed) {
            case .failure: return false
            case .success(let done):
                seat.box = done.box
                seat.waitStart = seat.waitStart.filter { id, _ in done.box.waiting.contains { $0.id == id } }
                seat.toy = nil
                effects.append(.setDown(seat: s, rows: done.clearedRows))
                if done.out {
                    seat.status = .out
                    effects.append(.out(seat: s))
                } else {
                    let next = queue.toy(done.box.next)
                    seat.toy = TumbleToyState(n: done.box.next, toy: next, spot: TumbleToys.spawn(next))
                    seat.toyAt = now
                }
            }
        case .ack(let id):
            guard let h = hits.removeValue(forKey: id), h.to == s else { return true }
            let wasOut = seat.box.out
            if let junk = h.junk {
                seat.box = Tumble.receiveJunk(seat.box, junk)
                seat.waitStart[junk.id] = now
            } else if let hit = h.hit {
                seat.box = Tumble.applyHit(seat.box, hit).box
                if h.k == .catnip { seat.catnipUntil = now + TumbleClock.effectLength }
                if h.k == .nap { seat.napUntil = now + TumbleClock.effectLength }
                if h.k == .bath { seat.waitStart = [:] }
                effects.append(.hit(seat: s, kind: h.k, from: h.from))
            }
            if seat.box.out, !wasOut {
                seat.status = .out
                seat.toy = nil
                effects.append(.out(seat: s))
            }
        case .use(let slot, _):
            guard let used = Tumble.useTrick(seat.box, slot: slot) else { return false }
            seat.box = used.box
        }
        return true
    }

    private func applySync(_ b: TumbleBoxSync, now: Double) {
        guard var seat = seats[b.s] else { return }
        let wasOut = seat.status == .out
        seat.box = b.box
        seat.q = b.q
        seat.stale = false
        seat.status = b.box.out ? .out : b.status
        seat.waitStart = [:]
        for (i, w) in b.box.waiting.enumerated() {
            let left = i < b.waitingLeft.count ? b.waitingLeft[i] : TumbleClock.junkWait
            seat.waitStart[w.id] = now - (TumbleClock.junkWait - left)
        }
        seat.catnipUntil = b.catnipLeft > 0 ? now + b.catnipLeft : 0
        seat.napUntil = b.napLeft > 0 ? now + b.napLeft : 0
        if seat.status == .out {
            seat.toy = nil
            if !wasOut { effects.append(.out(seat: b.s)) }
        } else {
            let next = queue.toy(b.box.next)
            seat.toy = TumbleToyState(n: b.box.next, toy: next, spot: TumbleToys.spawn(next))
            seat.toyAt = now
        }
        seats[b.s] = seat
    }

    /// Where another box's toy is drawn now: its last reported spot, gliding down by gravity
    /// since then (never through the stack, never more than a row ahead of the device), and held
    /// still while its device is reconnecting.
    public func glide(_ s: Int, now: Double, roundMs: Double) -> (toy: TumbleToyState, y: Double)? {
        guard let seat = seats[s], let toy = seat.toy, seat.status == .ok else {
            return seats[s]?.toy.map { ($0, Double($0.spot.y)) }
        }
        let g = TumbleClock.gravityMs(roundMs, catnip: now < seat.catnipUntil)
        let rest = Double(Tumble.restingY(seat.box, toy: toy.toy, rot: toy.spot.rot, x: toy.spot.x, from: toy.spot.y) ?? toy.spot.y)
        let fall = min(1, max(0, (now - seat.toyAt) / g))
        return (toy, max(rest, Double(toy.spot.y) - fall))
    }

    /// Each waiting junk's rows and ms left, for a box's meter.
    public func waiting(_ s: Int, now: Double) -> [(rows: Int, leftMs: Double)] {
        guard let seat = seats[s] else { return [] }
        return seat.box.waiting.map { w in (w.rows, max(0, TumbleClock.junkWait - (now - (seat.waitStart[w.id] ?? now)))) }
    }
}
