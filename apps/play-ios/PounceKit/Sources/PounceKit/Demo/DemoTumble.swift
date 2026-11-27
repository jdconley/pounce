#if DEBUG
import Foundation

/// Toy Tumble's DEBUG demo room: a small stand-in for the server's round, run on the demo
/// socket's actor (never the main thread), so the real table plays with no server. It referees
/// this device's stream with the same engine, plays House-Cat-like scripted boxes in the other
/// seats, sends junk and tricks both ways, and runs rounds to a game over. It answers roughly as
/// the server does (`docs/live-protocol.md`); the real referee is play-api's.
public final class TumbleDemoRoom {
    public struct Options: Sendable {
        public var seats = 4
        public var mine = 0
        /// Tricks this device's box starts each round holding (for the tray's demos and tests).
        public var held: [TumbleTrick] = []
        /// Start mid-round, playing, instead of in the 3-2-1.
        public var playing = true
        /// The cats' think time per toy, ms.
        public var think: ClosedRange<Double> = 1400...2400
        /// How often a cat picks a worse spot.
        public var sloppy = 0.35
        /// A cat uses tricks it pockets, on this device's box when they hurt.
        public var catTricks = true
        /// This many wins takes the game.
        public var toWin = 3
        /// A rows-deep stack every box starts with, so clears and junk come early.
        public var stack = 0
        /// The style checkpoint: every box holds all nine toys, hairball rows and every trick badge,
        /// and nothing moves.
        public var sheet = false
        /// A screen (the TV) watches: no seat is this device's.
        public var screen = false
        /// This device's box starts the round out (it watches every box).
        public var mineOut = false
        /// Seats that left the game, and seats sitting rounds out as Away: no box, no play.
        public var left: [Int] = []
        public var away: [Int] = []
        public var names: [String] = ["Sam", "Mia", "Leo", "Ivy", "Max", "Zoe"]
        /// The other seats as people with these names (the App Store shots), played like the cats.
        public var family: [String] = []
        public init() {}
    }

    public private(set) var room: RoomView
    public private(set) var seq = 1
    private let o: Options
    /// The room's clock: the last `now` it was given, stamped on snapshots as `room.tumble.now`.
    private var clockNow: Double
    private var boxes: [TumbleBox] = []
    private var queue: TumbleQueue
    private var q: [Int] = []
    private var hitID = 100
    private var dice: [UInt32]
    private var plans: [Int: Plan] = [:]
    private var waitStart: [Int: [Int: Double]] = [:]
    private var napUntil: [Int: Double] = [:]
    private var useAt: [Int: Double] = [:]
    /// Hits to this device not yet acked, by id.
    private var owed: [Int: TumbleHitWire] = [:]
    private var betweenUntil: Double?

    private struct Plan {
        var spot: TumbleSpot
        var at: Double
        var moved = false
    }

    public init(_ options: Options = Options(), now: Double) {
        o = options
        clockNow = now
        let n = options.seats
        dice = [41, 42, 43, 44]
        queue = TumbleQueue(roundSeed: [1, 2, 3, 4])
        let seats = (0..<n).map { s in
            s == options.mine && !options.screen
                ? SeatView(kind: .human, person: Person(id: "p\(s)", name: options.names[s % options.names.count], cat: s % 8), yours: true, presence: .awake)
                : Self.seat(s, family: options.family)
        }
        room = RoomView(
            code: "TUMBLE", name: "Toy night", status: .playing, youAreHost: !options.screen, seats: seats, gameId: GameID.tumble,
            screen: options.screen ? true : nil, options: RoomOptions(cats: .easy),
            tumble: TumbleView(seats: n, wins: Array(repeating: 0, count: n), status: .countdown, r: 0))
        startRound(now: now, playing: options.playing)
    }

    private var mine: Int? { o.screen ? nil : o.mine }

