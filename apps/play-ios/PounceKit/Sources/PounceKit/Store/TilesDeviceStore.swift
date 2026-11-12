import Foundation

/// What the device remembers about one tile game table (tile game spec §5.3, §5.6, §5.7): each
/// local seat's rack order, the draft of a turn left half built, and the rug as last seen.
public struct TilesTableMemory: Codable, Equatable, Sendable {
    /// A draft saved mid-turn. It only comes back for the same seat and the same count of
    /// completed turns, and only when it still matches the rug and rack (`TilesTableModel.draft`).
    public struct SavedDraft: Codable, Equatable, Sendable {
        public var seat: Seat
        public var turns: Int
        public var draft: TilesDraft

        public init(seat: Seat, turns: Int, draft: TilesDraft) {
            self.seat = seat
            self.turns = turns
            self.draft = draft
        }
    }

    public var orders: [Seat: RackOrder] = [:]
    public var draft: SavedDraft?
    /// The rug the last time this phone drew it, for "what changed" after a cold start.
    public var lastTable: [[TileID]]?
    /// Easy mode for this table (tile game spec §5.10); nil follows the age band's default.
    public var easy: Bool?
    /// Easy mode's "tricks" paw: the loupe, splitting and joining are on.
    public var tricks: Bool?

    public init() {}

    /// The saved draft for `seat` on turn `turns`; nil when the turn has moved on.
    public func draft(seat: Seat, turns: Int) -> TilesDraft? {
        guard let draft, draft.seat == seat, draft.turns == turns else { return nil }
        return draft.draft
    }
}

/// `tiles.json` (or a per-server `fileName`) in the given directory, keyed by room code, written
/// atomically. Not thread-safe by itself; callers use it from one actor.
public final class TilesDeviceStore {
    private let fileURL: URL
    private var cache: [String: TilesTableMemory]?
    /// Tables kept at most; the least recently written go first.
    static let limit = 40
    private var recency: [String] = []

    public init(directory: URL, fileName: String = "tiles.json") {
        fileURL = directory.appendingPathComponent(fileName)
    }

    private struct File: Codable {
        var tables: [String: TilesTableMemory]
        var recency: [String]
    }

    public func memory(code: String) -> TilesTableMemory {
        load()[code] ?? TilesTableMemory()
    }

    /// Changes one table's memory and writes the file if anything changed.
    public func update(code: String, _ change: (inout TilesTableMemory) -> Void) {
        var tables = load()
        var memory = tables[code] ?? TilesTableMemory()
        let before = memory
        change(&memory)
        guard memory != before || tables[code] == nil else { return }
        tables[code] = memory
        recency.removeAll { $0 == code }
        recency.append(code)
        while recency.count > Self.limit {
            tables[recency.removeFirst()] = nil
        }
        cache = tables
        save(tables)
    }

    public func remove(code: String) {
        var tables = load()
        guard tables.removeValue(forKey: code) != nil else { return }
        recency.removeAll { $0 == code }
        cache = tables
        save(tables)
    }

    private func load() -> [String: TilesTableMemory] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(File.self, from: data) else {
            cache = [:]
            return [:]
        }
        recency = file.recency.filter { file.tables[$0] != nil }
        recency += file.tables.keys.filter { !recency.contains($0) }.sorted()
        cache = file.tables
        return file.tables
    }

    private func save(_ tables: [String: TilesTableMemory]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(File(tables: tables, recency: recency)) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
