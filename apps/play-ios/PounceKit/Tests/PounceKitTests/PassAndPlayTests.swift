import Testing
@testable import PounceKit

@Suite struct PassAndPlayTests {
    @Test func singleSeatNeverCurtains() {
        var pnp = PassAndPlay()
        pnp.update(TableModel(room: makeRoom(mine: [0], turn: 0)))
        #expect(pnp.state == .revealed(0))
        pnp.update(TableModel(room: makeRoom(mine: [0], turn: 2)))
        #expect(pnp.state == .revealed(0))
        pnp.update(TableModel(room: makeRoom(mine: [0], turn: 0, round: 2)))
        #expect(pnp.state == .revealed(0))
        pnp.hide()
        #expect(pnp.state == .revealed(0))
    }

    @Test func curtainBetweenLocalSeats() {
        var pnp = PassAndPlay()
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 0)))
        #expect(pnp.state == .curtain(0))
        #expect(pnp.revealed == nil)
        pnp.completeHold()
        #expect(pnp.state == .revealed(0))
        #expect(pnp.revealed == 0)
        // Same turn, new snapshot (draw -> play): stays revealed.
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 0, step: .play)))
        #expect(pnp.state == .revealed(0))
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 1)))
        #expect(pnp.state == .curtain(1))
        #expect(pnp.revealed == nil)
        pnp.completeHold()
        #expect(pnp.state == .revealed(1))
    }

    @Test func remoteTurnHidesHand() {
        var pnp = PassAndPlay()
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 0)))
        pnp.completeHold()
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 2)))
        #expect(pnp.state == CurtainState.none)
        #expect(pnp.revealed == nil)
        // Back to a local seat: curtain again, even the same seat.
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 0)))
        #expect(pnp.state == .curtain(0))
    }

    @Test func peekShowsCurtainThenHides() {
        var pnp = PassAndPlay()
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 2)))
        pnp.peek(1)
        #expect(pnp.state == .curtain(1))
        pnp.completeHold()
        #expect(pnp.state == .revealed(1))
        // A snapshot on the same remote turn does not hide the peek.
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 2, step: .play)))
        #expect(pnp.state == .revealed(1))
        pnp.hide()
        #expect(pnp.state == CurtainState.none)
        #expect(pnp.revealed == nil)
        // Not a seat of mine: ignored.
        pnp.peek(3)
        #expect(pnp.state == CurtainState.none)
    }

    @Test func peekIgnoredDuringOwnTurn() {
        var pnp = PassAndPlay()
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 0)))
        pnp.peek(1)
        #expect(pnp.state == .curtain(0))
    }

    @Test func newRoundCurtainsAgain() {
        var pnp = PassAndPlay()
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 0, round: 1)))
        pnp.completeHold()
        #expect(pnp.state == .revealed(0))
        pnp.update(TableModel(room: makeRoom(mine: [0, 1], turn: 0, round: 2)))
        #expect(pnp.state == .curtain(0))
    }
}
