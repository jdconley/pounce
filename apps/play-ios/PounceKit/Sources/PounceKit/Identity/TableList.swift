import Foundation

/// The server's last answer to `/tables`: `table-list.json` (or a per-server `fileName`) in the
/// given directory. Home draws from it at launch, so someone with tables sees them at once
/// instead of the first-visit game posters until the server answers. The list is kept in memory
/// and written behind (`JSONFile`), so nothing here touches the disk. Not thread-safe by itself;
/// callers use it from one actor (the app model).
public final class TableList {
    private let file: JSONFile<[TableEntry]>
    private var saved: [TableEntry]?

    /// `loaded` is what `file.read()` returned, read off the main actor at launch.
    public init(file: JSONFile<[TableEntry]>, loaded: [TableEntry]?) {
        self.file = file
        saved = loaded
    }

    public static func file(directory: URL, fileName: String = "table-list.json") -> JSONFile<[TableEntry]> {
        JSONFile(url: directory.appendingPathComponent(fileName))
    }

    /// Reads the file (off the caller's actor) and opens the list on it.
    public static func open(directory: URL, fileName: String = "table-list.json") async -> sending TableList {
        let file = file(directory: directory, fileName: fileName)
        return TableList(file: file, loaded: await file.read())
    }

    /// Waits for every save so far to reach the disk.
    public nonisolated(nonsending) func flush() async { await file.flush() }

    /// One server's list, `table-list.<host>_<port>.json`: room codes belong to a server.
    public static func fileName(for config: APIConfig) -> String {
        "table-list.\(config.serverKey.replacingOccurrences(of: ":", with: "_")).json"
    }

    /// The saved list; nil when this phone never saved one (or it can't be read).
    public func load() -> [TableEntry]? { saved }

    public func save(_ entries: [TableEntry]) {
        guard entries != saved else { return }
        saved = entries
        file.save(entries)
    }
}
