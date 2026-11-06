import Foundation

/// The trophy room's model (trophy room design §3, D4): the records row, the shelf of what you've
/// earned (loudest first), the locked silhouettes still to earn (nearest first), your connections.
public struct TrophyRoom: Equatable, Sendable {
    public enum RecordKind: String, Sendable { case current, best, longestPair, totalDays, perfectWeeks }

    public struct Record: Equatable, Sendable, Identifiable {
        public var kind: RecordKind
        public var value: Int
        public var id: String { kind.rawValue }
    }

    public struct ShelfItem: Equatable, Sendable, Identifiable {
        public var id: String
        public var kind: Trophies.Kind
    }

    public var records: [Record]
    public var shelf: [ShelfItem]
    public var locked: [Trophies.Item]
    public var connections: [StreakView]

    public init(_ t: Trophies) {
        let r = t.records
        records = [
            Record(kind: .current, value: r.current), Record(kind: .best, value: r.best),
            Record(kind: .longestPair, value: r.longestPair), Record(kind: .totalDays, value: r.totalDays),
            Record(kind: .perfectWeeks, value: r.perfectWeeks),
        ]
        let e = t.earned
        let rarity: [StreakCatalog.Rarity] = [.golden, .shiny, .common]
        let toys = rarity.flatMap { r in e.toys.filter { StreakCatalog.rarity($0) == r } }
        shelf = (e.condoStage > 0 ? [ShelfItem(id: "condo-\(e.condoStage)", kind: .condo)] : [])
            + e.rugs.map { ShelfItem(id: $0, kind: .rug) }
            + e.backs.map { ShelfItem(id: $0, kind: .back) }
            + toys.map { ShelfItem(id: $0, kind: .toy) }
        let owned = Set(e.toys + e.backs + e.rugs)
        let open = t.catalog.enumerated().filter { _, item in
            switch item.kind {
            case .condo: (Int(item.id.dropFirst("condo-".count)) ?? 0) > e.condoStage
            case .back, .rug, .toy: !owned.contains(item.id)
            case .unknown: false
            }
        }
        locked = open.sorted { a, b in a.element.progress != b.element.progress ? a.element.progress > b.element.progress : a.offset < b.offset }
            .map(\.element)
        connections = t.connections
    }

    /// A ring's drawn fill: a sliver even at 0 (endowed, as the milestone arc), never past full.
    public static func ring(_ progress: Double) -> Double {
        min(1, max(0.06, progress))
    }
}
