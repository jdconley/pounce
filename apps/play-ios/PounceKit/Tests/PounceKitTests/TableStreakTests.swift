import Testing
@testable import PounceKit

@Suite struct TableStreakTests {
    private let jd = "jd"
    private let kid = "kid"
    private let mia = streakView("pr_mia", count: 40, partner: .init(name: "Mia", cat: 2), theirMove: ["FAMLY"])
    private let sam = streakView("pr_sam", count: 9, partner: .init(name: "Sam", cat: 6), myMove: ["FAMLY"])
    private let mom = streakView("pr_mom", count: 70, partner: .init(name: "Mom", cat: 5), myMove: ["OTHER"])

    @Test func picksTopPairAtThisTable() {
        let pick = TableStreak.pick(code: "FAMLY", candidates: [(jd, mom), (jd, mia), (jd, sam)], reported: [], others: [])
        #expect(pick?.view.pair == "pr_mia")
        #expect(pick?.person == jd)
    }

    @Test func ignoresPairsElsewhere() {
        #expect(TableStreak.pick(code: "NOPES", candidates: [(jd, mom), (jd, mia)], reported: [], others: []) == nil)
    }

    @Test func reportedOnThisSocketCounts() {
        let pick = TableStreak.pick(code: "NOPES", candidates: [(jd, mom), (kid, mia)], reported: ["pr_mia"], others: [])
        #expect(pick?.view.pair == "pr_mia")
        #expect(pick?.person == kid)
    }

    @Test func partnerSeatMatchCounts() {
        let pick = TableStreak.pick(code: "NOPES", candidates: [(jd, mom), (jd, sam)], reported: [],
                                    others: [Person(id: "x", name: "Sam", cat: 6)])
        #expect(pick?.view.pair == "pr_sam")
        #expect(TableStreak.pick(code: "NOPES", candidates: [(jd, sam)], reported: [],
                                 others: [Person(id: "x", name: "Sam", cat: 1)]) == nil, "a namesake with another cat isn't them")
    }
}
