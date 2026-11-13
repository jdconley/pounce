import Foundation

/// When this phone last sent each table's invite (the share sheet went out, or the QR code was
/// shown): `invites.json` (or a per-server `fileName`), room code to epoch ms. A table you sit at
/// alone shows on Home only for a while after its invite went out (`HomeTables.isWaitingAlone`).
/// Not thread-safe by itself; callers use it from one actor (the app model).
public final class TableInvites {
    private let fileURL: URL

    public init(directory: URL, fileName: String = "invites.json") {
        fileURL = directory.appendingPathComponent(fileName)
    }

    /// One server's file, `invites.<host>_<port>.json`: room codes belong to a server.
    public static func fileName(for config: APIConfig) -> String {
        "invites.\(config.serverKey.replacingOccurrences(of: ":", with: "_")).json"
    }

    public func all() -> [String: Double] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }

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

    private func save(_ marks: [String: Double]) {
        guard let data = try? JSONEncoder().encode(marks) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
