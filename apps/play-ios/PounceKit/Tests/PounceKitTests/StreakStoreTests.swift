import Foundation
import Synchronization
import Testing
@testable import PounceKit

/// A scripted `StreakService`: answers from `list`, records every call.
final class FakeStreaks: StreakService, Sendable {
    let state = Mutex<(list: StreakList, calls: [String], error: APIError?, gate: Bool)>((StreakList(), [], nil, false))

    init(_ list: StreakList = StreakList()) { state.withLock { $0.list = list } }

    var calls: [String] { state.withLock { $0.calls } }
    func set(_ list: StreakList) { state.withLock { $0.list = list } }
    func fail(_ error: APIError?) { state.withLock { $0.error = error } }

    private func record(_ call: String) throws {
        try state.withLock {
            $0.calls.append(call)
            if let error = $0.error { throw error }
        }
    }

    func streaks(person: String?) async throws -> StreakList {
        try record("list")
        return state.withLock { $0.list }
    }
    func pause(pair: String, days: Int, person: String?) async throws { try record("pause \(pair) \(days)") }
    func unpause(pair: String, person: String?) async throws { try record("unpause \(pair)") }
    func openGift(pair: String, gift: String, person: String?) async throws {
        try await Task.sleep(for: .milliseconds(30))
        try record("open \(pair) \(gift)")
        // As the server does: the gift is gone for this person and its item is theirs.
        state.withLock { s in
            guard let i = s.list.pairs.firstIndex(where: { $0.pair == pair }),
                  let g = s.list.pairs[i].gifts.first(where: { $0.id == gift }) else { return }
            s.list.pairs[i].gifts.removeAll { $0.id == gift }
            if g.item.hasPrefix("rug-") { s.list.pairs[i].unlocked.rugs.append(g.item) }
        }
    }
    func pin(pair: String, person: String?) async throws { try record("pin \(pair)") }
    func leave(pair: String, person: String?) async throws { try record("leave \(pair)") }
    func rejoin(pair: String, person: String?) async throws { try record("rejoin \(pair)") }
}

func streakView(
    _ pair: String = "pr_mia", count: Int = 5, me: Bool = false, them: Bool = false, kept: Bool = false,
    partner: StreakView.Partner = .init(name: "Mia", cat: 2), week: [WeekState] = [], myMove: [String] = [],
    theirMove: [String] = [], best: Int? = nil, todayToy: String? = nil, unlocked: StreakView.Unlocks = .init(backs: [], rugs: []),
    gifts: [StreakView.Gift] = []
) -> StreakView {
    StreakView(
        pair: pair, partner: partner, count: count, me: me, them: them, kept: kept, best: best ?? count,
        week: week.enumerated().map { WeekDot(day: "2026-11-0\($0.offset + 1)", state: $0.element) },
        todayToy: todayToy, unlocked: unlocked, gifts: gifts, myMove: myMove, theirMove: theirMove)
}

@MainActor @Suite struct StreakStoreTests {
    private let owner = "6f1c0e0e-0000-4000-8000-000000000001"

    private func store(_ list: StreakList) -> (StreakStore, FakeStreaks) {
        let fake = FakeStreaks(list)
        let store = StreakStore(service: fake)
        store.person = owner
        return (store, fake)
    }

    @Test func refreshLoadsOwnerPairs() async {
        let (store, _) = store(StreakList(pairs: [streakView(count: 9), streakView("pr_sam", count: 2)],
                                          left: [LeftPair(pair: "pr_leo", partner: .init(name: "Leo", cat: 1))]))
        await store.refresh()
        #expect(store.enabled == true)
        #expect(store.pairs.map(\.pair) == ["pr_mia", "pr_sam"])
        #expect(store.top?.count == 9)
        #expect(store.left.map(\.pair) == ["pr_leo"])
    }

    @Test func refreshWithoutAPersonDoesNothing() async {
        let (store, fake) = store(StreakList(pairs: [streakView()]))
        store.person = nil
        await store.refresh()
        #expect(fake.calls.isEmpty)
        #expect(store.enabled == nil)
    }

    @Test func notFoundTurnsStreaksOff() async {
        let (store, fake) = store(StreakList(pairs: [streakView()]))
        await store.refresh()
        fake.fail(.notFound)
        await store.refresh()
        #expect(store.enabled == false)
        #expect(store.pairs.isEmpty && store.left.isEmpty && store.top == nil)
    }

    @Test func noPlayerYetLeavesStreaksUnknown() async {
        let (store, fake) = store(StreakList(pairs: [streakView()]))
        fake.fail(.noPlayer)
        await store.refresh()
        #expect(store.enabled == nil)
        fake.fail(nil)
        await store.refresh()
        #expect(store.enabled == true)
    }

    @Test func offlineKeepsLastList() async {
        let (store, fake) = store(StreakList(pairs: [streakView()]))
        await store.refresh()
        fake.fail(.transport("offline"))
        await store.refresh()
        #expect(store.enabled == true)
        #expect(store.pairs.count == 1)
    }

