import Foundation

/// What update awareness keeps on this device: the server's last word on what is current, the
/// soft card's memory, and the tables waiting behind an update.
public struct UpdateRecord: Codable, Equatable, Sendable {
    public var status: AppStatus?
    public var fetchedAt: Date?
    public var soft: SoftPromptState
    public var locked: [LockedInvite]

    public init(status: AppStatus? = nil, fetchedAt: Date? = nil, soft: SoftPromptState = SoftPromptState(), locked: [LockedInvite] = []) {
        self.status = status
        self.fetchedAt = fetchedAt
        self.soft = soft
        self.locked = locked
    }

    private enum CodingKeys: String, CodingKey { case status, fetchedAt, soft, locked }

    /// Each part is read on its own: one that a newer or older build wrote differently is empty,
    /// and the rest is kept.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? c.decodeIfPresent(AppStatus.self, forKey: .status)) ?? nil
        fetchedAt = (try? c.decodeIfPresent(Date.self, forKey: .fetchedAt)) ?? nil
        soft = ((try? c.decodeIfPresent(SoftPromptState.self, forKey: .soft)) ?? nil) ?? SoftPromptState()
        locked = ((try? c.decodeIfPresent([LockedInvite].self, forKey: .locked)) ?? nil) ?? []
    }
}

/// `updates.json` in the given directory (next to `people.json`), kept in memory and written
/// behind (`JSONFile`), atomically, on every change. Not thread-safe by itself; callers use it from
/// one actor (the app's update model).
public final class UpdateStore {
    private let file: JSONFile<UpdateRecord>
    private var record: UpdateRecord

    /// `loaded` is what `file.read()` returned, read off the main actor at launch.
    public init(file: JSONFile<UpdateRecord>, loaded: UpdateRecord?) {
        self.file = file
        record = loaded ?? UpdateRecord()
    }

    public static func file(directory: URL) -> JSONFile<UpdateRecord> {
        JSONFile(url: directory.appendingPathComponent("updates.json"), coding: .sorted)
    }

    /// Reads the file (off the caller's actor) and opens the store on it.
    public static func open(directory: URL) async -> sending UpdateStore {
        let file = file(directory: directory)
        return UpdateStore(file: file, loaded: await file.read())
    }

    /// Waits for every save so far to reach the disk.
    public nonisolated(nonsending) func flush() async { await file.flush() }

    public func load() -> UpdateRecord { record }

    public func save(_ next: UpdateRecord) {
        record = next
        file.save(next)
    }

    /// Changes the record and writes it down; returns what it is now.
    @discardableResult
    public func update(_ change: (inout UpdateRecord) -> Void) -> UpdateRecord {
        var record = load()
        let before = record
        change(&record)
        if record != before { save(record) }
        return record
    }
}
