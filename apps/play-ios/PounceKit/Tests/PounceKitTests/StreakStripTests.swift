import Testing
@testable import PounceKit

/// Home's streak strip (trophy room design §1): your own streak, then each connection in
/// top-pair order, then the plus, always last.
@Suite struct StreakStripTests {
    private let own = OwnStreak(count: 12, best: 12)

    @Test func ownThenPairsInOrderThenThePlus() {
        let pairs = [streakView("pr_mia", count: 128), streakView("pr_kiki", count: 9), streakView("pr_nova", count: 41)]
        let chips = StreakStrip.chips(own: own, pairs: pairs)
        #expect(chips == [.own(own), .pair(pairs[0]), .pair(pairs[1]), .pair(pairs[2]), .plus(big: false)])
    }

    @Test func noConnectionsMakesThePlusBigRightAfterYourOwnStreak() {
        #expect(StreakStrip.chips(own: own, pairs: []) == [.own(own), .plus(big: true)])
    }

    @Test func withoutTheOwnStreakItsPairsAndThePlus() {
        let mia = streakView("pr_mia")
        #expect(StreakStrip.chips(own: nil, pairs: [mia]) == [.pair(mia), .plus(big: false)])
        #expect(StreakStrip.chips(own: nil, pairs: []) == [.plus(big: true)])
    }

    @Test func theBigPlusBouncesExceptForATeen() {
        #expect(StreakStrip.bounces(big: true, band: .adult))
        #expect(StreakStrip.bounces(big: true, band: .kitten))
        #expect(!StreakStrip.bounces(big: true, band: .teen))
        #expect(!StreakStrip.bounces(big: false, band: .adult))
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
