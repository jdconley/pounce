import Testing
@testable import PounceKit

@Suite struct SolverTests {
    // tabby numbers: id = value - 1; tuxedo: 24 + value - 1; yarn 96...; cucumber 104...
    private func n(_ value: Int, _ coat: Int = 0) -> CardID { coat * 24 + value - 1 }

    @Test func findsTwoSetsOfThree() {
        let hand = [n(5, 0), n(5, 1), n(5, 2), n(9, 0), n(9, 1), n(9, 3), n(2, 0), n(11, 1), 104, 105]
        let groups = Solver.findPhase(hand: hand, phaseIndex: 0)
        #expect(groups != nil)
        #expect(Rules.matchPhase(0, groups: groups ?? []) != nil)
        #expect(groups?.allSatisfy { Set($0.cards).isSubset(of: Set(hand)) } == true)
        #expect(groups?.flatMap(\.cards).contains(where: { $0 >= 104 }) == false)
        #expect(groups?.flatMap(\.cards).contains(where: { $0 >= 96 }) == false)
    }

    @Test func usesYarnOnlyWhenNeeded() {
        let hand = [n(5, 0), n(5, 1), n(9, 0), n(9, 1), n(9, 2), 96, 97, n(2, 0), n(3, 0), n(12, 3)]
        let groups = Solver.findPhase(hand: hand, phaseIndex: 0)
        #expect(Rules.matchPhase(0, groups: groups ?? []) != nil)
        #expect(groups?.flatMap(\.cards).filter { $0 >= 96 }.count == 1)
    }

    @Test func findsRunWithYarnGap() {
        // Phase 4 (index 3): run of 7. Values 2,3,4,6,7,8,9 plus a Yarn for the 5.
        let hand = [n(2, 0), n(3, 1), n(4, 2), n(6, 0), n(7, 3), n(8, 1), n(9, 0), 96, n(12, 2), 104]
        let groups = Solver.findPhase(hand: hand, phaseIndex: 3)
        #expect(groups?.count == 1)
        #expect(groups?[0].runStart != nil)
        let built = Rules.matchPhase(3, groups: groups ?? [])
        #expect(built != nil)
        if case .run(let cards, let start, let end)? = built?.first {
            #expect(cards.count == 7)
            #expect(end - start == 6)
            #expect(cards.contains(96))
        } else {
            Issue.record("expected a run")
        }
    }

    @Test func findsSetAndRun() {
        let hand = [n(7, 0), n(7, 1), n(7, 2), n(1, 0), n(2, 1), n(3, 2), n(4, 3), n(12, 0), 104, n(10, 3)]
        let groups = Solver.findPhase(hand: hand, phaseIndex: 1)
        #expect(Rules.matchPhase(1, groups: groups ?? []) != nil)
    }

    @Test func findsCoatSeven() {
        let hand = [n(1), n(3), n(4), n(6), n(8), n(9), n(11), n(2, 1), n(5, 2), 98]
        let groups = Solver.findPhase(hand: hand, phaseIndex: 7)
        #expect(Rules.matchPhase(7, groups: groups ?? []) != nil)
    }

    @Test func returnsNilWhenImpossible() {
        let hand = [n(1, 0), n(3, 1), n(5, 2), n(7, 3), n(9, 0), n(11, 1), 104, 105, 106, 107]
        for phase in 0..<10 {
            #expect(Solver.findPhase(hand: hand, phaseIndex: phase) == nil)
        }
        #expect(Solver.findPhase(hand: hand, phaseIndex: 10) == nil)
        // All Yarn is not a legal group either (needs a natural card).
        #expect(Solver.findPhase(hand: [96, 97, 98, 99, 100, 101, 102, 103], phaseIndex: 3) == nil)
    }

    @Test func hitsExtendGroupsSequentially() {
        let laid: [[Group]?] = [
            nil,
            [.run(cards: [n(3), n(4), n(5), n(6)], start: 3, end: 6), .set(cards: [n(11, 0), n(11, 1), n(11, 2)], value: 11)],
        ]
        let hand = [n(8, 2), n(7, 1), n(11, 3), n(1, 0), 104]
        let result = Solver.hits(hand: hand, laid: laid)
        #expect(Set(result.map(\.card)) == [n(7, 1), n(8, 2), n(11, 3)])
        // 8 only fits after 7 has been laid on the run.
        let order = result.map(\.card)
        #expect(order.firstIndex(of: n(7, 1))! < order.firstIndex(of: n(8, 2))!)
        #expect(result.first { $0.card == n(11, 3) }?.target == HitTarget(seat: 1, group: 1))
    }
}
