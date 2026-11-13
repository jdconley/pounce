import Foundation

/// The server's last answer to `/tables`: `table-list.json` (or a per-server `fileName`) in the
/// given directory. Home draws from it at launch, so someone with tables sees them at once
/// instead of the first-visit game posters until the server answers. Not thread-safe by itself;
/// callers use it from one actor (the app model).
public final class TableList {
    private let fileURL: URL

    public init(directory: URL, fileName: String = "table-list.json") {
        fileURL = directory.appendingPathComponent(fileName)
    }

    /// One server's list, `table-list.<host>_<port>.json`: room codes belong to a server.
    public static func fileName(for config: APIConfig) -> String {
        "table-list.\(config.serverKey.replacingOccurrences(of: ":", with: "_")).json"
    }

    /// The saved list; nil when this phone never saved one (or it can't be read).
    public func load() -> [TableEntry]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([TableEntry].self, from: data)
    }

    public func save(_ entries: [TableEntry]) {
        guard entries != load() else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
