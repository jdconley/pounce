import Foundation

/// Builds and runs `PUT /v1/devices/me/profile` (spec §13.1, §13.4).
public enum ProfileUploader {
    /// The server takes at most this many people.
    public static let maxPeople = 8

    /// The body for this device's people: the owner first, then the others it holds the keys for
    /// (never people imported from the account). Nil without an owner.
    public static func body(
        people: LocalPeople, record: AccountRecord, ownerBand: AgeBand?, timeZone: String, keys: PersonKeyStore
    ) -> ProfileBody? {
        guard let owner = people.owner else { return nil }
        let imported = Set(record.imported)
        let local = [owner] + people.others.filter { !imported.contains($0.id) }
        let sent = local.prefix(maxPeople).map { p in
            ProfilePerson(
                id: p.id, name: p.name, cat: p.cat, key: keys.key(for: p.id),
                // The owner's band goes at profile level; the server gives it to anyone without one.
                ageBand: p.id == owner.id ? nil : record.bands[p.id],
                // A change the device never recorded loses to any recorded one.
                at: record.changedAt[p.id] ?? 1)
        }
        return ProfileBody(timeZone: timeZone, ageBand: ownerBand, people: Array(sent))
    }

    /// One upload: on `rejected` (someone else bound that id first) each rejected person gets a new
    /// id and key, their tips move along, and the profile goes up once more. A second rejection
    /// in the same pass is left for the next one. Returns the ids it replaced, old → new.
    public static func run(
        people: PeopleStore, tutorial: TutorialStore, record: inout AccountRecord, keys: PersonKeyStore,
        ownerBand: AgeBand?, timeZone: String,
        isolation: isolated (any Actor)? = #isolation,
        upload: (ProfileBody) async throws -> ProfileReply
    ) async throws -> [String: String] {
        var renamed: [String: String] = [:]
        for attempt in 0..<2 {
            guard let body = body(
                people: people.load(), record: record, ownerBand: ownerBand, timeZone: timeZone, keys: keys)
            else {
                record.pendingUpload = false
                return renamed
            }
            let reply = try await upload(body)
            record.playerIds.merge(reply.players) { $1 }
            guard !reply.rejected.isEmpty, attempt == 0 else { break }
            for old in reply.rejected {
                let new = UUID().uuidString.lowercased()
                people.replaceID(old, with: new)
                tutorial.moveTips(from: old, to: new)
                keys.remove(old)
                record.rename(old, to: new)
                renamed[old] = new
            }
        }
        record.pendingUpload = false
        return renamed
    }
}
