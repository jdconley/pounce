import Foundation

public struct CachedSeat: Codable, Equatable, Sendable {
    public var kind: SeatKind
    public var name: String?
    public var cat: Int?
    public var yours: Bool
    /// The seated person's id; nil in caches written before Home showed names.
    public var person: String?

    public init(kind: SeatKind, name: String? = nil, cat: Int? = nil, yours: Bool = false, person: String? = nil) {
        self.kind = kind
        self.name = name
        self.cat = cat
        self.yours = yours
        self.person = person
    }

    /// A seat from the server's tables list.
    public init(_ seat: TableSeat) {
        self.init(kind: seat.kind, name: seat.person?.name, cat: seat.person?.cat, yours: seat.yours, person: seat.person?.id)
    }
}

/// Just enough of a table to draw its Home tile before the socket connects.
public struct CachedTable: Codable, Equatable, Sendable {
    public var code: String
    /// Nil in caches written before tables had names.
    public var name: String?
    public var status: RoomStatus
    public var seats: [CachedSeat]
    public var turn: Seat?
    public var phase: [Int]
    public var updatedAt: Date

    public init(
        code: String, name: String? = nil, status: RoomStatus, seats: [CachedSeat], turn: Seat? = nil,
        phase: [Int] = [], updatedAt: Date
    ) {
        self.code = code
        self.name = name
        self.status = status
        self.seats = seats
        self.turn = turn
        self.phase = phase
        self.updatedAt = updatedAt
    }
}

/// `tables.json` (or a per-server `fileName`) in the given directory, keyed by room code,
/// written atomically. Not thread-safe by itself; callers use it from one actor (the app model).
public final class TableCache {
    private let fileURL: URL

    public init(directory: URL, fileName: String = "tables.json") {
        fileURL = directory.appendingPathComponent(fileName)
    }

    /// One server's cache file, `tables.<host>_<port>.json`: room codes belong to a server.
    public static func fileName(for config: APIConfig) -> String {
        "tables.\(config.serverKey.replacingOccurrences(of: ":", with: "_")).json"
    }

    public func all() -> [String: CachedTable] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([String: CachedTable].self, from: data)) ?? [:]
    }

    public func store(_ room: RoomView, now: Date = .now) {
        var tables = all()
        tables[room.code] = CachedTable(
            code: room.code, name: room.name, status: room.status,
            seats: room.seats.map {
                CachedSeat(kind: $0.kind, name: $0.person?.name, cat: $0.person?.cat, yours: $0.yours, person: $0.person?.id)
            },
            turn: room.game?.turn, phase: room.game?.phase ?? [], updatedAt: now)
        save(tables)
    }

    public func remove(code: String) {
        var tables = all()
        if tables.removeValue(forKey: code) != nil { save(tables) }
    }

    public func contains(code: String) -> Bool { all()[code] != nil }

    private func save(_ tables: [String: CachedTable]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(tables) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
