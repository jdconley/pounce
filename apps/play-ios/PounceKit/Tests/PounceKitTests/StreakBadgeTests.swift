import Testing
@testable import PounceKit

@Suite struct StreakBadgeTests {
    private func badge(_ view: StreakView?, all: [StreakView]? = nil, signedIn: Bool = true, offers: Bool = true) -> StreakBadge? {
        StreakBadge.make(view, all: all ?? view.map { [$0] } ?? [], signedIn: signedIn, offersSignIn: offers)
    }

    @Test func noPairNoBadge() {
        #expect(badge(nil) == nil)
    }

    @Test func paws() {
        #expect(badge(streakView(count: 4)) == StreakBadge(count: 4, me: false, them: false, kept: false, mode: .normal, offerSignIn: false))
        #expect(badge(streakView(count: 4, me: true))?.me == true)
        #expect(badge(streakView(count: 4, them: true))?.them == true)
        let both = badge(streakView(count: 5, me: true, them: true, kept: true))
        #expect(both?.kept == true && both?.count == 5)
    }

    @Test func winbackPausedNappedAndFresh() {
        var view = streakView(count: 12)
        view.winback = .init(kept: 1)
        #expect(badge(view)?.mode == .winback(kept: 1))
        view.pausedUntil = "2026-11-08"
        #expect(badge(view)?.mode == .paused, "the suitcase wins over everything")
        #expect(badge(streakView(count: 8, week: [.kept, .kept, .kept, .kept, .kept, .nap, .live]))?.mode == .napped)
        #expect(badge(streakView(count: 8, kept: true, week: [.kept, .kept, .kept, .kept, .kept, .nap, .kept]))?.mode == .normal)
        #expect(badge(streakView(count: 0, best: 5))?.mode == .fresh)
        #expect(badge(streakView(count: 0, best: 0))?.mode == .normal)
    }

    @Test func cloudOnlyAtThreeForGuestsWhoMaySignIn() {
        let three = streakView(count: 3)
        #expect(badge(three, signedIn: false)?.offerSignIn == true)
        #expect(badge(three, signedIn: true)?.offerSignIn == false)
        #expect(badge(three, signedIn: false, offers: false)?.offerSignIn == false, "never on a kitten's phone")
        #expect(badge(streakView(count: 2), signedIn: false)?.offerSignIn == false)
        // Any pair that reached 3, even if the top one hasn't.
        #expect(badge(streakView(count: 1), all: [streakView(count: 1), streakView("pr_b", count: 0, best: 4)], signedIn: false)?.offerSignIn == true)
    }
}

@Suite struct StreakStampTests {
    @Test func stamps() {
        #expect(StreakStamp.diff(old: nil, new: streakView(count: 1, me: true, them: true, kept: true, todayToy: "toy-fish")) == .dayKept(toy: "toy-fish"))
        #expect(StreakStamp.diff(old: streakView(), new: streakView(me: true)) == .halfDone)
        #expect(StreakStamp.diff(old: nil, new: streakView(me: true)) == .halfDone)
        #expect(StreakStamp.diff(old: streakView(me: true), new: streakView(me: true)) == nil)
        #expect(StreakStamp.diff(old: streakView(), new: streakView(them: true)) == nil, "only my own paw stamps")
        #expect(StreakStamp.diff(old: streakView(kept: true), new: streakView(kept: true)) == nil)
    }
}
