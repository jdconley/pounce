import Foundation

/// How a phone at a TV table shows its own game: the cards in hand ("Cards") or the whole table
/// ("Table").
public enum TableView: String, Codable, Equatable, Sendable {
    case cards, table
}

/// The Cards/Table choice per table, keyed by room code, kept for the newest 30 tables. A table
/// with no choice shows Cards. `tableviews.json` in the given directory, kept in memory and written
/// behind (`JSONFile`). Not thread-safe by itself; callers use it from one actor.
public final class TableViews {
    private let file: JSONFile<File>
    private var views: [String: TableView]
    /// Oldest first.
    private var recency: [String]
    /// Tables kept at most; the least recently set go first.
    static let limit = 30

    public struct File: Codable, Sendable {
        var views: [String: TableView]
        var recency: [String]
    }

    /// `loaded` is what `file.read()` returned, read off the main actor.
    public init(file: JSONFile<File>, loaded: File?) {
        self.file = file
        let loaded = loaded ?? File(views: [:], recency: [])
        views = loaded.views
        recency = loaded.recency.filter { loaded.views[$0] != nil }
        recency += loaded.views.keys.filter { !recency.contains($0) }.sorted()
    }

    public static func file(directory: URL, fileName: String = "tableviews.json") -> JSONFile<File> {
        JSONFile(url: directory.appendingPathComponent(fileName), coding: .sorted)
    }

    /// Reads the file (off the caller's actor) and opens the store on it.
    public static func open(directory: URL, fileName: String = "tableviews.json") async -> sending TableViews {
        let file = file(directory: directory, fileName: fileName)
        return TableViews(file: file, loaded: await file.read())
    }

    /// Waits for every save so far to reach the disk.
    public nonisolated(nonsending) func flush() async { await file.flush() }

    /// The table's choice; Cards when it has none.
    public func view(code: String) -> TableView { views[code] ?? .cards }

    /// Sets the table's choice, and writes the file if anything changed.
    public func set(_ view: TableView, code: String) {
        guard views[code] != view else { return }
        views[code] = view
        recency.removeAll { $0 == code }
        recency.append(code)
        while recency.count > Self.limit {
            views[recency.removeFirst()] = nil
        }
        file.save(File(views: views, recency: recency))
    }
}
