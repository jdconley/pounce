import Foundation

/// The coaching tips each person has seen, by `Person.id`.
public typealias TipsSeen = [String: Set<CoachTip>]

/// The UI tips each person has seen or learned, by `Person.id`.
public typealias UITipsSeen = [String: Set<UITip>]

/// `tutorial.json` in the given directory (next to `people.json`), rewritten atomically on every
/// change. Tips are kept per person, not per phone: pass-and-play puts several people on one.
/// The file is the same shape it always was, person to tip names: the game's tips (`CoachTip`)
/// and the UI tips (`UITip`, "ui." names) share it, and names this build doesn't know (from a
/// newer one) are kept as they are, so nothing anyone has seen is ever lost.
/// Not thread-safe by itself; callers use it from one actor (the app model).
public final class TutorialStore {
    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("tutorial.json")
    }

    /// Every name in the file, known or not.
    public func loadNames() -> [String: Set<String>] {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return raw.mapValues(Set.init)
    }

    /// The game's tips. Other names are left out here (and kept in the file).
    public func load() -> TipsSeen {
        loadNames().mapValues { Set($0.compactMap(CoachTip.init(rawValue:))) }
    }

    /// The UI tips.
    public func loadUI() -> UITipsSeen {
        loadNames().compactMapValues { names in
            let tips = Set(names.compactMap(UITip.init(rawValue:)))
            return tips.isEmpty ? nil : tips
        }
    }

    @discardableResult
    public func markSeen(_ tips: Set<CoachTip>, person: String) -> TipsSeen {
        markSeen(names: Set(tips.map(\.rawValue)), person: person)
        return load()
    }

    @discardableResult
    public func markSeen(_ tips: Set<UITip>, person: String) -> UITipsSeen {
        markSeen(names: Set(tips.map(\.rawValue)), person: person)
        return loadUI()
    }

    public func markSeen(names: Set<String>, person: String) {
        var all = loadNames()
        guard !names.isSubset(of: all[person] ?? []) else { return }
        all[person, default: []].formUnion(names)
        save(all)
    }

    /// Moves one person's tips to a new id (their old id was rejected by the server).
    public func moveTips(from old: String, to new: String) {
        var all = loadNames()
        guard let tips = all.removeValue(forKey: old) else { return }
        all[new, default: []].formUnion(tips)
        save(all)
    }

    /// Replaces the game's tips (sync brought another device's), keeping every other name.
    public func replace(_ all: TipsSeen) {
        var names = loadNames().mapValues { $0.filter { CoachTip(rawValue: $0) == nil } }
        for (person, tips) in all { names[person, default: []].formUnion(tips.map(\.rawValue)) }
        save(names.filter { !$0.value.isEmpty })
    }

    /// Replaces the whole record.
    public func replaceNames(_ all: [String: Set<String>]) {
        save(all.filter { !$0.value.isEmpty })
    }

    /// Everyone sees the tips again.
    public func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save(_ all: [String: Set<String>]) {
        let raw = all.mapValues { $0.sorted() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(raw) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// How often UI tips have shown, for pacing: the app opens on this phone and, per person, how
/// many tips they had today. `tip-pacing.json`, next to `tutorial.json`.
public final class TipPacingStore {
    public struct Record: Codable, Equatable, Sendable {
        public var opens: Int = 0
        /// Per person: the day ("2026-11-12", the phone's calendar) and that day's count.
        public var days: [String: Day] = [:]

        public struct Day: Codable, Equatable, Sendable {
            public var day: String
            public var shown: Int
        }

        public init() {}
    }

    private let fileURL: URL
    private let calendar: Calendar

    public init(directory: URL, calendar: Calendar = .current) {
        fileURL = directory.appendingPathComponent("tip-pacing.json")
        self.calendar = calendar
    }

    public func load() -> Record {
        guard let data = try? Data(contentsOf: fileURL),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return Record() }
        return record
    }

    /// One more app open; returns the count, this one included.
    @discardableResult
    public func opened() -> Int {
        var record = load()
        record.opens += 1
        save(record)
        return record.opens
    }

    /// Tips `person` had on `date`'s day.
    public func shown(person: String, on date: Date) -> Int {
        guard let day = load().days[person], day.day == key(date) else { return 0 }
        return day.shown
    }

    public func noteShown(person: String, on date: Date) {
        var record = load()
        let today = key(date)
        let count = record.days[person].flatMap { $0.day == today ? $0.shown : nil } ?? 0
        record.days[person] = .init(day: today, shown: count + 1)
        save(record)
    }

    /// Today's counts start over (the opens stay: they are about the phone, not the tips).
    public func reset() {
        var record = load()
        record.days = [:]
        save(record)
    }

    private func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func save(_ record: Record) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(record) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
