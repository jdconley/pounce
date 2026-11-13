import Testing
@testable import PounceKit

/// Home's streak strip (trophy room design §1): your own streak, then each connection in
/// top-pair order. Invite lives in the dock.
@Suite struct StreakStripTests {
    private let own = OwnStreak(count: 12, best: 12)

    @Test func ownThenPairsInOrder() {
        let pairs = [streakView("pr_mia", count: 128), streakView("pr_kiki", count: 9), streakView("pr_nova", count: 41)]
        let chips = StreakStrip.chips(own: own, pairs: pairs)
        #expect(chips == [.own(own), .pair(pairs[0]), .pair(pairs[1]), .pair(pairs[2])])
    }

    @Test func noConnectionsLeavesYourOwnStreak() {
        #expect(StreakStrip.chips(own: own, pairs: []) == [.own(own)])
    }

    @Test func withoutTheOwnStreakJustThePairs() {
        let mia = streakView("pr_mia")
        #expect(StreakStrip.chips(own: nil, pairs: [mia]) == [.pair(mia)])
        #expect(StreakStrip.chips(own: nil, pairs: []).isEmpty)
    }

    @Test func inviteBouncesUntilSomeoneIsConnectedExceptForATeen() {
        #expect(StreakStrip.inviteBounces(connected: false, band: .adult))
        #expect(StreakStrip.inviteBounces(connected: false, band: .kitten))
        #expect(!StreakStrip.inviteBounces(connected: false, band: .teen))
        #expect(!StreakStrip.inviteBounces(connected: true, band: .adult))
    }

    @Test func ownModeUsesThePairMarks() {
        #expect(StreakStrip.mode(OwnStreak(count: 3, best: 3)) == .normal)
        #expect(StreakStrip.mode(OwnStreak(count: 3, best: 3, winback: .init(kept: 1))) == .winback(kept: 1))
        #expect(StreakStrip.mode(OwnStreak(count: 0, best: 9)) == .fresh)
        let napped = OwnStreak(count: 8, best: 8, week: [WeekDot(day: "a", state: .nap), WeekDot(day: "b", state: .live)])
        #expect(StreakStrip.mode(napped) == .napped)
        var kept = napped
        kept.kept = true
        #expect(StreakStrip.mode(kept) == .normal)
    }
}
