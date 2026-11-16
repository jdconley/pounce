import Foundation

/// The tables archived off Home on this phone: `archived.json` (or a per-server `fileName`) in
/// the given directory, room code to the server's `updatedAt` (epoch ms) when it was archived.
/// Archiving only hides a table; the seat, links and pushes keep working. Kept in memory and
/// written behind (`JSONFile`). Not thread-safe by itself; callers use it from one actor (the app
/// model).
public final class TableArchive {
    private let file: JSONFile<[String: Double]>
    private var marks: [String: Double]

    /// `loaded` is what `file.read()` returned, read off the main actor at launch.
    public init(file: JSONFile<[String: Double]>, loaded: [String: Double]?) {
        self.file = file
        marks = loaded ?? [:]
    }

    public static func file(directory: URL, fileName: String = "archived.json") -> JSONFile<[String: Double]> {
        JSONFile(url: directory.appendingPathComponent(fileName), coding: .sorted)
    }

    /// Reads the file (off the caller's actor) and opens the store on it.
    public static func open(directory: URL, fileName: String = "archived.json") async -> sending TableArchive {
        let file = file(directory: directory, fileName: fileName)
        return TableArchive(file: file, loaded: await file.read())
    }

    /// Waits for every save so far to reach the disk.
    public nonisolated(nonsending) func flush() async { await file.flush() }

    /// One server's archive file, `archived.<host>_<port>.json`: room codes belong to a server.
    public static func fileName(for config: APIConfig) -> String {
        "archived.\(config.serverKey.replacingOccurrences(of: ":", with: "_")).json"
    }

    public func all() -> [String: Double] { marks }

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

    private func save(_ next: [String: Double]) {
        marks = next
        file.save(next)
    }
}
