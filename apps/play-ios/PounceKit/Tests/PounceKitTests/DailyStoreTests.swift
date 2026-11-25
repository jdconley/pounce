import Foundation
import Testing

@testable import PounceKit

/// A board route that answers from a script.
private actor ScriptedBoard: DailyService {
    var answers: [Result<DailyBoard, any Error>]
    init(_ answers: [Result<DailyBoard, any Error>]) { self.answers = answers }

    func board(date: String?, person: String?) async throws -> DailyBoard { try answers.removeFirst().get() }
    func stats(person: String?) async throws -> DailyStatsList {
        DailyStatsList(games: ["test": try DailyFixtures.decode(DailyStatsList.self, "http", "stats").games["test"]!])
    }
    func start(game: String, person: String?) async throws -> DailyStart { throw APIError.notFound }
    func moves(run: String, body: DailyMovesBody, person: String?) async throws -> DailyMovesAnswer { throw APIError.notFound }
    func hint(run: String, hints: Int, person: String?) async throws -> DailyMovesAnswer { throw APIError.notFound }
    func giveUp(run: String, person: String?) async throws -> DailyMovesAnswer { throw APIError.notFound }
    func showOnTV(run: String, on: Bool, person: String?) async throws {}
    func linkBoard(_ key: ScreenKey, person: String?) async throws {}
    func unlinkBoard(person: String?) async throws {}
}

/// The server as a brand-new owner meets it: a person is known only once a profile upload named
/// them, and the board refuses anyone else with a 403 (`who` in play-api's daily routes).
private actor NewPlayerServer: DailyService {
    let answer: DailyBoard
    private var known: Set<String> = []
    private(set) var boardCalls = 0
    init(_ answer: DailyBoard) { self.answer = answer }

    func upload(_ body: ProfileBody) -> ProfileReply {
        known.formUnion(body.people.map(\.id))
        return ProfileReply(players: Dictionary(uniqueKeysWithValues: body.people.map { ($0.id, "pr_\($0.id)") }), rejected: [])
    }

    func board(date: String?, person: String?) async throws -> DailyBoard {
        boardCalls += 1
        guard let person, known.contains(person) else { throw APIError.forbidden }
        return answer
    }
    func stats(person: String?) async throws -> DailyStatsList { throw APIError.forbidden }
    func start(game: String, person: String?) async throws -> DailyStart { throw APIError.notFound }
    func moves(run: String, body: DailyMovesBody, person: String?) async throws -> DailyMovesAnswer { throw APIError.notFound }
    func hint(run: String, hints: Int, person: String?) async throws -> DailyMovesAnswer { throw APIError.notFound }
    func giveUp(run: String, person: String?) async throws -> DailyMovesAnswer { throw APIError.notFound }
    func showOnTV(run: String, on: Bool, person: String?) async throws {}
    func linkBoard(_ key: ScreenKey, person: String?) async throws {}
    func unlinkBoard(person: String?) async throws {}
}

@MainActor @Suite struct DailyStoreTests {
    private func board() throws -> DailyBoard { try DailyFixtures.decode(DailyBoard.self, "http", "board") }

    @Test func boardNotFoundHides() async {
        let store = DailyStore(service: ScriptedBoard([.failure(APIError.notFound)]))
        store.person = "p1"
        await store.refresh()
        #expect(store.enabled == false)
        #expect(store.board == nil)
    }

    @Test func aBoardShows() async throws {
        let store = DailyStore(service: ScriptedBoard([.success(try board())]))
        store.person = "p1"
        await store.refresh()
        #expect(store.enabled == true)
        #expect(store.tvs == 1)
        #expect(store.result("test")?.outcome == .solved)
    }

    @Test func offlineKeepsTheBoard() async throws {
        let store = DailyStore(service: ScriptedBoard([.success(try board()), .failure(APIError.transport("offline"))]))
        store.person = "p1"
        await store.refresh()
        await store.refresh()
        #expect(store.enabled == true)
        #expect(store.board != nil)
    }

    @Test func socketMessagesApply() async throws {
        let store = DailyStore(service: ScriptedBoard([.success(try board())]))
        store.person = "p1"
        await store.refresh()
        store.apply(.tvs(0))
        #expect(store.tvs == 0)
        store.apply(.progress(player: "pr_Hn5sW2qLp7Xy3Zc8Vb1MkA", game: "test", progress: 0.9))
        #expect(store.board?.games.first?.rows.last?.playing?.progress == 0.9)
        let done = DailyResult(game: "test", date: "2026-11-23", number: 2, outcome: .solved, timeMs: 1, progress: 1)
        store.apply(.result(player: "pr_Hn5sW2qLp7Xy3Zc8Vb1MkA", result: done))
        #expect(store.board?.games.first?.rows.last?.result == done)
        store.apply(.watch(player: "x", game: "test", puzzle: .null, state: .null))
        #expect(store.tvs == 0)
    }

    @Test func personChangeClears() async throws {
        let store = DailyStore(service: ScriptedBoard([.success(try board())]))
        store.person = "p1"
        await store.refresh()
        await store.refreshStats()
        #expect(store.stats["test"]?.played == 1)
        store.person = "p2"
        #expect(store.board == nil && store.enabled == nil && store.stats.isEmpty)
    }

    /// Onboarding saves the owner and goes Home, whose board call beats the profile upload to the
    /// server: a 403. Once the upload lands the Dish shows, with no trip to the background.
    @Test func aNewOwnersDishShowsOnceTheUploadLands() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pounce-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let people = await PeopleStore.open(directory: dir)
        let tutorial = await TutorialStore.open(directory: dir)
        let server = NewPlayerServer(try board())
        let store = DailyStore(service: server)

        let owner = people.setOwner(name: "Mia", cat: 3)
        store.person = owner.id
        await store.refresh()
        #expect(store.enabled == nil)

        var record = AccountRecord()
        _ = try await ProfileUploader.run(
            people: people, tutorial: tutorial, keys: MemoryPersonKeyStore(), ownerBand: .adult, timeZone: "UTC",
            record: { record }, update: { $0(&record) }
        ) { body in await server.upload(body) }
        await store.profileSaved(owner.id)

        #expect(store.enabled == true)
        #expect(store.board != nil)
    }

    @Test func aSavedProfileLeavesAShownDishAlone() async throws {
        let server = NewPlayerServer(try board())
        let store = DailyStore(service: server)
        _ = await server.upload(ProfileBody(timeZone: "UTC", ageBand: .adult, people: [
            ProfilePerson(id: "p1", name: "Mia", cat: 3, key: "k", ageBand: nil, at: 1),
        ]))
        store.person = "p1"
        await store.refresh()
        await store.profileSaved("p1")
        await store.profileSaved("someone-else")
        #expect(store.enabled == true)
        #expect(await server.boardCalls == 1)
    }
}
