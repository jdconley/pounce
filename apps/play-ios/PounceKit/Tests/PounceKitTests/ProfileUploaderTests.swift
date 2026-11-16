import Foundation
import Synchronization
import Testing
@testable import PounceKit

@Suite struct PersonKeysTests {
    @Test func testKeyIs43Base64URLAndStable() async {
        let keys = MemoryPersonKeyStore()
        let a = await keys.key(for: "p1")
        #expect(a.count == 43)
        #expect(a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(await keys.key(for: "p1") == a)
        #expect(await keys.key(for: "p2") != a)
        await keys.remove("p1")
        #expect(await keys.key(for: "p1") != a)
    }

    @Test func testRandomKeysDiffer() {
        #expect(PersonKeys.random() != PersonKeys.random())
    }

    @Test func testKeychainRoundTripWhereAvailable() async throws {
        let keys = KeychainPersonKeyStore(service: "com.conleychaos.play.person.tests-\(UUID().uuidString)")
        let a = await keys.key(for: "p1")
        guard await KeychainPersonKeyStore.isUsable(keys) else {
            try Test.cancel("data-protection keychain unavailable to this test host (unsigned, no entitlements)")
        }
        #expect(await keys.key(for: "p1") == a)
        await keys.remove("p1")
        #expect(await keys.key(for: "p1") != a)
        await keys.remove("p1")
    }
}

