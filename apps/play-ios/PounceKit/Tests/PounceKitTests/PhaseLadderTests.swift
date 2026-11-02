import Testing
@testable import PounceKit

@Suite struct PhaseLadderTests {
    @Test func phaseWordsMatchTheSpec() {
        #expect((0..<10).map { Rules.describe(phase: $0) } == [
            "2 sets of 3",
            "1 set of 3 + 1 run of 4",
            "1 set of 4 + 1 run of 4",
            "1 run of 7",
            "1 run of 8",
            "1 run of 9",
            "2 sets of 4",
            "7 cards of one coat",
            "1 set of 5 + 1 set of 2",
            "1 set of 5 + 1 set of 3",
        ])
        #expect(Rules.describe(phase: 10) == "")
        #expect(Rules.describe(phase: -1) == "")
    }

    /// The demo table: me (seat 0) on phase 3, Leo laid phase 1, Kiki on 7, the bot on 4.
    @Test func everySeatSitsOnItsPhase() {
        let model = TableModel(room: DemoFixtures.table(seats: 4, mySeat: 0, phase: 2))
        let ladder = PhaseLadder(model: model, focus: 0)
        #expect(ladder.rungs.count == 10)
        #expect(ladder.rungs.map(\.seats) == [[1], [], [0], [3], [], [], [2], [], [], []])
        #expect(ladder.rungs.map(\.isFocus) == (0..<10).map { $0 == 2 })
        #expect(ladder.rungs.map(\.isDone) == (0..<10).map { $0 < 2 })
        #expect(ladder.laid == [1])
        #expect(ladder.rungs[3].text == "1 run of 7")
    }

    @Test func noFocusChecksNothing() {
        let model = TableModel(room: DemoFixtures.table(seats: 4, mySeat: 0, phase: 2))
        let ladder = PhaseLadder(model: model, focus: nil)
        #expect(ladder.focus == nil)
        #expect(ladder.rungs.allSatisfy { !$0.isFocus && !$0.isDone })
        #expect(PhaseLadder(model: model, focus: 9).focus == nil)
    }

    @Test func pastTheLastPhaseSitsOnTheTopDone() {
        var room = DemoFixtures.table(seats: 2, mySeat: 0, phase: 9)
        room.game?.phase = [10, 9]
        let ladder = PhaseLadder(model: TableModel(room: room), focus: 0)
        #expect(ladder.rungs[9].seats == [0, 1])
        #expect(ladder.rungs[9].isFocus)
        #expect(ladder.rungs.prefix(9).allSatisfy { $0.isDone })
        #expect(ladder.laid.contains(0))
    }
}
