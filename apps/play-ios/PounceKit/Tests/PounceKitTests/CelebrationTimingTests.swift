import Testing
@testable import PounceKit

@Suite struct CelebrationTimingTests {
    /// The server deals the next round 6 s after `roundOver`: the sequence fits in 5 s for
    /// every table size and any number of leapers.
    @Test func roundOverFitsTheBudget() {
        for seats in 2...6 {
            for leapers in 0...seats {
                for finale in [false, true] {
                    let total = CelebrationTiming.roundOver(seats: seats, leapers: leapers, finale: finale)
                    #expect(total <= CelebrationTiming.roundOverBudget, "\(seats) seats, \(leapers) leapers: \(total)")
                }
            }
        }
    }

    @Test func staggersAreTheSpecsUntilCrowded() {
        #expect(CelebrationTiming.pointsStagger(seats: 4) == 0.3)
        #expect(CelebrationTiming.leapStagger(leapers: 2) == 0.45)
        #expect(CelebrationTiming.pointsStagger(seats: 6) < 0.3)
        #expect(CelebrationTiming.leapStagger(leapers: 6) < 0.45)
        #expect(CelebrationTiming.pointsStagger(seats: 1) == 0)
        #expect(CelebrationTiming.leapStagger(leapers: 1) == 0)
    }

    @Test func leapIsSquatArcSquashThenBadge() {
        #expect(abs(CelebrationTiming.leap - (0.08 + 0.35 + 0.14 + 0.22 + 0.3)) < 1e-9)
    }
}
