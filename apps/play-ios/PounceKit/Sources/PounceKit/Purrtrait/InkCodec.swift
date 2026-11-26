import Foundation

/// The easel's fixed numbers (spec §6.1, §6.3): a portrait 3:4 grid, eight colours plus the
/// eraser, three widths, and how much the drawer's device sends.
public enum InkGrid {
    public static let width = 768
    public static let height = 1024
    /// Colours 0-7, black first; 8 is white, the eraser.
    public static let colors = 9
    public static let eraser = 8
    /// Widths 0-2, in grid units.
    public static let widths: [Double] = [4, 10, 24]
    /// A point closer than this to the last one kept is dropped.
    public static let minStep = 2.0
    /// Ramer-Douglas-Peucker tolerance, in grid units.
    public static let tolerance = 1.0
    /// A batch goes this often while a finger draws (and at once when a stroke ends).
    public static let batchEvery: Duration = .milliseconds(50)
    /// At most this many `ink` messages a second (the server drops more).
    public static let perSecond = 25
    /// Every delta stays inside this.
    public static let maxDelta = 768
    /// An `ink` message stays under this many bytes as JSON (the server takes 8 KB, envelope too).
    public static let messageBytes = 7_000
    /// The server's caps per turn.
    public static let maxStrokes = 500
    public static let maxPoints = 30_000

    /// The palette, sRGB 0-255, matched with the web player (notes `purrtrait-ios-tv.md`).
    public static let rgb: [(r: Int, g: Int, b: Int)] = [
        (0x1A, 0x14, 0x26),  // 0 black
        (0xFF, 0x3B, 0x4A),  // 1 red
        (0xFF, 0x94, 0x19),  // 2 orange
        (0xFF, 0xD4, 0x00),  // 3 yellow
        (0x2E, 0xCC, 0x5B),  // 4 green
        (0x2F, 0x80, 0xFF),  // 5 blue
        (0x9B, 0x4D, 0xFF),  // 6 purple
        (0x8B, 0x5A, 0x2B),  // 7 brown
        (0xFF, 0xFF, 0xFF),  // 8 white, the eraser
    ]

    public static func clamp(_ p: InkPoint) -> InkPoint {
        InkPoint(min(max(p.x, 0), width - 1), min(max(p.y, 0), height - 1))
    }

    /// A width number's size in grid units (an unknown number reads as the middle one).
    public static func size(_ width: Int) -> Double { widths.indices.contains(width) ? widths[width] : widths[1] }
}

/// The pure pieces of ink, shared by the drawer's device and the TV.
public enum InkCodec {
    // MARK: filtering and simplifying

    /// Drops every point less than `InkGrid.minStep` from the last one kept (`last` is the
    /// stroke's last point kept so far, if any). Returns the points to keep.
    public static func filter(_ points: [InkPoint], after last: InkPoint?) -> [InkPoint] {
        var kept: [InkPoint] = []
        var prev = last
        for p in points {
            if let q = prev, distance(p, q) < InkGrid.minStep { continue }
            kept.append(p)
            prev = p
        }
        return kept
    }

