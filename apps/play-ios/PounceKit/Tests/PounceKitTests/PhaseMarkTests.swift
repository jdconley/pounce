import Testing
@testable import PounceKit

@Suite struct PhaseMarkTests {
    @Test func numbersFromOne() {
        #expect(PhaseMark(index: 0, laid: false).text == "P1")
        #expect(PhaseMark(index: 3, laid: false).text == "P4")
        #expect(PhaseMark(index: 9, laid: false).text == "P10")
        #expect(PhaseMark(index: -2, laid: false).text == "P1", "a bad index reads as phase 1")
    }

    @Test func pastTheLastPhaseIsDone() {
        for index in [Rules.phases.count, Rules.phases.count + 3] {
            let mark = PhaseMark(index: index, laid: true)
            #expect(mark.isDone)
            #expect(mark.text == nil)
            #expect(!mark.laid, "a done seat has nothing left to lay down")
        }
        #expect(!PhaseMark(index: 9, laid: false).isDone)
    }

    @Test func laidKeepsThePhase() {
        let mark = PhaseMark(index: 4, laid: true)
        #expect(mark.laid)
        #expect(mark.text == "P5")
    }

    @Test func advancedOnlyForALaterPhase() {
        let p4 = PhaseMark(index: 3, laid: false)
        #expect(!p4.advanced(from: nil), "a cat's first mark doesn't pop")
        #expect(!p4.advanced(from: p4))
        #expect(!PhaseMark(index: 3, laid: true).advanced(from: p4), "laying down isn't a new phase")
        #expect(PhaseMark(index: 4, laid: false).advanced(from: PhaseMark(index: 3, laid: true)))
        #expect(PhaseMark(index: 10, laid: false).advanced(from: PhaseMark(index: 9, laid: true)))
        #expect(!p4.advanced(from: PhaseMark(index: 5, laid: false)), "a new game going back to phase 1 doesn't pop")
    }

    @Test func seatsOfTheDemoTable() throws {
        // Leo (seat 1) laid phase 1; Kiki (seat 2) on phase 7, not laid.
        let game = try #require(DemoFixtures.table(seats: 4, mySeat: 0, phase: 2).game)
        #expect(PhaseMark.seat(1, in: game) == PhaseMark(index: 0, laid: true))
        #expect(PhaseMark.seat(2, in: game) == PhaseMark(index: 6, laid: false))
        #expect(PhaseMark.seat(9, in: game) == nil)
    }
}
