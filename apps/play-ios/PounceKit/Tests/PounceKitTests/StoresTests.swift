import Foundation
import Testing
@testable import PounceKit

@Suite struct StoresTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pounce-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: PeopleStore

    @Test func peopleStartEmpty() throws {
        let store = PeopleStore(directory: try tempDir())
        #expect(store.load() == LocalPeople(owner: nil, others: []))
    }

    @Test func peopleRoundTripThroughDisk() throws {
        let dir = try tempDir()
        let store = PeopleStore(directory: dir)
        let me = store.setOwner(name: "Mochi", cat: 2)
        let pal = store.add(name: "Biscuit", cat: 5)
        #expect(me.id == me.id.lowercased())
        #expect(UUID(uuidString: me.id) != nil)
        #expect(me.id != pal.id)

        let reloaded = PeopleStore(directory: dir).load()
        #expect(reloaded.owner == me)
        #expect(reloaded.others == [pal])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("people.json").path))
    }

    @Test func setOwnerAgainKeepsTheIdentity() throws {
        let store = PeopleStore(directory: try tempDir())
        let first = store.setOwner(name: "Mochi", cat: 2)
        let second = store.setOwner(name: "Pickle", cat: 4)
        #expect(second.id == first.id)
        #expect(store.load().owner == Person(id: first.id, name: "Pickle", cat: 4))
    }

    @Test func namesAreTrimmedAndClampedTo20() throws {
        let store = PeopleStore(directory: try tempDir())
        let long = store.add(name: String(repeating: "x", count: 30), cat: 0)
        #expect(long.name.count == 20)
        let padded = store.add(name: "   Pickle \n", cat: 1)
        #expect(padded.name == "Pickle")
        let owner = store.setOwner(name: String(repeating: "y", count: 25), cat: 0)
        #expect(owner.name.count == 20)
        var edited = padded
        edited.name = String(repeating: "z", count: 40)
        store.update(edited)
        #expect(store.load().others.first { $0.id == padded.id }?.name.count == 20)
    }

    @Test func emojiNamesClampToTheServersUTF16LimitWithoutSplittingCharacters() throws {
        let store = PeopleStore(directory: try tempDir())
        // Family emoji is one Character but 11 UTF-16 units; two of them are 22 units.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        #expect(family.count == 1)
        let p = store.add(name: String(repeating: family, count: 2), cat: 0)
        #expect(p.name.utf16.count <= 20)
        #expect(p.name == family)  // the second whole Character was dropped, not split
        let many = store.add(name: String(repeating: "\u{1F63A}", count: 20), cat: 0)  // 2 units each
        #expect(many.name.utf16.count == 20)
        #expect(many.name.count == 10)
        let owner = store.setOwner(name: String(repeating: "\u{1F63A}", count: 15), cat: 0)
        #expect(owner.name.utf16.count <= 20)
        var edited = p
        edited.name = String(repeating: "e\u{301}", count: 30)  // 2 units per Character
        store.update(edited)
        let stored = try #require(store.load().others.first { $0.id == p.id })
        #expect(stored.name.utf16.count == 20)
        #expect(stored.name.count == 10)
    }

    @Test func blankNamesBecomeGeneratedNames() throws {
        let store = PeopleStore(directory: try tempDir())
        let added = store.add(name: "  \n\t ", cat: 0)
        #expect(NameGenerator.names.contains(added.name))
        let owner = store.setOwner(name: "", cat: 1)
        #expect(NameGenerator.names.contains(owner.name))
        var edited = added
        edited.name = "   "
        store.update(edited)
        let stored = try #require(store.load().others.first { $0.id == added.id })
        #expect(NameGenerator.names.contains(stored.name))
    }

    @Test func updateAndRemove() throws {
        let store = PeopleStore(directory: try tempDir())
        let a = store.add(name: "A", cat: 0)
        let b = store.add(name: "B", cat: 1)
        store.update(Person(id: a.id, name: "Aa", cat: 3))
        #expect(store.load().others == [Person(id: a.id, name: "Aa", cat: 3), b])
        store.remove(id: a.id)
        #expect(store.load().others == [b])
        store.remove(id: "no-such-id")
        #expect(store.load().others == [b])
        // Updating the owner by id works too.
        let me = store.setOwner(name: "Me", cat: 0)
        store.update(Person(id: me.id, name: "Moi", cat: 6))
        #expect(store.load().owner == Person(id: me.id, name: "Moi", cat: 6))
    }

    @Test func corruptPeopleFileLoadsEmpty() throws {
        let dir = try tempDir()
        try Data("not json".utf8).write(to: dir.appendingPathComponent("people.json"))
        #expect(PeopleStore(directory: dir).load() == LocalPeople(owner: nil, others: []))
    }

    @Test func createsMissingDirectory() throws {
        let dir = try tempDir().appendingPathComponent("nested/deeper", isDirectory: true)
        let store = PeopleStore(directory: dir)
        let p = store.add(name: "Zed", cat: 0)
        #expect(PeopleStore(directory: dir).load().others == [p])
    }

    // MARK: TableCache

    private func fixtureRoom(status: RoomStatus = .playing, game: GameView? = nil) -> RoomView {
        RoomView(
            code: "K7QM4", status: status, youAreHost: true,
            seats: [
                SeatView(kind: .human, person: Person(id: "a", name: "Mochi", cat: 2), yours: true, presence: .awake),
                SeatView(kind: .bot, person: nil, yours: false, presence: nil),
                SeatView(kind: .open), SeatView(kind: .closed),
            ],
            game: game)
    }

    private func fixtureGame() -> GameView {
        GameView(
            round: 1, dealer: 0, turn: 1, step: .draw, status: .playing, deckCount: 40, discardTop: 5,
            discardCount: 1, phase: [0, 2], scores: [0, 10], laid: [nil, nil], handCounts: [10, 10],
            hands: [0: [1, 2, 3]], pendingSkip: [false, false], winners: [])
    }

    @Test func tableCacheStoresReloadsAndRemoves() throws {
        let dir = try tempDir()
        let cache = TableCache(directory: dir)
        #expect(cache.all().isEmpty)
        #expect(!cache.contains(code: "K7QM4"))

        let now = Date(timeIntervalSince1970: 1_700_000_000.5)
        cache.store(fixtureRoom(game: fixtureGame()), now: now)
        #expect(cache.contains(code: "K7QM4"))

        let expected = CachedTable(
            code: "K7QM4", status: .playing,
            seats: [
                CachedSeat(kind: .human, name: "Mochi", cat: 2, yours: true),
                CachedSeat(kind: .bot, name: nil, cat: nil, yours: false),
                CachedSeat(kind: .open, name: nil, cat: nil, yours: false),
                CachedSeat(kind: .closed, name: nil, cat: nil, yours: false),
            ],
            turn: 1, phase: [0, 2], updatedAt: now)
        #expect(cache.all()["K7QM4"] == expected)

        let reloaded = TableCache(directory: dir)
        #expect(reloaded.all() == ["K7QM4": expected])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tables.json").path))

        reloaded.remove(code: "K7QM4")
        #expect(!reloaded.contains(code: "K7QM4"))
        #expect(TableCache(directory: dir).all().isEmpty)
    }

    // I-3: the dev server and production never share a credential or a table cache.
    @Test func serverKeyNamesHostAndPort() {
        func key(_ s: String) -> String { APIConfig(baseURL: URL(string: s)!).serverKey }
        #expect(key("http://localhost:8787") == "localhost:8787")
        #expect(key("https://play.conleychaos.com") == "play.conleychaos.com:443")
        #expect(key("http://example.test") == "example.test:80")
        #expect(key("https://Gin-And-Tonic.tailc8d3c2.ts.net:8443/") == "gin-and-tonic.tailc8d3c2.ts.net:8443")
    }

    @Test func keychainServicePerServer() {
        let dev = KeychainCredentialStore.serviceName(for: APIConfig(baseURL: URL(string: "http://localhost:8787")!))
        let prod = KeychainCredentialStore.serviceName(for: APIConfig(baseURL: URL(string: "https://play.conleychaos.com")!))
        #expect(dev == "com.conleychaos.play.device.localhost:8787")
        #expect(prod == "com.conleychaos.play.device.play.conleychaos.com:443")
        #expect(dev != prod)
    }

    @Test func tableCacheFilePerServer() throws {
        let dir = try tempDir()
        let dev = APIConfig(baseURL: URL(string: "http://localhost:8787")!)
        let prod = APIConfig(baseURL: URL(string: "https://play.conleychaos.com")!)
        #expect(TableCache.fileName(for: dev) == "tables.localhost_8787.json")
        #expect(TableCache.fileName(for: prod) == "tables.play.conleychaos.com_443.json")
        let devCache = TableCache(directory: dir, fileName: TableCache.fileName(for: dev))
        devCache.store(fixtureRoom(game: fixtureGame()))
        #expect(devCache.contains(code: "K7QM4"))
        #expect(!TableCache(directory: dir, fileName: TableCache.fileName(for: prod)).contains(code: "K7QM4"))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tables.localhost_8787.json").path))
    }

    @Test func tableCacheLobbyHasNoTurnOrPhase() throws {
        let cache = TableCache(directory: try tempDir())
        cache.store(fixtureRoom(status: .lobby, game: nil))
        let t = cache.all()["K7QM4"]
        #expect(t?.turn == nil)
        #expect(t?.phase == [])
        #expect(t?.status == .lobby)
    }

    @Test func tableCacheStoreReplacesSameCode() throws {
        let cache = TableCache(directory: try tempDir())
        cache.store(fixtureRoom(status: .lobby))
        cache.store(fixtureRoom(status: .over))
        #expect(cache.all().count == 1)
        #expect(cache.all()["K7QM4"]?.status == .over)
    }

    @Test func corruptTableFileLoadsEmpty() throws {
        let dir = try tempDir()
        try Data("{".utf8).write(to: dir.appendingPathComponent("tables.json"))
        #expect(TableCache(directory: dir).all().isEmpty)
    }

    // MARK: Credentials

    @Test func memoryCredentialStore() {
        let store = MemoryCredentialStore()
        #expect(store.load() == nil)
        let c = DeviceCredential(deviceId: "d", token: "t")
        store.save(c)
        #expect(store.load() == c)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func memoryCredentialStoreIsThreadSafe() async {
        let store = MemoryCredentialStore()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    store.save(DeviceCredential(deviceId: "d\(i)", token: "t\(i)"))
                    _ = store.load()
                    if i % 7 == 0 { store.clear() }
                }
            }
        }
    }

    @Test func credentialCodableShape() throws {
        let c = DeviceCredential(deviceId: "d", token: "t")
        let again = try JSONDecoder().decode(DeviceCredential.self, from: JSONEncoder().encode(c))
        #expect(again == c)
    }
}