    /// Ramer-Douglas-Peucker: the fewest points within `tolerance` of the line. Keeps the first
    /// and the last point always.
    public static func simplify(_ points: [InkPoint], tolerance: Double = InkGrid.tolerance) -> [InkPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var worst = -1.0
            var at = a
            for i in (a + 1)..<b {
                let d = lineDistance(points[i], points[a], points[b])
                if d > worst {
                    worst = d
                    at = i
                }
            }
            if worst > tolerance {
                keep[at] = true
                stack.append((a, at))
                stack.append((at, b))
            }
        }
        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }

    static func distance(_ a: InkPoint, _ b: InkPoint) -> Double {
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func lineDistance(_ p: InkPoint, _ a: InkPoint, _ b: InkPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return distance(p, a) }
        return abs(dy * Double(p.x - a.x) - dx * Double(p.y - a.y)) / len
    }

    /// Steps from `from` through `points`, each split so no step is over `InkGrid.maxDelta` on
    /// either axis.
    public static func deltas(from: InkPoint, through points: [InkPoint]) -> [InkPoint] {
        var out: [InkPoint] = []
        out.reserveCapacity(points.count)
        var prev = from
        for p in points {
            let d = p - prev
            let parts = max(1, (max(abs(d.x), abs(d.y)) + InkGrid.maxDelta - 1) / InkGrid.maxDelta)
            if parts == 1 {
                out.append(d)
            } else {
                var at = prev
                for k in 1...parts {
                    let next = InkPoint(prev.x + d.x * k / parts, prev.y + d.y * k / parts)
                    out.append(next - at)
                    at = next
                }
            }
            prev = p
        }
        return out
    }

    // MARK: compacting

    /// The smallest list of ops that draws the same picture (as the server's `compact`): undone
    /// strokes and everything before the last clear are left out.
    public static func compact(_ ops: [InkOp]) -> [InkOp] {
        var start = 0
        if let c = ops.lastIndex(of: .clear) { start = c + 1 }
        let tail = ops[start...]
        var undone = Set<Int>()
        for op in tail { if case .undo(let id) = op { undone.insert(id) } }
        return tail.filter { op in
            switch op {
            case .stroke(let id, _, _, _, _), .extend(let id, _): !undone.contains(id)
            case .undo, .clear: false
            }
        }
    }

    // MARK: sizes

    /// About how many bytes `op` takes as JSON, a little over.
    public static func estimatedBytes(_ op: InkOp) -> Int {
        func n(_ v: Int) -> Int {
            var digits = v < 0 ? 2 : 1
            var a = abs(v)
            while a >= 10 {
                a /= 10
                digits += 1
            }
            return digits + 1  // the comma
        }
        switch op {
        case .stroke(let id, let color, let width, let start, let deltas):
            return 8 + n(id) + n(color) + n(width) + n(start.x) + n(start.y) + deltas.reduce(0) { $0 + n($1.x) + n($1.y) }
        case .extend(let id, let deltas):
            return 8 + n(id) + deltas.reduce(0) { $0 + n($1.x) + n($1.y) }
        case .undo(let id):
            return 8 + n(id)
        case .clear:
            return 6
        }
    }

    /// Splits `ops` into messages under `limit` bytes each, in order. A stroke too long for one
    /// message goes on as `p` ops in the next ones.
    public static func chunk(_ ops: [InkOp], limit: Int = InkGrid.messageBytes) -> [[InkOp]] {
        var messages: [[InkOp]] = []
        var current: [InkOp] = []
        var size = 60  // the envelope: {"t":"ink","seat":n,"turn":"…","ops":[…]}
        func close() {
            if !current.isEmpty { messages.append(current) }
            current = []
            size = 60
        }
        func add(_ op: InkOp) {
            let bytes = estimatedBytes(op)
            if size + bytes > limit { close() }
            current.append(op)
            size += bytes
        }
        for op in ops {
            guard estimatedBytes(op) + 60 > limit else {
                add(op)
                continue
            }
            // Too big for one message: the start and as many points as fit, then `p` ops.
            let (id, head, deltas): (Int, InkOp?, [InkPoint]) = {
                switch op {
                case .stroke(let id, let color, let width, let start, let deltas):
                    return (id, .stroke(id: id, color: color, width: width, start: start, deltas: []), deltas)
                case .extend(let id, let deltas):
                    return (id, nil, deltas)
                default:
                    return (0, op, [])
                }
            }()
            if let head { add(head) }
            var rest = deltas[...]
            let per = max(1, (limit - 120) / 12)
            while !rest.isEmpty {
                let piece = Array(rest.prefix(per))
                rest = rest.dropFirst(piece.count)
                add(.extend(id: id, deltas: piece))
            }
        }
        close()
        return messages
    }
}

/// A picture made of ops: the visible strokes in drawing order, with absolute points. The TV and
/// the drawer's device both keep one; `apply` says what changed so a renderer redraws only that.
public struct InkDrawing: Equatable, Sendable {
    public struct Stroke: Equatable, Sendable {
        public var id: Int
        public var color: Int
        public var width: Int
        public var points: [InkPoint]

        public init(id: Int, color: Int, width: Int, points: [InkPoint]) {
            self.id = id
            self.color = color
            self.width = width
            self.points = points
        }
    }

    /// What one op changed.
    public enum Change: Equatable, Sendable {
        /// A new stroke at the end: the one before it is finished.
        case started
        /// The last stroke got points.
        case extended
        /// A finished stroke went or changed: the finished picture needs drawing again.
        case finishedChanged
        /// The stroke in progress went.
        case removedLive
        case cleared
        /// Nothing (an op for a stroke that isn't there).
        case none
    }

    public private(set) var strokes: [Stroke] = []
    /// The points in the visible strokes.
    public private(set) var points = 0

    public init() {}

    public init(ops: [InkOp]) {
        for op in ops { apply(op) }
    }

    public var isEmpty: Bool { strokes.isEmpty }

    /// The stroke still being drawn: the newest one.
    public var live: Stroke? { strokes.last }

    /// Every stroke but the newest.
    public var finished: ArraySlice<Stroke> { strokes.dropLast() }

    /// The highest stroke id seen this turn, visible or not.
    public private(set) var highestID = -1

    @discardableResult public mutating func apply(_ op: InkOp) -> Change {
        switch op {
        case .stroke(let id, let color, let width, let start, let deltas):
            var pts = [start]
            pts.reserveCapacity(deltas.count + 1)
            var at = start
            for d in deltas {
                at = at + d
                pts.append(at)
            }
            strokes.append(Stroke(id: id, color: color, width: width, points: pts))
            points += pts.count
            highestID = max(highestID, id)
            return .started
        case .extend(let id, let deltas):
            guard let i = strokes.lastIndex(where: { $0.id == id }), !deltas.isEmpty else { return .none }
            var at = strokes[i].points.last ?? InkPoint(0, 0)
            for d in deltas {
                at = at + d
                strokes[i].points.append(at)
            }
            points += deltas.count
            return i == strokes.count - 1 ? .extended : .finishedChanged
        case .undo(let id):
            guard let i = strokes.lastIndex(where: { $0.id == id }) else { return .none }
            let wasLive = i == strokes.count - 1
            points -= strokes[i].points.count
            strokes.remove(at: i)
            return wasLive ? .removedLive : .finishedChanged
        case .clear:
            strokes.removeAll()
            points = 0
            return .cleared
        }
    }

    /// The ops that draw this picture, one `s` per stroke, ids as they are.
    public var ops: [InkOp] {
        strokes.map { s in
            .stroke(id: s.id, color: s.color, width: s.width, start: s.points[0],
                    deltas: InkCodec.deltas(from: s.points[0], through: Array(s.points.dropFirst())))
        }
    }
}
