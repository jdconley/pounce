import Foundation

/// One card on Home: a server table entry joined with the local cache of its last snapshot.
public struct HomeTableItem: Equatable, Sendable, Identifiable {
    /// The room code.
    public var id: String
    /// The table's name: the server's list, else the cache, else nil (see `title`).
    public var name: String?
    public var yourTurn: Bool
    public var status: String
    /// Seat summaries from the cache; empty until the room has been opened on this phone.
    public var seats: [CachedSeat]
    /// The cat of the seat whose turn it is, when the cache knows it.
    public var turnCat: Int?
    /// Epoch milliseconds, as the server reports it.
    public var updatedAt: Double

    public init(
        id: String, name: String? = nil, yourTurn: Bool, status: String, seats: [CachedSeat], turnCat: Int?,
        updatedAt: Double
    ) {
        self.id = id
        self.name = name
        self.yourTurn = yourTurn
        self.status = status
        self.seats = seats
        self.turnCat = turnCat
        self.updatedAt = updatedAt
    }

    /// The name to show on the card.
    public var title: String { name ?? TableName.fallback(code: id) }
}

public enum HomeTables {
    /// Finished tables stay on Home this long after their last update.
    static let finishedLifetimeMs: Double = 24 * 3_600_000

    /// The server's list is the truth for which tables exist (and, when it has one, the table's
    /// name); the cache only adds cats, seat names and a name the list lacks.
    /// Order: your-turn tables (newest first), then playing/lobby tables by recency, then finished
    /// tables from the last 24 hours. Older finished tables are dropped, as is any cached code the
    /// server no longer lists, and any table archived on this phone (`archived`, see `isArchived`).
    public static func merge(
        entries: [TableEntry], cache: [String: CachedTable], archived: [String: Double] = [:], now: Date
    ) -> [HomeTableItem] {
        let shown = entries.filter { !isArchived($0, mark: archived[$0.code]) }
        var mine: [HomeTableItem] = []
        var live: [HomeTableItem] = []
        var finished: [HomeTableItem] = []
        for item in items(shown, cache: cache, now: now) {
            if item.status == RoomStatus.over.rawValue {
                finished.append(item)
            } else if item.yourTurn {
                mine.append(item)
            } else {
                live.append(item)
            }
        }
        return mine.sorted(by: newestFirst) + live.sorted(by: newestFirst) + finished.sorted(by: newestFirst)
    }

    /// The archived tables the server still lists, newest first (Home's Archived sheet). Finished
    /// ones leave after 24 hours here too.
    public static func archivedItems(
        entries: [TableEntry], cache: [String: CachedTable], archived: [String: Double], now: Date
    ) -> [HomeTableItem] {
        let hidden = entries.filter { isArchived($0, mark: archived[$0.code]) }
        return items(hidden, cache: cache, now: now).sorted(by: newestFirst)
    }

    /// An archived table stays off Home until it is your turn there again after someone moved
    /// since it was archived (`mark`, the server's `updatedAt` then): like a new message bringing
    /// an archived chat back. A table that sits on your turn untouched stays archived.
    public static func isArchived(_ entry: TableEntry, mark: Double?) -> Bool {
        guard let mark else { return false }
        let isOver = entry.status == RoomStatus.over.rawValue
        return !(entry.yourTurn && !isOver && entry.updatedAt > mark)
    }

    /// The archive worth keeping after a fresh `/tables`: codes the server still lists that are
    /// still archived. A table that came back stays back when its turn passes.
    public static func keptArchive(entries: [TableEntry], archived: [String: Double]) -> [String: Double] {
        var kept: [String: Double] = [:]
        for entry in entries {
            if let mark = archived[entry.code], isArchived(entry, mark: mark) { kept[entry.code] = mark }
        }
        return kept
    }

    private static func newestFirst(_ a: HomeTableItem, _ b: HomeTableItem) -> Bool { a.updatedAt > b.updatedAt }

    /// One item per entry, joined with the cache; finished tables older than 24 hours are dropped.
    private static func items(
        _ entries: [TableEntry], cache: [String: CachedTable], now: Date
    ) -> [HomeTableItem] {
        let nowMs = now.timeIntervalSince1970 * 1000
        return entries.compactMap { entry in
            let isOver = entry.status == RoomStatus.over.rawValue
            if isOver && nowMs - entry.updatedAt >= finishedLifetimeMs { return nil }
            let cached = cache[entry.code]
            let seats = cached?.seats ?? []
            var turnCat: Int?
            if let turn = cached?.turn, seats.indices.contains(turn) { turnCat = seats[turn].cat }
            return HomeTableItem(
                id: entry.code, name: entry.name ?? cached?.name, yourTurn: entry.yourTurn && !isOver, status: entry.status,
                seats: seats, turnCat: turnCat, updatedAt: entry.updatedAt)
        }
    }
}
