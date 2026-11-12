/// The order a rack is shown in (tile game spec §5.3): free, by number or by toy. Local only;
/// nothing here is ever sent. It is kept per table on the device (`TilesDeviceStore`).
///
/// The order covers every piece the seat holds this turn, the ones placed on the rug too, so a
/// piece taken back returns to its old place. Show `shown(_:)` of the draft's rack.
public struct RackOrder: Equatable, Sendable, Codable {
    public enum Sort: String, Equatable, Sendable, Codable {
        /// 1s together, then 2s: matches show.
        case number
        /// Each toy in order: rows show.
        case toy
    }

    /// The order shown.
    public private(set) var tiles: [TileID] = []
    /// The sort applied last. A manual move, or the same toggle again, clears it.
    public private(set) var sort: Sort?
    /// The player's own order, which a second tap on a sort goes back to.
    private var free: [TileID] = []

    public init() {}

    /// Keeps the order of pieces still in `rack` and puts new ones (a draw) at the right end, in
    /// the server's order. A new piece joins the sort on the next toggle, not before.
    public mutating func sync(_ rack: [TileID]) {
        tiles = Self.synced(tiles, with: rack)
        free = Self.synced(free, with: rack)
    }

    private static func synced(_ order: [TileID], with rack: [TileID]) -> [TileID] {
        var remaining = rack
        var kept: [TileID] = []
        for tile in order {
            if let i = remaining.firstIndex(of: tile) {
                kept.append(tile)
                remaining.remove(at: i)
            }
        }
        return kept + remaining
    }

    /// The pieces of `rack` in the order shown.
    public func shown(_ rack: [TileID]) -> [TileID] {
        let here = Set(rack)
        let known = tiles.filter(here.contains)
        let seen = Set(known)
        return known + rack.filter { !seen.contains($0) }
    }

    /// One of the two sort toggles: sorts that way, or goes back to the free order when the rack
    /// is already sorted that way.
    public mutating func toggle(_ wanted: Sort) {
        if sort == wanted {
            tiles = free
            sort = nil
        } else {
            tiles = Self.sorted(tiles, by: wanted)
            sort = wanted
        }
    }

    /// Sorts `wanted`'s way whatever the toggles say (easy mode: the rack sorts itself).
    public mutating func apply(_ wanted: Sort) {
        tiles = Self.sorted(tiles, by: wanted)
        sort = wanted
    }

    /// Moves `moving` (one piece, or several lifted together) into slot `slot` of the rack as
    /// drawn: `shown` is the rack left to right, and afterwards it reads `shown` without them
    /// with `moving` at `slot`. Pieces not shown (placed on the rug) keep their places. The
    /// order is the player's own from here on.
    public mutating func move(_ moving: [TileID], toSlot slot: Int, shown: [TileID]) {
        let lifted = moving.filter(tiles.contains)
        guard !lifted.isEmpty else { return }
        let others = shown.filter { !lifted.contains($0) && tiles.contains($0) }
        let slot = min(max(slot, 0), others.count)
        var next = tiles.filter { !lifted.contains($0) }
        if slot < others.count, let at = next.firstIndex(of: others[slot]) {
            next.insert(contentsOf: lifted, at: at)
        } else if let last = others.last, let at = next.firstIndex(of: last) {
            // Just after the last piece shown, so pieces out on the rug keep their places.
            next.insert(contentsOf: lifted, at: at + 1)
        } else {
            next.append(contentsOf: lifted)
        }
        tiles = next
        free = next
        sort = nil
    }

    static func sorted(_ tiles: [TileID], by sort: Sort) -> [TileID] {
        tiles.sorted { key($0, sort).lexicographicallyPrecedes(key($1, sort)) }
    }

    /// Numbers first (by number then toy, or toy then number), then Yarn.
    static func key(_ id: TileID, _ sort: Sort) -> [Int] {
        guard case .number(let value, let suit)? = Tile.decode(id) else { return [1, 0, 0, id] }
        return sort == .number ? [0, value, suit.index, id] : [0, suit.index, value, id]
    }

    /// Ready sets (tile game spec §5.3): stretches of `shown`, left to right, that are already a
    /// row or a match as they sit, each as long as it can be. Only in a sorted view: in the free
    /// order nothing is pulled together.
    public func readySets(in shown: [TileID]) -> [Range<Int>] {
        guard sort != nil else { return [] }
        var found: [Range<Int>] = []
        var i = 0
        while i < shown.count {
            var best: Int?
            var j = min(shown.count, i + Tile.maxValue)
            while j - i >= TilesRules.minSet {
                let window = Array(shown[i..<j])
                // Number pieces only: a Yarn sitting next to them hasn't been spent on anything.
                if !window.contains(where: Tile.isYarn), TilesRules.readSet(window) != nil {
                    best = j
                    break
                }
                j -= 1
            }
            if let best {
                found.append(i..<best)
                i = best
            } else {
                i += 1
            }
        }
        return found
    }
}