@Suite struct ProfileUploaderTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pounce-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func testBodyLeavesOutImported() async throws {
        let owner = Person(id: "o", name: "JD", cat: 4)
        let kid = Person(id: "k", name: "Sam", cat: 1)
        let fromIPhone = Person(id: "i", name: "Mia", cat: 2)
        var record = AccountRecord()
        record.imported = ["i"]
        record.bands = ["k": .teen]
        let body = try #require(await ProfileUploader.body(
            people: LocalPeople(owner: owner, others: [kid, fromIPhone]), record: record, ownerBand: .adult,
            timeZone: "Europe/Paris", keys: MemoryPersonKeyStore()))
        #expect(body.people.map(\.id) == ["o", "k"])
        #expect(body.timeZone == "Europe/Paris")
    }

    @Test func testBodyCarriesBandsAndAt() async throws {
        let keys = MemoryPersonKeyStore()
        var record = AccountRecord()
        record.bands = ["k": .kitten]
        record.changedAt = ["o": 500]
        let body = try #require(await ProfileUploader.body(
            people: LocalPeople(owner: Person(id: "o", name: "JD", cat: 4), others: [Person(id: "k", name: "Mochi", cat: 1)]),
            record: record, ownerBand: .teen, timeZone: "UTC", keys: keys))
        #expect(body.ageBand == .teen)
        let ownerKey = await keys.key(for: "o")
        #expect(body.people[0] == ProfilePerson(id: "o", name: "JD", cat: 4, key: ownerKey, ageBand: nil, at: 500))
        #expect(body.people[1].ageBand == .kitten)
        #expect(body.people[1].at == 1)
    }

    @Test func testNoOwnerNoBody() async {
        #expect(await ProfileUploader.body(
            people: LocalPeople(), record: AccountRecord(), ownerBand: .adult, timeZone: "UTC",
            keys: MemoryPersonKeyStore()) == nil)
    }

    @Test func testBodyLeavesOutPeopleWithoutABand() async throws {
        // Added before ages were asked: nobody has said how old they are yet (§14.1).
        let body = try #require(await ProfileUploader.body(
            people: LocalPeople(owner: Person(id: "o", name: "JD", cat: 4), others: [Person(id: "old", name: "Ella", cat: 1)]),
            record: AccountRecord(), ownerBand: .adult, timeZone: "UTC", keys: MemoryPersonKeyStore()))
        #expect(body.people.map(\.id) == ["o"])
    }

    @Test func testBodyCapsAtEightPeople() async throws {
        let others = (0..<12).map { Person(id: "p\($0)", name: "P\($0)", cat: $0 % 8) }
        var record = AccountRecord()
        for p in others { record.bands[p.id] = .adult }
        let body = try #require(await ProfileUploader.body(
            people: LocalPeople(owner: Person(id: "o", name: "JD", cat: 4), others: others),
            record: record, ownerBand: .adult, timeZone: "UTC", keys: MemoryPersonKeyStore()))
        #expect(body.people.count == 8)
        #expect(body.people.first?.id == "o")
    }

    @MainActor @Test func testRejectedMintsNewIdOnce() async throws {
        let dir = try tempDir()
        let people = await PeopleStore.open(directory: dir)
        let owner = people.setOwner(name: "JD", cat: 4)
        let tutorial = await TutorialStore.open(directory: dir)
        tutorial.markSeen([.goal, .draw], person: owner.id)
        let keys = MemoryPersonKeyStore()
        let oldKey = await keys.key(for: owner.id)
        var record = AccountRecord()
        record.changedAt = [owner.id: 77]
        let calls = Mutex(0)

        let renamed = try await ProfileUploader.run(
            people: people, tutorial: tutorial, keys: keys, ownerBand: .adult, timeZone: "UTC",
            record: { record }, update: { $0(&record) }
        ) { body in
            calls.withLock { $0 += 1 }
            // Every id is "taken", every time: the pass must stop after one re-mint.
            return ProfileReply(players: [:], rejected: body.people.map(\.id))
        }

        #expect(calls.withLock { $0 } == 2)
        let newOwner = try #require(people.load().owner)
        #expect(newOwner.id != owner.id)
        #expect(UUID(uuidString: newOwner.id) != nil)
        #expect(newOwner.name == "JD")
        #expect(renamed == [owner.id: newOwner.id])
        #expect(tutorial.load()[newOwner.id] == [.goal, .draw])
        #expect(tutorial.load()[owner.id] == nil)
        #expect(await keys.key(for: newOwner.id) != oldKey)
        #expect(record.changedAt[newOwner.id] == 77)
        #expect(record.changedAt[owner.id] == nil)
    }

    @MainActor @Test func testAcceptedRecordsPlayersAndClearsPending() async throws {
        let dir = try tempDir()
        let people = await PeopleStore.open(directory: dir)
        let owner = people.setOwner(name: "JD", cat: 4)
        var record = AccountRecord()
        let tutorial = await TutorialStore.open(directory: dir)
        _ = try await ProfileUploader.run(
            people: people, tutorial: tutorial, keys: MemoryPersonKeyStore(),
            ownerBand: .adult, timeZone: "UTC", record: { record }, update: { $0(&record) }
        ) { _ in ProfileReply(players: [owner.id: "p_X"], rejected: []) }
        #expect(record.playerIds == [owner.id: "p_X"])
    }

    @MainActor @Test func testChangesMadeDuringTheUploadSurvive() async throws {
        let dir = try tempDir()
        let people = await PeopleStore.open(directory: dir)
        let owner = people.setOwner(name: "JD", cat: 4)
        var record = AccountRecord()
        let tutorial = await TutorialStore.open(directory: dir)
        _ = try await ProfileUploader.run(
            people: people, tutorial: tutorial, keys: MemoryPersonKeyStore(),
            ownerBand: .adult, timeZone: "UTC", record: { record }, update: { $0(&record) }
        ) { _ in
            // Sign-in finished and a rename was noted while this was on the wire.
            record.accountPersonId = owner.id
            record.changedAt[owner.id] = 999
            return ProfileReply(players: [owner.id: "p_X"], rejected: [])
        }
        #expect(record.accountPersonId == owner.id)
        #expect(record.changedAt[owner.id] == 999)
        #expect(record.playerIds == [owner.id: "p_X"])
    }

    @MainActor @Test func testRenameSurvivesAFailedRetry() async throws {
        let dir = try tempDir()
        let people = await PeopleStore.open(directory: dir)
        let owner = people.setOwner(name: "JD", cat: 4)
        var record = AccountRecord()
        record.accountPersonId = owner.id
        let calls = Mutex(0)
        let tutorial = await TutorialStore.open(directory: dir)
        await #expect(throws: APIError.transport("offline")) {
            _ = try await ProfileUploader.run(
                people: people, tutorial: tutorial, keys: MemoryPersonKeyStore(),
                ownerBand: .adult, timeZone: "UTC", record: { record }, update: { $0(&record) }
            ) { body in
                let n = calls.withLock { $0 += 1; return $0 }
                if n == 1 { return ProfileReply(players: [:], rejected: body.people.map(\.id)) }
                throw APIError.transport("offline")
            }
        }
        let newOwner = try #require(people.load().owner)
        #expect(newOwner.id != owner.id)
        #expect(record.accountPersonId == newOwner.id, "the record must follow the stores' new id")
    }

    @Test func testAChangeDuringAnUploadKeepsItOwed() {
        var sync = UploadState()
        sync.noteChange()
        let started = sync.begin()
        sync.noteChange()
        sync.finished(started)
        #expect(sync.pending)
        let again = sync.begin()
        sync.finished(again)
        #expect(!sync.pending)
    }

    @MainActor @Test func testFailureLeavesUploadPending() async throws {
        let dir = try tempDir()
        let people = await PeopleStore.open(directory: dir)
        people.setOwner(name: "JD", cat: 4)
        var record = AccountRecord()
        var sync = UploadState()
        sync.noteChange()
        let started = sync.begin()
        let tutorial = await TutorialStore.open(directory: dir)
        await #expect(throws: APIError.transport("offline")) {
            _ = try await ProfileUploader.run(
                people: people, tutorial: tutorial, keys: MemoryPersonKeyStore(),
                ownerBand: .adult, timeZone: "UTC", record: { record }, update: { $0(&record) }
            ) { _ in throw APIError.transport("offline") }
        }
        sync.failed(started)
        #expect(sync.pending)
    }

    @Test func testAccountStoreRoundTrips() async throws {
        let dir = try tempDir()
        let store = await AccountStore.open(directory: dir, fileName: "account.test.json")
        #expect(store.load() == AccountRecord())
        var record = AccountRecord()
        record.accountPersonId = "o"
        record.providers = ["apple"]
        record.ledger = ["settings": ["soundOn": SyncEntry(v: .bool(false), at: 3)]]
        store.save(record)
        await store.flush()
        #expect(await AccountStore.open(directory: dir, fileName: "account.test.json").load() == record)
        #expect(AccountStore.fileName(for: APIConfig(baseURL: URL(string: "http://localhost:8787")!)) == "account.localhost_8787.json")
    }

    @Test func testReplaceIDKeepsNameAndPlace() async throws {
        let store = try await PeopleStore.open(directory: tempDir())
        let owner = store.setOwner(name: "JD", cat: 4)
        let kid = store.add(name: "Sam", cat: 1)
        store.replaceID(kid.id, with: "new-kid")
        store.replaceID(owner.id, with: "new-owner")
        #expect(store.load() == LocalPeople(
            owner: Person(id: "new-owner", name: "JD", cat: 4), others: [Person(id: "new-kid", name: "Sam", cat: 1)]))
    }

    @Test func testUpsertOtherAddsThenUpdatesInPlace() async throws {
        let store = try await PeopleStore.open(directory: tempDir())
        store.setOwner(name: "JD", cat: 4)
        let kid = store.add(name: "Sam", cat: 1)
        store.upsertOther(Person(id: "i", name: "Mia", cat: 2))
        store.upsertOther(Person(id: "i", name: "Mochi", cat: 3))
        #expect(store.load().others == [kid, Person(id: "i", name: "Mochi", cat: 3)])
    }
}
