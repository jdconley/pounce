import Foundation
import Testing
@testable import PounceKit

/// The final review's Important findings, each pinned by a test that failed first.
@MainActor @Suite struct ReviewFixTests {
    private let owner = "6f1c0e0e-0000-4000-8000-000000000001"

    private func room() -> RoomView {
        RoomView(code: "BCDFG", status: .over, youAreHost: true, seats: [], look: .standard)
    }

    // 1. Play again never sticks on "waiting": a send that never left, or a deal that failed,
    // lets it be asked again after the wait.
    @Test func playAgainCanBeAskedAgainAfterTheWait() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var again = PlayAgain()
        #expect(again.tap(room: room(), rematch: nil, now: t0) == .send)
        #expect(again.isWaiting(now: t0.addingTimeInterval(5)))
        #expect(again.tap(room: room(), rematch: nil, now: t0.addingTimeInterval(5)) == .none)
        #expect(!again.isWaiting(now: t0.addingTimeInterval(PlayAgain.wait + 1)))
        #expect(again.tap(room: room(), rematch: nil, now: t0.addingTimeInterval(PlayAgain.wait + 1)) == .send)
    }

    // 2. The look tray offers the seated people's unlocks, not the owner's when the owner isn't seated.
    @Test func unlocksAreTheSeatedPeoples() async {
        let fake = FakeStreaks(StreakList(pairs: [streakView(unlocked: .init(backs: ["back-crown"], rugs: ["rug-night-sky"]))]))
        let store = StreakStore(service: fake)
        store.person = owner
        await store.refresh()
        _ = store.apply(pair: "pr_kid", person: "kid", view: streakView("pr_kid", count: 2, unlocked: .init(backs: ["back-heart-paws"], rugs: [])))
        #expect(store.unlocked(for: ["kid"]) == .init(backs: ["back-violet-paw", "back-heart-paws"], rugs: ["rug-classic"]))
        #expect(store.unlocked(for: ["nobody"]) == .init(backs: ["back-violet-paw"], rugs: ["rug-classic"]))
        #expect(store.unlocked(for: [owner, "kid"]).backs == ["back-violet-paw", "back-crown", "back-heart-paws"])
    }

    // 3a. Someone else on this phone first heard after a launch: an already-kept long streak isn't a
    // new stamp; a brand-new pair's first day is.
    @Test func firstHeardViewOfAnOldStreakDoesNotStamp() async {
        let store = StreakStore(service: FakeStreaks())
        store.person = owner
        await store.refresh()
        #expect(store.apply(pair: "pr_kid", person: "kid", view: streakView("pr_kid", count: 40, me: true, them: true, kept: true)) == nil)
        #expect(store.apply(pair: "pr_new", person: "kid", view: streakView("pr_new", count: 1, me: true, them: true, kept: true)) == .dayKept(toy: nil))
    }

    // 3b. A stamp plays only on the badge of the pair and person it is for.
    @Test func stampIsBoundToItsPairAndPerson() {
        let stamp = TableStamp(pair: "pr_mia", person: "jd", kind: .halfDone, serial: 2, at: .now)
        #expect(stamp.plays(on: "pr_mia", person: "jd"))
        #expect(!stamp.plays(on: "pr_sam", person: "jd"), "another pair's kept day")
        #expect(!stamp.plays(on: "pr_mia", person: "mia"), "the same pair heard for the other person on this phone")
    }

    // 3c/4. Both people of a same-phone pair hear the kept day back to back (before a render): the
    // first one's stamp must not be lost to the second's.
    @Test func stampsAreKeptPerPairAndPerson() {
        var stamps = TableStamps()
        stamps.add(pair: "pr_x", person: "jd", kind: .dayKept(toy: nil), at: .now)
        stamps.add(pair: "pr_x", person: "kid", kind: .dayKept(toy: nil), at: .now)
        #expect(stamps.latest(pair: "pr_x", person: "jd")?.serial == 1)
        #expect(stamps.latest(pair: "pr_x", person: "kid")?.serial == 2)
        #expect(stamps.latest(pair: "pr_y", person: "jd") == nil)
        stamps.add(pair: "pr_x", person: "jd", kind: .halfDone, at: .now)
        #expect(stamps.latest(pair: "pr_x", person: "jd")?.serial == 3)
        #expect(stamps.latest(pair: "pr_x", person: "jd")?.kind == .halfDone)
    }

    // 4. A badge that appears with the message that made it still plays a fresh stamp.
    @Test func freshStampPlaysOnAppear() {
        let at = Date(timeIntervalSince1970: 1000)
        let stamp = TableStamp(pair: "p", person: "q", kind: .dayKept(toy: nil), serial: 1, at: at)
        #expect(stamp.isFresh(now: at.addingTimeInterval(0.5)))
        #expect(!stamp.isFresh(now: at.addingTimeInterval(TableStamp.freshFor + 0.1)))
    }

    // 6. Signing out or deleting resets what the store shows.
    @Test func resetForgetsEverything() async {
        let store = StreakStore(service: FakeStreaks(StreakList(pairs: [streakView()], left: [LeftPair(pair: "x", partner: .init(name: "Leo", cat: 1))])))
        store.person = owner
        await store.refresh()
        _ = store.apply(pair: "pr_kid", person: "kid", view: streakView("pr_kid"))
        store.reset()
        #expect(store.pairs.isEmpty && store.left.isEmpty && store.enabled == nil)
        #expect(store.views(for: "kid").isEmpty)
    }

    // 5. Home's gift: the first waiting gift of any pair.
    @Test func firstWaitingGift() async {
        let gift = StreakView.Gift(id: "g9", milestone: 7, item: "rug-night-sky")
        let store = StreakStore(service: FakeStreaks(StreakList(pairs: [streakView(), streakView("pr_sam", gifts: [gift])])))
        store.person = owner
        await store.refresh()
        #expect(store.waitingGift?.pair == "pr_sam")
        #expect(store.waitingGift?.gift == gift)
    }
}
