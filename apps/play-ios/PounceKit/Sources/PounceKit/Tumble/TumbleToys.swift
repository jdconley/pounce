import Foundation

/// The nine Toy Tumble toys (spec §4.1), a port of play-api's `tumble/toys.ts`. These values are
/// the contract with the server's engine and the shared vectors; change them only together.
public enum TumbleToy: String, CaseIterable, Codable, Sendable, Hashable {
    case i3, v3, i4, o4, t4, l4, j4, p5, u5

    /// Its index in `TOY_IDS`: a settled cell holds this + 1.
    public var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// The toy a settled cell's value (1 to 9) came from.
    public init?(cell: Int) {
        guard cell >= 1, cell <= Self.allCases.count else { return nil }
        self = Self.allCases[cell - 1]
    }
}

/// A cell offset, x to the right and y up.
public struct TumbleCell: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

/// A toy's rotation and the bottom-left corner of its own k by k box.
public struct TumbleSpot: Hashable, Sendable, Codable {
    public var rot: Int
    public var x: Int
    public var y: Int
    public init(rot: Int, x: Int, y: Int) {
        self.rot = rot
        self.x = x
        self.y = y
    }
}

public enum TumbleToys {
    static let width = 12
    static let spawnRow = 18

    /// Each toy's cells at rotation 0 inside a k by k box, in `TumbleToy.allCases` order.
    private static let base: [(k: Int, cells: [TumbleCell])] = [
        (3, [.init(0, 1), .init(1, 1), .init(2, 1)]),
        (2, [.init(0, 0), .init(0, 1), .init(1, 0)]),
        (4, [.init(0, 2), .init(1, 2), .init(2, 2), .init(3, 2)]),
        (2, [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)]),
        (3, [.init(0, 1), .init(1, 1), .init(2, 1), .init(1, 2)]),
        (3, [.init(0, 1), .init(1, 1), .init(2, 1), .init(2, 2)]),
        (3, [.init(0, 1), .init(1, 1), .init(2, 1), .init(0, 2)]),
        (3, [.init(1, 0), .init(0, 1), .init(1, 1), .init(2, 1), .init(1, 2)]),
        (3, [.init(0, 0), .init(1, 0), .init(2, 0), .init(0, 1), .init(2, 1)]),
    ]

    private static let table: [[[TumbleCell]]] = base.map { entry in
        var rots = [entry.cells]
        for r in 1..<4 { rots.append(rots[r - 1].map { TumbleCell($0.y, entry.k - 1 - $0.x) }) }
        return rots
    }

    /// The toy's cells at `rot`, as offsets from its box's bottom-left corner. Clockwise turns keep the cell order.
    public static func cells(_ toy: TumbleToy, rot: Int) -> [TumbleCell] { table[toy.index][((rot % 4) + 4) % 4] }

    /// The side of the square box a toy turns in.
    public static func size(_ toy: TumbleToy) -> Int { base[toy.index].k }

    /// Where a new toy appears: rotation 0, centred (rounding left), lowest cells in row 18.
    public static func spawn(_ toy: TumbleToy) -> TumbleSpot {
        let k = size(toy)
        let low = cells(toy, rot: 0).map(\.y).min() ?? 0
        return TumbleSpot(rot: 0, x: (width - k) / 2, y: spawnRow - low)
    }
}
