import Foundation

/// When this phone last sent each table's invite (the share sheet went out, or the QR code was
/// shown): `invites.json` (or a per-server `fileName`), room code to epoch ms. A table you sit at
/// alone shows on Home only for a while after its invite went out (`HomeTables.isWaitingAlone`).
/// Kept in memory and written behind (`JSONFile`). Not thread-safe by itself; callers use it from
/// one actor (the app model).
public final class TableInvites {
    private let file: JSONFile<[String: Double]>
    private var marks: [String: Double]

    /// `loaded` is what `file.read()` returned, read off the main actor at launch.
    public init(file: JSONFile<[String: Double]>, loaded: [String: Double]?) {
        self.file = file
        marks = loaded ?? [:]
    }

    public static func file(directory: URL, fileName: String = "invites.json") -> JSONFile<[String: Double]> {
        JSONFile(url: directory.appendingPathComponent(fileName))
    }

    /// Reads the file (off the caller's actor) and opens the store on it.
    public static func open(directory: URL, fileName: String = "invites.json") async -> sending TableInvites {
        let file = file(directory: directory, fileName: fileName)
        return TableInvites(file: file, loaded: await file.read())
    }

    /// Waits for every save so far to reach the disk.
    public nonisolated(nonsending) func flush() async { await file.flush() }

    /// One server's file, `invites.<host>_<port>.json`: room codes belong to a server.
    public static func fileName(for config: APIConfig) -> String {
        "invites.\(config.serverKey.replacingOccurrences(of: ":", with: "_")).json"
    }

    public func all() -> [String: Double] { marks }

    public func note(code: String, now: Date = .now) {
        var marks = all()
        marks[code] = now.timeIntervalSince1970 * 1000
        save(marks)
    }

    /// Keeps only the codes the server still lists.
    public func keep(_ codes: Set<String>) {
        let marks = all()
        let kept = marks.filter { codes.contains($0.key) }
        if kept != marks { save(kept) }
    }

    private func save(_ next: [String: Double]) {
        marks = next
        file.save(next)
    }
}
