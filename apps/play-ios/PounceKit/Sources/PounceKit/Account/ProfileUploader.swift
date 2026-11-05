import Foundation

/// Builds and runs `PUT /v1/devices/me/profile` (spec §13.1, §13.4).
public enum ProfileUploader {
    /// The server takes at most this many people.
    public static let maxPeople = 8

    /// The body for this device's people: the owner first, then the others it holds the keys for
    /// and whose age band someone picked (never people imported from the account, nor people
    /// added before ages were asked, until a band is picked for them). Nil without an owner.
    public static func body(
        people: LocalPeople, record: AccountRecord, ownerBand: AgeBand?, timeZone: String, keys: PersonKeyStore
    ) -> ProfileBody? {
        guard let owner = people.owner else { return nil }
        let imported = Set(record.imported)
        let others = people.others.filter { !imported.contains($0.id) && record.bands[$0.id] != nil }
        let sent = ([owner] + others).prefix(maxPeople).map { p in
            ProfilePerson(
                id: p.id, name: p.name, cat: p.cat, key: keys.key(for: p.id),
                // The owner's band goes at profile level; the server gives it to anyone without one.
                ageBand: p.id == owner.id ? nil : record.bands[p.id],
                // A change the device never recorded loses to any recorded one.
                at: record.changedAt[p.id] ?? 1)
        }
        return ProfileBody(timeZone: timeZone, ageBand: ownerBand, people: Array(sent))
    }

    /// One upload. It reads the live record when it builds a body and writes back only what the
    /// server's reply brings (`update`), so anything else that changes the record meanwhile (a
    /// sign-in, a rename, a sync) stands. On `rejected` (someone else bound that id first) each
    /// rejected person gets a new id and key at once, in the stores and the record together,
    /// and the profile goes up once more; a second rejection waits for the next pass. Returns
    /// the ids it replaced, old to new.
    public static func run(
        people: PeopleStore, tutorial: TutorialStore, keys: PersonKeyStore, ownerBand: AgeBand?, timeZone: String,
        record: () -> AccountRecord, update: ((inout AccountRecord) -> Void) -> Void,
        isolation: isolated (any Actor)? = #isolation,
        upload: (ProfileBody) async throws -> ProfileReply
    ) async throws -> [String: String] {
        var renamed: [String: String] = [:]
        for attempt in 0..<2 {
            guard let body = body(
                people: people.load(), record: record(), ownerBand: ownerBand, timeZone: timeZone, keys: keys)
            else { return renamed }
            let reply = try await upload(body)
            update { $0.playerIds.merge(reply.players) { $1 } }
            guard !reply.rejected.isEmpty, attempt == 0 else { break }
            for old in reply.rejected {
                let new = UUID().uuidString.lowercased()
                people.replaceID(old, with: new)
                tutorial.moveTips(from: old, to: new)
                keys.remove(old)
                update { $0.rename(old, to: new) }
                renamed[old] = new
            }
        }
        return renamed
    }
}

/// Whether a profile upload is owed. A change noted while an upload is on the wire keeps it
/// owed, so that change goes up in the next one.
public struct UploadState: Equatable, Sendable {
    public private(set) var pending = true
    private var generation = 0

    public init() {}

    public mutating func noteChange() {
        generation += 1
        pending = true
    }

    /// An upload starts; pass the result to `finished` or `failed`.
    public func begin() -> Int { generation }

    public mutating func finished(_ started: Int) {
        if generation == started { pending = false }
    }

    public mutating func failed(_ started: Int) {
        pending = true
    }
}