    @Test func applyUpdatesOwnerPairAndReturnsStamp() async {
        var pinned = streakView(count: 5)
        pinned.pinned = true
        let (store, _) = store(StreakList(pairs: [pinned]))
        await store.refresh()
        let half = store.apply(pair: "pr_mia", person: owner, view: streakView(count: 5, me: true))
        #expect(half == .halfDone)
        #expect(store.top?.me == true)
        #expect(store.top?.pinned == true, "a socket view keeps the list's pin")
        let kept = store.apply(pair: "pr_mia", person: owner,
                               view: streakView(count: 6, me: true, them: true, kept: true, todayToy: "toy-mouse"))
        #expect(kept == .dayKept(toy: "toy-mouse"))
        #expect(store.top?.count == 6)
        #expect(store.apply(pair: "pr_mia", person: owner,
                            view: streakView(count: 6, me: true, them: true, kept: true, todayToy: "toy-mouse")) == nil)
    }

    @Test func applyForAnotherPersonOnThisPhoneKeepsItApart() async {
        let (store, _) = store(StreakList(pairs: [streakView()]))
        await store.refresh()
        let stamp = store.apply(pair: "pr_kid", person: "kid", view: streakView("pr_kid", count: 1, me: true, them: true, kept: true))
        #expect(stamp == .dayKept(toy: nil))
        #expect(store.pairs.map(\.pair) == ["pr_mia"])
        #expect(store.views(for: "kid").map(\.pair) == ["pr_kid"])
        #expect(store.views(for: owner).map(\.pair) == ["pr_mia"])
    }

    @Test func aNewOwnerPairFromTheSocketIsAdded() async {
        let (store, _) = store(StreakList())
        await store.refresh()
        _ = store.apply(pair: "pr_new", person: owner, view: streakView("pr_new", count: 1, me: true, them: true, kept: true))
        #expect(store.pairs.map(\.pair) == ["pr_new"])
    }

    @Test func openGiftOnce() async {
        let gift = StreakView.Gift(id: "g3", milestone: 3, item: "rug-night-sky")
        let (store, fake) = store(StreakList(pairs: [streakView(gifts: [gift])]))
        await store.refresh()
        async let a = store.openGift("pr_mia", "g3")
        async let b = store.openGift("pr_mia", "g3")
        let results = await [a, b]
        #expect(results.filter { $0 }.count == 1)
        #expect(fake.calls.filter { $0.hasPrefix("open") } == ["open pr_mia g3"])
        #expect(store.top?.gifts.isEmpty == true)
        #expect(store.unlocked.rugs.contains("rug-night-sky"), "an opened gift's item is mine at once")
    }

    @Test func pauseRefreshes() async {
        let (store, fake) = store(StreakList(pairs: [streakView()]))
        await store.refresh()
        var paused = streakView()
        paused.pausedUntil = "2026-11-06"
        fake.set(StreakList(pairs: [paused]))
        #expect(await store.pause("pr_mia", days: 3))
        #expect(fake.calls.contains("pause pr_mia 3"))
        #expect(store.top?.pausedUntil == "2026-11-06")
        #expect(await store.pause("pr_mia", days: 15) == false, "1 to 14 days only")
    }

    @Test func leaveMovesPairToLeft() async {
        let (store, fake) = store(StreakList(pairs: [streakView(), streakView("pr_sam", partner: .init(name: "Sam", cat: 6))]))
        await store.refresh()
        fake.set(StreakList(pairs: [streakView("pr_sam", partner: .init(name: "Sam", cat: 6))],
                            left: [LeftPair(pair: "pr_mia", partner: .init(name: "Mia", cat: 2))]))
        #expect(await store.leave("pr_mia"))
        #expect(store.pairs.map(\.pair) == ["pr_sam"])
        #expect(store.left.map(\.pair) == ["pr_mia"])
        fake.set(StreakList(pairs: [streakView("pr_new", count: 0), streakView("pr_sam")]))
        #expect(await store.rejoin("pr_mia"))
        #expect(fake.calls.contains("rejoin pr_mia"))
        #expect(store.left.isEmpty)
    }

    @Test func unlockedUnionsWithDefaults() async {
        let (store, _) = store(StreakList(pairs: [
            streakView(unlocked: .init(backs: ["back-crown"], rugs: [])),
            streakView("pr_sam", unlocked: .init(backs: ["back-yarn-swirl", "back-crown"], rugs: ["rug-fish-pond"])),
        ]))
        await store.refresh()
        #expect(store.unlocked.backs == ["back-violet-paw", "back-yarn-swirl", "back-crown"])
        #expect(store.unlocked.rugs == ["rug-classic", "rug-fish-pond"])
    }

    @Test func completesToday() async {
        let (store, _) = store(StreakList(pairs: [
            streakView(them: true, myMove: ["AAAAA"]),
            streakView("pr_sam", me: true, them: false, myMove: ["BBBBB"]),
        ]))
        await store.refresh()
        #expect(store.completesToday(code: "AAAAA"))
        #expect(!store.completesToday(code: "BBBBB"))
        #expect(!store.completesToday(code: "CCCCC"))
    }
}
