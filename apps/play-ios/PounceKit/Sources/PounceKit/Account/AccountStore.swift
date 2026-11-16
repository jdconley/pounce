import Foundation

/// What this device knows about its players and account, per server (player ids belong to one).
public struct AccountRecord: Codable, Equatable, Sendable {
    /// The local person this device is signed in as (the device's account), if any.
    public var accountPersonId: String?
    /// personId → playerId, from the last profile upload.
    public var playerIds: [String: String] = [:]
    /// Sign-in providers linked to the account (`apple`).
    public var providers: [String] = []
    /// Local people with a sign-in of their own: the account, and household people who signed in.
    public var signedIn: Set<String> = []
    /// Household people's age bands, chosen by whoever added them (§14.1). The owner's band lives
    /// in the age record.
    public var bands: [String: AgeBand] = [:]
    /// When each person's name or cat last changed on this device (epoch ms), sent as `at`.
    public var changedAt: [String: Int64] = [:]
    /// Household people listed by another of the account's devices. They are never uploaded from
    /// here (their keys live on that device) and leave on sign-out.
    public var imported: [String] = []
    /// The last value and write time of every synced key on this device, by section name.
    public var ledger: [String: SyncSection] = [:]

    public init() {}

    public var isSignedIn: Bool { accountPersonId != nil }

    /// Moves everything kept under `old` to `new` (a person id the server rejected).
    public mutating func rename(_ old: String, to new: String) {
        if accountPersonId == old { accountPersonId = new }
        playerIds[old] = nil
        if signedIn.remove(old) != nil { signedIn.insert(new) }
        if let band = bands.removeValue(forKey: old) { bands[new] = band }
        if let at = changedAt.removeValue(forKey: old) { changedAt[new] = at }
        imported = imported.map { $0 == old ? new : $0 }
    }

    private enum CodingKeys: String, CodingKey {
        case accountPersonId, playerIds, providers, signedIn, bands, changedAt, imported, ledger
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountPersonId = try c.decodeIfPresent(String.self, forKey: .accountPersonId)
        playerIds = try c.decodeIfPresent([String: String].self, forKey: .playerIds) ?? [:]
        providers = try c.decodeIfPresent([String].self, forKey: .providers) ?? []
        signedIn = try c.decodeIfPresent(Set<String>.self, forKey: .signedIn) ?? []
        bands = try c.decodeIfPresent([String: AgeBand].self, forKey: .bands) ?? [:]
        changedAt = try c.decodeIfPresent([String: Int64].self, forKey: .changedAt) ?? [:]
        imported = try c.decodeIfPresent([String].self, forKey: .imported) ?? []
        ledger = try c.decodeIfPresent([String: SyncSection].self, forKey: .ledger) ?? [:]
    }
}

/// `account.<host>_<port>.json` next to `people.json`, kept in memory and written behind
/// (`JSONFile`), atomically, on every save. Not thread-safe by itself; callers use it from one
/// actor (the app model).
public final class AccountStore {
    private let file: JSONFile<AccountRecord>
    private var record: AccountRecord

    /// `loaded` is what `file.read()` returned, read off the main actor at launch.
    public init(file: JSONFile<AccountRecord>, loaded: AccountRecord?) {
        self.file = file
        record = loaded ?? AccountRecord()
    }

    public static func file(directory: URL, fileName: String = "account.json") -> JSONFile<AccountRecord> {
        JSONFile(url: directory.appendingPathComponent(fileName), coding: .sorted)
    }

    /// Reads the file (off the caller's actor) and opens the store on it.
    public static func open(directory: URL, fileName: String = "account.json") async -> sending AccountStore {
        let file = file(directory: directory, fileName: fileName)
        return AccountStore(file: file, loaded: await file.read())
    }

    /// Waits for every save so far to reach the disk.
    public nonisolated(nonsending) func flush() async { await file.flush() }

    public static func fileName(for config: APIConfig) -> String {
        "account.\(config.serverKey.replacingOccurrences(of: ":", with: "_")).json"
    }

    public func load() -> AccountRecord { record }

    public func save(_ next: AccountRecord) {
        record = next
        file.save(next)
    }
}
