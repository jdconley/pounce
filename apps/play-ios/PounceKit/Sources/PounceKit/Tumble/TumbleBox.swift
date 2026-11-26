import Foundation

/// A trick (spec §4.6), in `TRICKS` order: a cell's trick code is its index + 1.
public enum TumbleTrick: String, CaseIterable, Codable, Sendable, Hashable {
    case hairball, swipe, catnip, scoop, settle, nap, swap, bath

    public var code: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    public init?(code: Int) {
        guard code >= 1, code <= Self.allCases.count else { return nil }
        self = Self.allCases[code - 1]
    }
}

/// Junk waiting in a box's meter: `rows` rows that land with one gap.
public struct TumbleWaiting: Codable, Equatable, Sendable, Hashable {
    public var id: Int
    public var rows: Int
    public var gap: Int
    public init(id: Int, rows: Int, gap: Int) {
        self.id = id
        self.rows = rows
        self.gap = gap
    }
}

/// One Toy Tumble box, exactly the engine's `Box` (play-api `tumble/box.ts`), on the wire too.
public struct TumbleBox: Codable, Equatable, Sendable {
    /// `total * width` values, index `y * width + x`, y = 0 at the bottom. 0 empty, 1 to 9 a toy, 10 junk.
    public var cells: [Int]
    /// The trick on each cell: 0 none, else `TumbleTrick.code`.
    public var tricks: [Int]
    public var held: [TumbleTrick]
    /// The queue index of the toy now in hand.
    public var next: Int
    public var waiting: [TumbleWaiting]
    public var rng: [UInt32]
    public var out: Bool
    /// Every row this box has cleared this round.
    public var rows: Int

    public init(trickSeed: [UInt32]) {
        cells = Array(repeating: 0, count: Tumble.total * Tumble.width)
        tricks = Array(repeating: 0, count: Tumble.total * Tumble.width)
        held = []
        next = 0
        waiting = []
        rng = trickSeed
        out = false
        rows = 0
    }

    public func cell(_ x: Int, _ y: Int) -> Int { cells[y * Tumble.width + x] }
    public func trick(_ x: Int, _ y: Int) -> Int { tricks[y * Tumble.width + x] }
}

public struct TumbleBlocked: Equatable, Sendable {
    public var id: Int
    public var rows: Int
    public init(id: Int, rows: Int) {
        self.id = id
        self.rows = rows
    }
}

/// What a set-down did.
public struct TumbleSetDown: Equatable, Sendable {
    public var box: TumbleBox
    public var cleared: Int
    /// Junk rows left over to send after blocking.
    public var sent: Int
    public var blocked: [TumbleBlocked]
    public var pocketed: [TumbleTrick]
    public var out: Bool
    /// The rows cleared, as they were before clearing (for the pop animation).
    public var clearedRows: [Int]
}

public enum TumbleSetDownError: String, Error, Sendable {
    case boxOut = "box_out", notNext = "not_next", badPlace = "bad_place", notResting = "not_resting", badLanded = "bad_landed"
}

/// A trick's effect on a box, as the engine applies it. Every random choice is in the payload.
public enum TumbleHit: Equatable, Sendable {
    case hairball(gap: Int)
    case swipe(shifts: [Int])
    case catnip, nap, scoop, settle, bath
    case swap(cells: [Int], tricks: [Int])
}

/// The box engine (spec §4), a line-for-line port of play-api's `tumble/box.ts`. Pure and
/// deterministic: every function returns a new box. One step is well under half a millisecond.
public enum Tumble {
    public static let width = 12
    public static let height = 18
    public static let total = 22
    public static let junk = 10
    public static let maxHeld = 6
    /// Junk sent for 0 to 4 rows cleared at once (§4.3).
    public static let attack = [0, 0, 1, 2, 4]
    /// The first row of the top third: a box with a cell here gets the comeback weights.
    public static let dangerRow = 12
    static let weights = [20, 15, 12, 18, 12, 10, 3, 3]
    static let dangerWeights = [20, 15, 12, 36, 12, 10, 9, 9]
    /// The nudges a turn tries, in order (§4.2).
    public static let nudges: [(Int, Int)] = [(0, 0), (-1, 0), (1, 0), (0, 1), (-2, 0), (2, 0)]

    @inline(__always) static func idx(_ x: Int, _ y: Int) -> Int { y * width + x }

    /// True when the toy at this rotation and position is inside the box and overlaps nothing.
    public static func fits(_ box: TumbleBox, toy: TumbleToy, rot: Int, x: Int, y: Int) -> Bool {
        for c in TumbleToys.cells(toy, rot: rot) {
            let px = x + c.x
            let py = y + c.y
            if px < 0 || px >= width || py < 0 || py >= total { return false }
            if box.cells[idx(px, py)] != 0 { return false }
        }
        return true
    }

