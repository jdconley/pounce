import Foundation
import Observation

/// This phone's notification settings (spec §12.6): only the values someone chose, each with when
/// it was chosen, so the server's band defaults apply to the rest and last writer wins per key.
///
/// A signed-in device carries them in the account's settings ledger (`values(band:)`); a guest
/// device sends what changed itself (`pendingPatch(band:)`, then `sent(_:)`), since the server
/// decides every player's reminders. A kitten's device sends nothing (§14.1).
@MainActor @Observable public final class NotifySettingsStore {
    public private(set) var entries: SyncSection = [:]
    /// Keys a guest device hasn't sent yet.
    @ObservationIgnored private var unsent: Set<String> = []
    @ObservationIgnored private let file: JSONFile<Saved>?

    /// The file's shape.
    public struct Saved: Codable, Sendable {
        var entries: SyncSection
        var unsent: [String]
    }

    /// `notify-settings.json` at `url`, written behind.
    public nonisolated static func file(at url: URL) -> JSONFile<Saved> { JSONFile(url: url) }

    /// `loaded` is what `file.read()` returned, read off the main actor at launch. No file keeps the
    /// settings in memory only.
    public init(file: JSONFile<Saved>?, loaded: Saved? = nil) {
        self.file = file
        if let saved = loaded {
            entries = saved.entries.filter { NotifyKey.all.contains($0.key) }
            unsent = Set(saved.unsent).intersection(entries.keys)
        }
    }

    /// Waits for every save so far to reach the disk.
    public func flush() async { await file?.flush() }

    public func settings(band: AgeBand?) -> NotifySettings {
        NotifySettings.resolve(entries, band: band)
    }

    /// A choice made on this phone, stamped `now` (epoch ms).
    public func set(_ key: String, _ value: JSONValue, now: Int64) {
        guard NotifyKey.all.contains(key) else { return }
        entries[key] = SyncEntry(v: value, at: now)
        unsent.insert(key)
        save()
    }

    /// Values another device wrote: each one newer than this phone's replaces it.
    public func takeRemote(_ section: SyncSection) {
        var changed = false
        for (key, theirs) in section where NotifyKey.all.contains(key) {
            if let mine = entries[key], mine.at >= theirs.at { continue }
            entries[key] = theirs
            unsent.remove(key)
            changed = true
        }
        if changed { save() }
    }

    /// The chosen values for the account's settings ledger; none on a kitten's device (which never
    /// signs in). An unknown band keeps them, so the ledger never reads them as removed.
    public func values(band: AgeBand?) -> [String: JSONValue] {
        guard band != .kitten else { return [:] }
        return entries.mapValues(\.v)
    }

    /// What a guest device still has to send; nil when nothing (or on a kitten's device).
    public func pendingPatch(band: AgeBand?) -> StatePatch? {
        guard PushPolicy.registersRemote(band: band) else { return nil }
        let section = entries.filter { unsent.contains($0.key) }
        return section.isEmpty ? nil : StatePatch(settings: section)
    }

    /// The server took `patch`: those keys are sent unless they changed again meanwhile.
    public func sent(_ patch: StatePatch) {
        for (key, entry) in patch.settings ?? [:] where entries[key] == entry { unsent.remove(key) }
        save()
    }

    private func save() {
        guard let file else { return }
        file.save(Saved(entries: entries, unsent: unsent.sorted()))
    }
}
