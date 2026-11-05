import Foundation

/// The coaching tips each person has seen, by `Person.id`.
public typealias TipsSeen = [String: Set<CoachTip>]

/// `tutorial.json` in the given directory (next to `people.json`), rewritten atomically on every
/// change. Tips are kept per person, not per phone: pass-and-play puts several people on one.
/// Not thread-safe by itself; callers use it from one actor (the app model).
public final class TutorialStore {
    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("tutorial.json")
    }

    /// Unknown tip names (from a newer build) are dropped.
    public func load() -> TipsSeen {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return raw.mapValues { Set($0.compactMap(CoachTip.init(rawValue:))) }
    }

    @discardableResult
    public func markSeen(_ tips: Set<CoachTip>, person: String) -> TipsSeen {
        var all = load()
        guard !tips.isSubset(of: all[person] ?? []) else { return all }
        all[person, default: []].formUnion(tips)
        save(all)
        return all
    }

    /// Moves one person's tips to a new id (their old id was rejected by the server).
    public func moveTips(from old: String, to new: String) {
        var all = load()
        guard let tips = all.removeValue(forKey: old) else { return }
        all[new, default: []].formUnion(tips)
        save(all)
    }

    /// Replaces the whole record (sync brought another device's tips).
    public func replace(_ all: TipsSeen) {
        save(all)
    }

    /// Everyone sees the tips again.
    public func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save(_ all: TipsSeen) {
        let raw = all.mapValues { $0.map(\.rawValue).sorted() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(raw) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