    /// A quarter turn (`dir` 1 clockwise, -1 counter-clockwise) with the first nudge that fits, or nil.
    public static func turn(_ box: TumbleBox, toy: TumbleToy, rot: Int, x: Int, y: Int, dir: Int) -> TumbleSpot? {
        let to = (((rot + dir) % 4) + 4) % 4
        for (dx, dy) in nudges where fits(box, toy: toy, rot: to, x: x + dx, y: y + dy) {
            return TumbleSpot(rot: to, x: x + dx, y: y + dy)
        }
        return nil
    }

    /// The highest filled row, or -1 for an empty box.
    public static func highest(_ box: TumbleBox) -> Int {
        var y = total - 1
        while y >= 0 {
            for x in 0..<width where box.cells[idx(x, y)] != 0 { return y }
            y -= 1
        }
        return -1
    }

    private static func anyAbove(_ box: TumbleBox) -> Bool { highest(box) >= height }

    private static func pushTrick(_ b: inout TumbleBox, _ code: Int, _ pocketed: inout [TumbleTrick]) {
        guard code != 0, let t = TumbleTrick(code: code) else { return }
        if b.held.count < maxHeld {
            b.held.append(t)
            pocketed.append(t)
        }
    }

    /// Removes the rows `full` (ascending), pocketing their tricks bottom row first, left to right.
    private static func removeRows(_ b: inout TumbleBox, _ full: [Int], _ pocketed: inout [TumbleTrick]) {
        if full.isEmpty { return }
        for y in full { for x in 0..<width { pushTrick(&b, b.tricks[idx(x, y)], &pocketed) } }
        let gone = Set(full)
        var cells: [Int] = []
        var tricks: [Int] = []
        cells.reserveCapacity(total * width)
        tricks.reserveCapacity(total * width)
        for y in 0..<total where !gone.contains(y) {
            for x in 0..<width {
                cells.append(b.cells[idx(x, y)])
                tricks.append(b.tricks[idx(x, y)])
            }
        }
        while cells.count < total * width {
            cells.append(0)
            tricks.append(0)
        }
        b.cells = cells
        b.tricks = tricks
    }

    private static func fullRows(_ b: TumbleBox) -> [Int] {
        var rows: [Int] = []
        for y in 0..<total {
            var full = true
            for x in 0..<width where b.cells[idx(x, y)] == 0 {
                full = false
                break
            }
            if full { rows.append(y) }
        }
        return rows
    }

    /// Pushes `rows` junk rows in under the stack, all with their gap at `gap`; tricks move with their cells.
    private static func pushJunk(_ b: inout TumbleBox, rows: Int, gap: Int) {
        var cells = Array(repeating: 0, count: total * width)
        var tricks = Array(repeating: 0, count: total * width)
        var y = 0
        while y + rows < total {
            for x in 0..<width {
                cells[idx(x, y + rows)] = b.cells[idx(x, y)]
                tricks[idx(x, y + rows)] = b.tricks[idx(x, y)]
            }
            y += 1
        }
        for y in 0..<min(rows, total) { for x in 0..<width { cells[idx(x, y)] = x == gap ? 0 : junk } }
        b.cells = cells
        b.tricks = tricks
    }

    /// How often each trick appears for this box, in `TRICKS` order: the comeback weights near the top.
    public static func trickWeights(_ b: TumbleBox) -> [Int] { highest(b) >= dangerRow ? dangerWeights : weights }

    /// One new trick for each row cleared: its kind by weight, then a filled cell with none.
    private static func spawnTricks(_ b: inout TumbleBox, _ count: Int) {
        for _ in 0..<count {
            let w = trickWeights(b)
            let totalWeight = w.reduce(0, +)
            let (u, s1) = TumbleRng.next(b.rng)
            b.rng = s1
            var pick = TumbleRng.float(u) * Double(totalWeight)
            var kind = 0
            while kind < w.count - 1 && pick >= Double(w[kind]) {
                pick -= Double(w[kind])
                kind += 1
            }
            var open: [Int] = []
            for c in 0..<(total * width) where b.cells[c] != 0 && b.tricks[c] == 0 { open.append(c) }
            if open.isEmpty { continue }
            let (v, s2) = TumbleRng.next(b.rng)
            b.rng = s2
            b.tricks[open[Int((TumbleRng.float(v) * Double(open.count)).rounded(.down))]] = kind + 1
        }
    }

    /// Sets toy `n` down (§4.2 to §4.6): clears full rows, blocks waiting junk with what they would
    /// send, adds a trick per row cleared, and, when nothing cleared, lands the junk in `landed`.
    public static func setDown(
        _ box: TumbleBox, roundSeed: [UInt32], n: Int, rot: Int, x: Int, y: Int, landed: [Int]
    ) -> Result<TumbleSetDown, TumbleSetDownError> {
        var queue = TumbleQueue(roundSeed: roundSeed)
        return setDown(box, queue: &queue, n: n, rot: rot, x: x, y: y, landed: landed)
    }

