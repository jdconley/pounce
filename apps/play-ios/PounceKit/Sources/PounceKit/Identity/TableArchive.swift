import Foundation

/// The tables archived off Home on this phone: `archived.json` (or a per-server `fileName`) in
/// the given directory, room code to the server's `updatedAt` (epoch ms) when it was archived.
/// Archiving only hides a table; the seat, links and pushes keep working. Not thread-safe by
/// itself; callers use it from one actor (the app model).
public final class TableArchive {
    private let fileURL: URL

    public init(directory: URL, fileName: String = "archived.json") {
        fileURL = directory.appendingPathComponent(fileName)
    }

    /// One server's archive file, `archived.<host>_<port>.json`: room codes belong to a server.
    public static func fileName(for config: APIConfig) -> String {
        "archived.\(config.serverKey.replacingOccurrences(of: ":", with: "_")).json"
    }

    public func all() -> [String: Double] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }

    /// Hides `code`, remembering how fresh the table was (`updatedAt`) so a later turn can bring it back.
    public func archive(code: String, updatedAt: Double) {
        var marks = all()
        marks[code] = updatedAt
        save(marks)
    }

    public func restore(code: String) {
        var marks = all()
        if marks.removeValue(forKey: code) != nil { save(marks) }
    }

    /// Replaces the whole archive (after `HomeTables.keptArchive` pruned it).
    public func replace(with marks: [String: Double]) {
        guard marks != all() else { return }
        save(marks)
    }

    private func save(_ marks: [String: Double]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(marks) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
