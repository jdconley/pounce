import Foundation

/// One card on Home: a server table entry joined with the local cache of its last snapshot.
public struct HomeTableItem: Equatable, Sendable, Identifiable {
    /// The room code.
    public var id: String
    public var yourTurn: Bool
    public var status: String
    /// Seat summaries from the cache; empty until the room has been opened on this phone.
    public var seats: [CachedSeat]
    /// The cat of the seat whose turn it is, when the cache knows it.
    public var turnCat: Int?
    /// Epoch milliseconds, as the server reports it.
    public var updatedAt: Double

    public init(
        id: String, yourTurn: Bool, status: String, seats: [CachedSeat], turnCat: Int?, updatedAt: Double
    ) {
        self.id = id
        self.yourTurn = yourTurn
        self.status = status
        self.seats = seats
        self.turnCat = turnCat
        self.updatedAt = updatedAt
    }
}

public enum HomeTables {
    /// Finished tables stay on Home this long after their last update.
    static let finishedLifetimeMs: Double = 24 * 3_600_000

    /// The server's list is the truth for which tables exist; the cache only adds cats and names.
    /// Order: your-turn tables (newest first), then playing/lobby tables by recency, then finished
    /// tables from the last 24 hours. Older finished tables are dropped, as is any cached code the
    /// server no longer lists.
    public static func merge(
        entries: [TableEntry], cache: [String: CachedTable], now: Date
    ) -> [HomeTableItem] {
        let nowMs = now.timeIntervalSince1970 * 1000
        var mine: [HomeTableItem] = []
        var live: [HomeTableItem] = []
        var finished: [HomeTableItem] = []
        for entry in entries {
            let isOver = entry.status == RoomStatus.over.rawValue
            if isOver && nowMs - entry.updatedAt >= finishedLifetimeMs { continue }
            let cached = cache[entry.code]
            let seats = cached?.seats ?? []
            var turnCat: Int?
            if let turn = cached?.turn, seats.indices.contains(turn) { turnCat = seats[turn].cat }
            let item = HomeTableItem(
                id: entry.code, yourTurn: entry.yourTurn && !isOver, status: entry.status,
                seats: seats, turnCat: turnCat, updatedAt: entry.updatedAt)
            if isOver {
                finished.append(item)
            } else if item.yourTurn {
                mine.append(item)
            } else {
                live.append(item)
            }
        }
        let newestFirst: (HomeTableItem, HomeTableItem) -> Bool = { $0.updatedAt > $1.updatedAt }
        return mine.sorted(by: newestFirst) + live.sorted(by: newestFirst) + finished.sorted(by: newestFirst)
    }
}