    /// The same, drawing toys from a queue that keeps its dealt bags.
    public static func setDown(
        _ box: TumbleBox, queue: inout TumbleQueue, n: Int, rot: Int, x: Int, y: Int, landed: [Int]
    ) -> Result<TumbleSetDown, TumbleSetDownError> {
        if box.out { return .failure(.boxOut) }
        if n != box.next { return .failure(.notNext) }
        let toy = queue.toy(n)
        if !fits(box, toy: toy, rot: rot, x: x, y: y) { return .failure(.badPlace) }
        if fits(box, toy: toy, rot: rot, x: x, y: y - 1) { return .failure(.notResting) }
        if landed.count > box.waiting.count { return .failure(.badLanded) }
        for (i, id) in landed.enumerated() where box.waiting[i].id != id { return .failure(.badLanded) }

        var b = box
        for c in TumbleToys.cells(toy, rot: rot) { b.cells[idx(x + c.x, y + c.y)] = toy.index + 1 }
        let full = fullRows(b)
        if !full.isEmpty && !landed.isEmpty { return .failure(.badLanded) }
        var pocketed: [TumbleTrick] = []
        removeRows(&b, full, &pocketed)
        let cleared = full.count
        var left = attack[min(cleared, 4)]

        var blocked: [TumbleBlocked] = []
        while left > 0 && !b.waiting.isEmpty {
            let take = min(left, b.waiting[0].rows)
            b.waiting[0].rows -= take
            left -= take
            blocked.append(TumbleBlocked(id: b.waiting[0].id, rows: take))
            if b.waiting[0].rows == 0 { b.waiting.removeFirst() }
        }
        spawnTricks(&b, cleared)
        for _ in landed {
            let w = b.waiting.removeFirst()
            pushJunk(&b, rows: w.rows, gap: w.gap)
        }
        b.rows += cleared
        b.next = n + 1
        let nextToy = queue.toy(n + 1)
        let at = TumbleToys.spawn(nextToy)
        b.out = anyAbove(b) || !fits(b, toy: nextToy, rot: at.rot, x: at.x, y: at.y)
        return .success(TumbleSetDown(box: b, cleared: cleared, sent: left, blocked: blocked, pocketed: pocketed, out: b.out, clearedRows: full))
    }

    /// Junk that has arrived and starts its wait (§4.5).
    public static func receiveJunk(_ box: TumbleBox, _ w: TumbleWaiting) -> TumbleBox {
        if box.out { return box }
        var b = box
        b.waiting.append(w)
        return b
    }

    /// A trick's effect on this box (§4.6). Rows a trick removes are not clears.
    public static func applyHit(_ box: TumbleBox, _ hit: TumbleHit) -> (box: TumbleBox, pocketed: [TumbleTrick]) {
        if box.out { return (box, []) }
        var b = box
        var pocketed: [TumbleTrick] = []
        switch hit {
        case .hairball(let gap):
            pushJunk(&b, rows: 1, gap: gap)
        case .swipe(let shifts):
            var cells = b.cells
            var tricks = b.tricks
            for y in 0..<total {
                let s = y < shifts.count ? shifts[y] : 0
                for x in 0..<width {
                    let to = (((x + s) % width) + width) % width
                    cells[idx(to, y)] = b.cells[idx(x, y)]
                    tricks[idx(to, y)] = b.tricks[idx(x, y)]
                }
            }
            b.cells = cells
            b.tricks = tricks
        case .scoop:
            removeRows(&b, [0, 1], &pocketed)
        case .settle:
            var cells = Array(repeating: 0, count: total * width)
            var tricks = Array(repeating: 0, count: total * width)
            for x in 0..<width {
                var to = 0
                for y in 0..<total where b.cells[idx(x, y)] != 0 {
                    cells[idx(x, to)] = b.cells[idx(x, y)]
                    tricks[idx(x, to)] = b.tricks[idx(x, y)]
                    to += 1
                }
            }
            b.cells = cells
            b.tricks = tricks
            removeRows(&b, fullRows(b), &pocketed)
        case .bath:
            b.cells = Array(repeating: 0, count: total * width)
            b.tricks = Array(repeating: 0, count: total * width)
            b.waiting = []
        case .swap(let cells, let tricks):
            b.cells = cells
            b.tricks = tricks
        case .catnip, .nap:
            break
        }
        b.out = anyAbove(b)
        return (b, pocketed)
    }

    /// Takes the trick in `slot` out of the box's held tricks, or nil when there is none.
    public static func useTrick(_ box: TumbleBox, slot: Int) -> (box: TumbleBox, trick: TumbleTrick)? {
        if box.out || slot < 0 || slot >= box.held.count { return nil }
        var b = box
        let trick = b.held.remove(at: slot)
        return (b, trick)
    }

    /// Where a toy rests if dropped straight down from `y` at this rotation and column, or nil when it can't be there.
    public static func restingY(_ box: TumbleBox, toy: TumbleToy, rot: Int, x: Int, from y: Int) -> Int? {
        guard fits(box, toy: toy, rot: rot, x: x, y: y) else { return nil }
        var y = y
        while fits(box, toy: toy, rot: rot, x: x, y: y - 1) { y -= 1 }
        return y
    }
}
