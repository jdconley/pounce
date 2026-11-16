import Foundation
import PounceKit

/// Everything the app model reads from disk and the Keychain to draw its first screen, read in one
/// go off the main actor (docs/main-thread.md: load once, before the first screen). Until it
/// arrives, a few milliseconds, the window shows the launch screen's violet.
struct LaunchData: Sendable {
    var people: Loaded<LocalPeople>
    var cache: Loaded<[String: CachedTable]>
    var archive: Loaded<[String: Double]>
    var list: Loaded<[TableEntry]>
    var invites: Loaded<[String: Double]>
    var tutorial: Loaded<TutorialStore.Saved>
    var pacing: Loaded<TipPacingStore.Record>
    var rating: Loaded<RatingRecord>
    var updates: Loaded<UpdateRecord>
    var funnel: Loaded<Funnel.Saved>
    var pounces: Loaded<[PendingAnswer]>
    var kitten: Loaded<KittenStore.Saved>
    var notify: Loaded<NotifySettingsStore.Saved>
    var condoSeen: Loaded<[String: Int]>
    var account: Loaded<AccountRecord>
    /// The tile game's memory (`TilesMemory`), in its own folder.
    var tiles: Loaded<TilesDeviceStore.File>
    var age: AgeRecord?

    @concurrent
    static func load(directory: URL, config: APIConfig, ageStore: any AgeRecordStore) async -> LaunchData {
        async let people = Loaded.read(PeopleStore.file(directory: directory))
        async let cache = Loaded.read(TableCache.file(directory: directory, fileName: TableCache.fileName(for: config)))
        async let archive = Loaded.read(TableArchive.file(directory: directory, fileName: TableArchive.fileName(for: config)))
        async let list = Loaded.read(TableList.file(directory: directory, fileName: TableList.fileName(for: config)))
        async let invites = Loaded.read(TableInvites.file(directory: directory, fileName: TableInvites.fileName(for: config)))
        async let tutorial = Loaded.read(TutorialStore.file(directory: directory))
        async let pacing = Loaded.read(TipPacingStore.file(directory: directory))
        async let rating = Loaded.read(RatingStore.file(directory: directory))
        async let updates = Loaded.read(UpdateStore.file(directory: directory))
        async let funnel = Loaded.read(Funnel.file(at: directory.appendingPathComponent("funnel-\(config.serverKey).json")))
        async let pounces = Loaded.read(PounceStore.file(at: directory.appendingPathComponent("pounce-answers.json")))
        async let kitten = Loaded.read(KittenStore.file(at: directory.appendingPathComponent("kitten.json")))
        async let notify = Loaded.read(NotifySettingsStore.file(at: directory.appendingPathComponent("notify-settings.json")))
        async let condoSeen = Loaded.read(JSONFile<[String: Int]>(url: directory.appendingPathComponent("streak-seen.json")))
        async let account = Loaded.read(AccountStore.file(directory: directory, fileName: AccountStore.fileName(for: config)))
        async let tiles = Loaded.read(TilesDeviceStore.file(directory: TilesMemory.directory))
        async let age = ageStore.load()
        return await LaunchData(
            people: people, cache: cache, archive: archive, list: list, invites: invites, tutorial: tutorial,
            pacing: pacing, rating: rating, updates: updates, funnel: funnel, pounces: pounces, kitten: kitten,
            notify: notify, condoSeen: condoSeen, account: account, tiles: tiles, age: age)
    }
}