    /// Another seat: a House Cat, or a person from `family`.
    private static func seat(_ s: Int, family: [String]) -> SeatView {
        guard family.indices.contains(s) else { return SeatView(kind: .bot) }
        return SeatView(kind: .human, person: Person(id: "f\(s)", name: family[s], cat: (s * 3 + 1) % 8), presence: .awake)
    }

    /// The room's copy of a box, for tests.
    public func box(_ s: Int) -> TumbleBox { boxes[s] }

    private func roll() -> Double {
        let (u, next) = TumbleRng.next(dice)
        dice = next
        return TumbleRng.float(u)
    }

    private func rollInt(_ n: Int) -> Int { min(n - 1, Int(roll() * Double(n))) }

    public var snapshot: ServerMessage {
        var r = room
        r.tumble?.now = clockNow
        return .snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: r)
    }

    private func bump() -> ServerMessage {
        seq += 1
        return snapshot
    }

    // MARK: rounds

    private func startRound(now: Double, playing: Bool) {
        guard var t = room.tumble else { return }
        let n = t.seats
        t.r += 1
        let r = UInt32(t.r)
        let roundSeed: [UInt32] = [r &* 101, 7, r &* 13, 9]
        let trickSeeds = (0..<n).map { s in [UInt32(s + 1) &* 31, r, 5, 6] }
        t.roundSeed = roundSeed
        t.trickSeeds = trickSeeds
        t.outs = []
        t.left = (0..<n).map { o.left.contains($0) }
        t.away = (0..<n).map { o.away.contains($0) }
        t.winner = nil
        t.status = playing ? .playing : .countdown
        t.startsAt = playing ? now - 1 : now + 3000
        room.tumble = t
        queue = TumbleQueue(roundSeed: roundSeed)
        boxes = trickSeeds.map { TumbleBox(trickSeed: $0) }
        if o.stack > 0 {
            for s in 0..<n {
                for y in 0..<o.stack {
                    let gap = (s + y * 5) % Tumble.width
                    for x in 0..<Tumble.width where x != gap { boxes[s].cells[y * Tumble.width + x] = Tumble.junk }
                }
            }
        }
        if o.sheet, let sheet = try? TumbleText.box(cells: Self.sheetCells, tricks: Self.sheetTricks) {
            for s in 0..<n {
                boxes[s].cells = sheet.cells
                boxes[s].tricks = sheet.tricks
            }
        }
        if let mine { boxes[mine].held = o.held }
        q = Array(repeating: 0, count: n)
        plans = [:]
        waitStart = [:]
        napUntil = [:]
        useAt = [:]
        owed = [:]
        betweenUntil = nil
        let start = t.startsAt ?? now
        if o.mineOut, let mine {
            boxes[mine].out = true
            room.tumble?.outs = [mine]
        }
        for s in o.left + o.away where s < n { boxes[s].out = true }
        for s in 0..<n where s != mine && !boxes[s].out { plans[s] = plan(s, at: start + (o.sheet ? 1e12 : think())) }
    }

    /// The nine toys, each in its own colour (1 to 9 in `TumbleToy` order), over three hairball rows.
    static let sheetCells = [
        "....8.......",
        "...888...9.9",
        "3...8....999",
        "3...........",
        "3.44..5....7",
        "3.44.555.777",
        "..........66",
        "111..2.....6",
        "....22....66",
        "#####.######",
        "##.#########",
        "########.###",
    ]
    /// Every trick's badge (a to h) on a cell.
    static let sheetTricks = [
        "", "", "", "", "", "", "", "",
        "a...........",
        ".....b....c.",
        "..d....e....",
        "f...g.....h.",
    ]

    private func think() -> Double { o.think.lowerBound + roll() * (o.think.upperBound - o.think.lowerBound) }

    /// The messages a fresh connection gets: the snapshot, then every box.
    public func connect() -> [ServerMessage] {
        [snapshot, syncAll()]
    }

    private func syncAll(now: Double = 0) -> ServerMessage {
        let r = room.tumble?.r ?? 0
        return .tumble(.sync(TumbleSync(r: r, boxes: boxes.indices.map { sync($0, now: now) })))
    }

    private func sync(_ s: Int, now: Double) -> TumbleBoxSync {
        let left = boxes[s].waiting.map { w in max(0, TumbleClock.junkWait - (now - (waitStart[s]?[w.id] ?? now))) }
        return TumbleBoxSync(s: s, box: boxes[s], q: q[s], waitingLeft: left, napLeft: max(0, (napUntil[s] ?? 0) - now),
                             status: boxes[s].out ? .out : .ok)
    }

    // MARK: this device's stream

    public func receive(_ message: ClientMessage, now: Double) -> [ServerMessage] {
        clockNow = now
        switch message {
        case .setOptions(let options):
            room.options = options
            if let cats = options.cats { room.tumble?.cats = cats }
            return [bump()]
        case .tumble(let r, let ev):
            guard let mine, r == room.tumble?.r else { return [] }
            if ev.isEmpty { return [syncAll(now: now)] }
            var out: [ServerMessage] = []
            for e in ev {
                switch e {
                case .move:
                    break
                case .land(let n, let rot, let x, let y, _, let landed):
                    switch Tumble.setDown(boxes[mine], queue: &queue, n: n, rot: rot, x: x, y: y, landed: landed) {
                    case .failure:
                        return out + [.tumble(.sync(TumbleSync(r: r, boxes: [sync(mine, now: now)])))]
                    case .success(let done):
                        boxes[mine] = done.box
                        out += junk(from: mine, rows: done.sent, now: now)
                        out += checkOut(now: now)
                    }
                case .ack(let id):
                    guard let h = owed.removeValue(forKey: id) else { continue }
                    if let junk = h.junk {
                        boxes[mine] = Tumble.receiveJunk(boxes[mine], junk)
                        waitStart[mine, default: [:]][junk.id] = now
                    } else if let hit = h.hit {
                        boxes[mine] = Tumble.applyHit(boxes[mine], hit).box
                        if h.k == .nap { napUntil[mine] = now + TumbleClock.effectLength }
                    }
                    out += checkOut(now: now)
                case .use(let slot, let target):
                    guard let used = Tumble.useTrick(boxes[mine], slot: slot) else { continue }
                    boxes[mine] = used.box
                    out += throwTrick(used.trick, from: mine, to: target, now: now)
                    out += checkOut(now: now)
                }
            }
            return out
        default:
            return []
        }
    }

    // MARK: the cats

    /// Advances the cats and the round to `now`.
    public func tick(now: Double) -> [ServerMessage] {
        clockNow = now
        guard var t = room.tumble else { return [] }
        if let until = betweenUntil {
            guard now >= until else { return [] }
            betweenUntil = nil
            if t.status == .over { return [] }
            startRound(now: now, playing: false)
            return o.stack > 0 ? [bump(), syncAll(now: now)] : [bump()]
        }
        if t.status == .countdown, let start = t.startsAt, now >= start {
            t.status = .playing
            room.tumble = t
            return [bump()]
        }
        guard t.status == .playing else { return [] }
        var out: [ServerMessage] = []
        for s in boxes.indices where s != mine && !boxes[s].out {
            if o.catTricks, let at = useAt[s], now >= at, !boxes[s].held.isEmpty {
                useAt[s] = nil
                out += catUse(s, now: now)
            }
            guard var p = plans[s], now >= p.at - 300 else { continue }
            if !p.moved {
                p.moved = true
                plans[s] = p
                out.append(relay(s, [.move(n: boxes[s].next, rot: p.spot.rot, x: p.spot.x, y: min(p.spot.y + 6, 19))]))
                continue
            }
            guard now >= p.at else { continue }
            out += catSetDown(s, p.spot, now: now)
            if !boxes[s].out { plans[s] = plan(s, at: now + think()) }
        }
        out += checkOut(now: now)
        return out
    }

    private func relay(_ s: Int, _ ev: [TumbleEvent]) -> ServerMessage {
        q[s] += 1
        return .tumble(.relay(TumbleRelay(r: room.tumble?.r ?? 0, s: s, q: q[s], ev: ev)))
    }

    /// The cat's spot for its next toy: the best by holes, height and clears, or a worse one now and then.
    private func plan(_ s: Int, at: Double) -> Plan {
        let box = boxes[s]
        let toy = queue.toy(box.next)
        var options: [(TumbleSpot, Double)] = []
        for rot in 0..<4 {
            for x in -3..<12 {
                guard let y = Tumble.restingY(box, toy: toy, rot: rot, x: x) else { continue }
                guard case .success(let r) = Tumble.setDown(box, queue: &queue, n: box.next, rot: rot, x: x, y: y, landed: []) else { continue }
                options.append((TumbleSpot(rot: rot, x: x, y: y), Self.score(r.box) - Double(r.cleared) * 6))
            }
        }
        options.sort { $0.1 < $1.1 }
        let spawn = TumbleToys.spawn(toy)
        guard !options.isEmpty else { return Plan(spot: spawn, at: at) }
        let pick = roll() < o.sloppy ? min(options.count - 1, 1 + rollInt(3)) : 0
        return Plan(spot: options[pick].0, at: at)
    }

    static func score(_ b: TumbleBox) -> Double {
        var holes = 0
        var height = 0
        for x in 0..<Tumble.width {
            var seen = false
            for y in stride(from: Tumble.total - 1, through: 0, by: -1) {
                let filled = b.cell(x, y) != 0
                if filled, !seen {
                    seen = true
                    height = max(height, y + 1)
                } else if !filled, seen {
                    holes += 1
                }
            }
        }
        return Double(holes * 4 + height)
    }

    private func catSetDown(_ s: Int, _ spot: TumbleSpot, now: Double) -> [ServerMessage] {
        let box = boxes[s]
        let n = box.next
        guard let y = Tumble.restingY(box, toy: queue.toy(n), rot: spot.rot, x: spot.x) else {
            // Nowhere to go: tip over.
            boxes[s].out = true
            return []
        }
        let ready = box.waiting.prefix { now - (waitStart[s]?[$0.id] ?? now) >= TumbleClock.junkWait }.map(\.id)
        var landed: [Int] = []
        var result = Tumble.setDown(box, queue: &queue, n: n, rot: spot.rot, x: spot.x, y: y, landed: [])
        if case .success(let r) = result, r.cleared == 0, !ready.isEmpty {
            landed = ready
            result = Tumble.setDown(box, queue: &queue, n: n, rot: spot.rot, x: spot.x, y: y, landed: landed)
        }
        guard case .success(let done) = result else { return [] }
        boxes[s] = done.box
        var out = [relay(s, [.move(n: n, rot: spot.rot, x: spot.x, y: y), .land(n: n, rot: spot.rot, x: spot.x, y: y, ms: 0, landed: landed)])]
        if !done.pocketed.isEmpty, useAt[s] == nil { useAt[s] = now + 1000 + roll() * 2000 }
        out += junk(from: s, rows: done.sent, now: now)
        return out
    }

    private func catUse(_ s: Int, now: Double) -> [ServerMessage] {
        let slot = 0
        let trick = boxes[s].held[slot]
        let harmful: Set<TumbleTrick> = [.hairball, .swipe, .catnip, .swap]
        let human = mine ?? (s + 1) % boxes.count
        let target = harmful.contains(trick) ? (boxes[human].out ? s : human) : s
        if trick == .swap, Tumble.highest(boxes[s]) < Tumble.highest(boxes[target]) { return [] }
        guard let used = Tumble.useTrick(boxes[s], slot: slot) else { return [] }
        boxes[s] = used.box
        return [relay(s, [.use(slot: slot, seat: target)])] + throwTrick(trick, from: s, to: target, now: now)
    }

    // MARK: hits

    private func nextID() -> Int {
        hitID += 1
        return hitID
    }

    private func junk(from s: Int, rows: Int, now: Double) -> [ServerMessage] {
        guard rows > 0 else { return [] }
        let r = room.tumble?.r ?? 0
        var out: [ServerMessage] = []
        let gap = rollInt(Tumble.width)
        for t in boxes.indices where t != s && !boxes[t].out {
            let id = nextID()
            if (napUntil[t] ?? 0) > now { continue }
            let wire = TumbleHitWire(r: r, id: id, from: s, to: t, k: .junk, junk: TumbleWaiting(id: id, rows: rows, gap: gap))
            out.append(.tumble(.hit(wire)))
            out += deliver(wire, now: now)
        }
        return out
    }

    private func throwTrick(_ trick: TumbleTrick, from s: Int, to t: Int, now: Double) -> [ServerMessage] {
        guard boxes.indices.contains(t), !boxes[t].out else { return [] }
        let r = room.tumble?.r ?? 0
        if (napUntil[t] ?? 0) > now {
            return [.tumble(.hit(TumbleHitWire(r: r, id: nextID(), from: s, to: t, k: .napped)))]
        }
        let hit: TumbleHit
        switch trick {
        case .hairball: hit = .hairball(gap: rollInt(Tumble.width))
        case .swipe: hit = .swipe(shifts: (0..<Tumble.total).map { _ in rollInt(5) - 2 })
        case .catnip: hit = .catnip
        case .scoop: hit = .scoop
        case .settle: hit = .settle
        case .nap: hit = .nap
        case .bath: hit = .bath
        case .swap:
            let a = boxes[s], b = boxes[t]
            let toT = TumbleHitWire(r: r, id: nextID(), from: s, to: t, k: .swap, hit: .swap(cells: a.cells, tricks: a.tricks))
            let toS = TumbleHitWire(r: r, id: nextID(), from: s, to: s, k: .swap, hit: .swap(cells: b.cells, tricks: b.tricks))
            return [.tumble(.hit(toT)), .tumble(.hit(toS))] + deliver(toT, now: now) + deliver(toS, now: now)
        }
        let wire = TumbleHitWire(r: r, id: nextID(), from: s, to: t, k: TumbleHitKind(rawValue: trick.rawValue) ?? .hairball, hit: hit)
        return [.tumble(.hit(wire))] + deliver(wire, now: now)
    }

    /// A cat's box applies a hit and acks it at once; this device's box acks it itself.
    private func deliver(_ h: TumbleHitWire, now: Double) -> [ServerMessage] {
        if h.to == mine {
            owed[h.id] = h
            return []
        }
        if let junk = h.junk {
            boxes[h.to] = Tumble.receiveJunk(boxes[h.to], junk)
            waitStart[h.to, default: [:]][junk.id] = now
        } else if let hit = h.hit {
            boxes[h.to] = Tumble.applyHit(boxes[h.to], hit).box
            if h.k == .nap { napUntil[h.to] = now + TumbleClock.effectLength }
            if h.k == .bath { waitStart[h.to] = [:] }
        }
        return [relay(h.to, [.ack(id: h.id)])]
    }

    // MARK: outs and the end of a round

    private func checkOut(now: Double) -> [ServerMessage] {
        guard var t = room.tumble, t.status == .playing else { return [] }
        var changed = false
        for s in boxes.indices where boxes[s].out && !t.outs.contains(s) {
            t.outs.append(s)
            changed = true
        }
        guard changed else { return [] }
        let left = boxes.indices.filter { !t.outs.contains($0) }
        if left.count <= 1 {
            t.winner = left.first
            if let w = left.first { t.wins[w] += 1 }
            t.status = t.wins.contains { $0 >= o.toWin } ? .over : .between
            betweenUntil = now + 5000
            if t.status == .over { room.status = .over }
        }
        room.tumble = t
        return [bump()]
    }
}
#endif
