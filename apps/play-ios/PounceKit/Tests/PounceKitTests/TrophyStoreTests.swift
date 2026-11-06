import Foundation
import Synchronization
import Testing
@testable import PounceKit

final class FakeTrophies: TrophyService, Sendable {
    let state = Mutex<(reply: Trophies?, error: APIError?, calls: Int)>((nil, nil, 0))

    func set(_ t: Trophies?, error: APIError? = nil) { state.withLock { $0.reply = t; $0.error = error } }
    var calls: Int { state.withLock { $0.calls } }

    func trophies(person: String?) async throws -> Trophies {
        try state.withLock { s in
            s.calls += 1
            if let error = s.error { throw error }
            return s.reply!
        }
    }
}

@MainActor @Suite struct TrophyStoreTests {
    private let sample = Trophies(
        own: OwnStreak(count: 2, best: 2), records: .init(current: 2, best: 2, longestPair: 5, totalDays: 2, perfectWeeks: 0),
        earned: .init(toys: [], backs: [], rugs: [], condoStage: 0), catalog: [], connections: [])

    @Test func refreshLoadsForThePerson() async {
        let fake = FakeTrophies()
        fake.set(sample)
        let store = TrophyStore(service: fake)
        await store.refresh()
        #expect(fake.calls == 0, "nothing loads without a person")
        store.person = "me"
        await store.refresh()
        #expect(store.enabled == true)
        #expect(store.trophies == sample)
    }

    @Test func notFoundTurnsTheRoomOff() async {
        let fake = FakeTrophies()
        fake.set(nil, error: .notFound)
        let store = TrophyStore(service: fake)
        store.person = "me"
        await store.refresh()
        #expect(store.enabled == false)
        #expect(store.trophies == nil)
    }

    @Test func offlineKeepsWhatWasShown() async {
        let fake = FakeTrophies()
        fake.set(sample)
        let store = TrophyStore(service: fake)
        store.person = "me"
        await store.refresh()
        fake.set(nil, error: .transport("down"))
        await store.refresh()
        #expect(store.trophies == sample)
        store.person = "someone else"
        #expect(store.trophies == nil, "another person's room never shows")
    }

    @Test func demoServiceDerivesFromTheDemoPairs() async throws {
        let t = try await DemoTrophyService().trophies(person: "me")
        #expect(t.connections.count == 3)
        #expect(t.records.longestPair == 128)
        #expect(t.earned.condoStage == 7)
        #expect(!t.earned.toys.isEmpty && !t.catalog.isEmpty)
        #expect(t.catalog.contains { $0.progress < 1 })
        let empty = try await DemoTrophyService(DemoFixtures.emptyStreaks()).trophies(person: "me")
        #expect(empty.connections.isEmpty && empty.earned.condoStage == 0)
    }
}
