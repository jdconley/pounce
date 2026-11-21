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
    func hint(run: String, person: String?) async throws -> DailyMovesAnswer { throw APIError.notFound }
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
        let done = DailyResult(game: "test", date: "2026-11-23", number: -26336, outcome: .solved, timeMs: 1, progress: 1)
        store.apply(.result(player: "pr_Hn5sW2qLp7Xy3Zc8Vb1MkA", result: done))
        #expect(store.board?.games.first?.rows.last?.result == done)
        store.apply(.watch(player: "x", game: "test", state: .null))
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
}
