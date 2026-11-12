/// The next thing a player could do, for easy mode's "show me" paw (tile game spec §5.10). It
/// runs on the device with the House Cat's greedy finders (`apps/play-api/src/tiles/solver.ts`:
/// `findSets` and the end-of-a-set half of `placeOnTable`), so nothing is sent or logged. It
/// looks at the rack and the rug as drafted and never suggests a rearrangement.
public enum TilesHints {
    public enum Hint: Equatable, Sendable {
        /// Rack pieces that make a set as they are, in set order.
        case newSet([TileID])
        /// A rack piece and the set (by draft id) it fits on the end of.
        case fits(tile: TileID, set: Int)
    }

    /// Sets that can be made from `rack`'s number pieces alone, greedily: all the rows and then
    /// matches from what is left, or the other way round. Yarn is left out.
    public static func findSets(_ rack: [TileID], runsFirst: Bool) -> [[TileID]] {
        // [suit][value] holds up to two ids.
        var grid = Array(repeating: Array(repeating: [TileID](), count: Tile.maxValue + 2), count: TileSuit.allCases.count)
        for id in rack {
            if case .number(let value, let suit)? = Tile.decode(id) { grid[suit.index][value].append(id) }
        }
        func takeRuns() -> [[TileID]] {
            var runs: [[TileID]] = []
            for suit in grid.indices {
                // Twice: the second copy of a number can start a second row.
                for _ in 0..<2 {
                    var stretch: [Int] = []
                    for value in 1...(Tile.maxValue + 1) {
                        if !grid[suit][value].isEmpty {
                            stretch.append(value)
                            continue
                        }
                        if stretch.count >= TilesRules.minSet { runs.append(stretch.map { grid[suit][$0].removeFirst() }) }
                        stretch = []
                    }
                }
            }
            return runs
        }
        func takeGroups() -> [[TileID]] {
            var groups: [[TileID]] = []
            for value in 1...Tile.maxValue {
                for _ in 0..<2 {
                    let held = grid.indices.filter { !grid[$0][value].isEmpty }
                    guard held.count >= TilesRules.minSet else { continue }
                    // Two toys held twice and two held once make two matches of three.
                    let twice = held.filter { grid[$0][value].count == 2 }
                    let once = held.filter { grid[$0][value].count == 1 }
                    let from = twice.count == 2 && once.count == 2 ? twice + [once[0]] : held
                    groups.append(from.map { grid[$0][value].removeFirst() })
                }
            }
            return groups
        }
        if runsFirst {
            let runs = takeRuns()
            return runs + takeGroups()
        }
        let groups = takeGroups()
        return groups + takeRuns()
    }

    /// The better of the two greedy orders: the sets worth the most.
    public static func bestSets(_ rack: [TileID]) -> [[TileID]] {
        let a = findSets(rack, runsFirst: true), b = findSets(rack, runsFirst: false)
        return points(a) >= points(b) ? a : b
    }

    static func points(_ sets: [[TileID]]) -> Int {
        sets.reduce(0) { $0 + (TilesRules.readSet($1)?.points ?? 0) }
    }

    /// What to light: a set waiting in the rack (the one worth the most), else a piece that goes
    /// on the end of a set on the rug. Before opening only new sets count, and only once the
    /// rack's sets (with the ones already drafted) reach 30. Nil when the finder comes up empty:
    /// time to draw.
    public static func next(_ draft: TilesDraft) -> Hint? {
        let rack = draft.rack
        let sets = bestSets(rack)
        if !draft.opened {
            guard draft.newPoints + points(sets) >= TilesRules.openingPoints else { return nil }
        }
        let best = sets.max { (TilesRules.readSet($0)?.points ?? 0) < (TilesRules.readSet($1)?.points ?? 0) }
        if let best { return .newSet(best) }
        for tile in rack {
            for set in draft.shownSets where !draft.isLocked(set.id) {
                if TilesRules.readSet(set.tiles + [tile]) != nil || TilesRules.readSet([tile] + set.tiles) != nil {
                    return .fits(tile: tile, set: set.id)
                }
            }
        }
        return nil
    }

    /// True when `tiles` could join the set and leave it a row or a match (easy mode: a piece
    /// that can't goes back to the rack instead of leaving a broken set).
    public static func fits(_ tiles: [TileID], in set: [TileID]) -> Bool {
        for side in [TilesDraft.Side.end, .start] {
            if TilesRules.readSet(TilesDraft.arrange(set, adding: tiles, toward: side)) != nil { return true }
        }
        return false
    }
}
