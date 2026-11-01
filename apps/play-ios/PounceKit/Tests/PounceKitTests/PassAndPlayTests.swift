import Testing
@testable import PounceKit

/// `PassAndPlay` fed the way the shell fed it before `RoomStore` owned it: every room the store
/// applies goes through a `TurnEpoch` (as `RoomStore.turnEpoch` does), and `update` gets that
/// epoch. `missed` is a room the store applied but `update` never saw (a skipped `onChange`).
struct PassDriver {
    var pnp = PassAndPlay()
    var epochs = TurnEpoch()
    var state: CurtainState { pnp.state }
    var revealed: Seat? { pnp.revealed }

    mutating func update(_ room: RoomView) {
        epochs.observe(room)
        pnp.update(TableModel(room: room), epoch: epochs.value)
    }

    mutating func missed(_ room: RoomView) { epochs.observe(room) }
    mutating func completeHold() { pnp.completeHold() }
    mutating func peek(_ seat: Seat) { pnp.peek(seat) }
    mutating func hide() { pnp.hide() }
}

@Suite struct PassAndPlayTests {
    @Test func singleSeatNeverCurtains() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0], turn: 0))
        #expect(pnp.state == .revealed(0))
        pnp.update(makeRoom(mine: [0], turn: 2))
        #expect(pnp.state == .revealed(0))
        pnp.update(makeRoom(mine: [0], turn: 0, round: 2))
        #expect(pnp.state == .revealed(0))
        pnp.hide()
        #expect(pnp.state == .revealed(0))
    }

    @Test func curtainBetweenLocalSeats() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0, 1], turn: 0))
        #expect(pnp.state == .curtain(0))
        #expect(pnp.revealed == nil)
        pnp.completeHold()
        #expect(pnp.state == .revealed(0))
        #expect(pnp.revealed == 0)
        // Same turn, new snapshot (draw -> play): stays revealed.
        pnp.update(makeRoom(mine: [0, 1], turn: 0, step: .play))
        #expect(pnp.state == .revealed(0))
        pnp.update(makeRoom(mine: [0, 1], turn: 1))
        #expect(pnp.state == .curtain(1))
        #expect(pnp.revealed == nil)
        pnp.completeHold()
        #expect(pnp.state == .revealed(1))
    }

    @Test func remoteTurnHidesHand() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0, 1], turn: 0))
        pnp.completeHold()
        pnp.update(makeRoom(mine: [0, 1], turn: 2))
        #expect(pnp.state == CurtainState.none)
        #expect(pnp.revealed == nil)
        // Back to a local seat: curtain again, even the same seat.
        pnp.update(makeRoom(mine: [0, 1], turn: 0))
        #expect(pnp.state == .curtain(0))
    }

    @Test func peekShowsCurtainThenHides() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0, 1], turn: 2))
        pnp.peek(1)
        #expect(pnp.state == .curtain(1))
        pnp.completeHold()
        #expect(pnp.state == .revealed(1))
        // A snapshot on the same remote turn does not hide the peek.
        pnp.update(makeRoom(mine: [0, 1], turn: 2, step: .play))
        #expect(pnp.state == .revealed(1))
        pnp.hide()
        #expect(pnp.state == CurtainState.none)
        #expect(pnp.revealed == nil)
        // Not a seat of mine: ignored.
        pnp.peek(3)
        #expect(pnp.state == CurtainState.none)
    }

    @Test func peekIgnoredDuringOwnTurn() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0, 1], turn: 0))
        pnp.peek(1)
        #expect(pnp.state == .curtain(0))
    }

    @Test func newRoundCurtainsAgain() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0, 1], turn: 0, round: 1))
        pnp.completeHold()
        #expect(pnp.state == .revealed(0))
        pnp.update(makeRoom(mine: [0, 1], turn: 0, round: 2))
        #expect(pnp.state == .curtain(0))
    }

    // M-2: outside live play a multi-seat phone shows no hand, so the round-over celebration
    // plays with every hand face down.
    @Test func roundOverHidesPeek() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0, 1], turn: 2))
        pnp.peek(1)
        pnp.completeHold()
        #expect(pnp.state == .revealed(1))
        // The remote turn ends the round: same turn, status roundOver.
        pnp.update(makeRoom(mine: [0, 1], turn: 2, step: .play, gameStatus: .roundOver))
        #expect(pnp.state == CurtainState.none)
        #expect(pnp.revealed == nil)
        // No peeking while the round is over.
        pnp.peek(0)
        #expect(pnp.state == CurtainState.none)
    }

    @Test func roundOverHidesOwnTurnReveal() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0, 1], turn: 0))
        pnp.completeHold()
        pnp.update(makeRoom(mine: [0, 1], turn: 0, step: .play, gameStatus: .roundOver))
        #expect(pnp.state == CurtainState.none)
        #expect(pnp.revealed == nil)
        pnp.update(makeRoom(mine: [0, 1], turn: 0, step: .play, gameStatus: .gameOver))
        #expect(pnp.state == CurtainState.none)
    }

    @Test func singleSeatKeepsHandThroughRoundOver() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0], turn: 0))
        pnp.update(makeRoom(mine: [0], turn: 0, step: .play, gameStatus: .roundOver))
        #expect(pnp.state == .revealed(0))
    }

    /// The multi-sim arrival: a move link put seat 1 on a one-seat phone in seat 1's turn (its
    /// hand shown, no hold needed), then a second link added seat 2 in the same turn. Two people
    /// share the phone now, so seat 1's hand goes behind the curtain until a hold.
    @Test func secondSeatArrivingMidTurnCurtains() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [1], turn: 1))
        #expect(pnp.state == .revealed(1))
        pnp.update(makeRoom(mine: [1, 2], turn: 1))
        #expect(pnp.state == .curtain(1))
        #expect(pnp.revealed == nil)
        // A seat leaving mid-reveal drops the reveal too.
        pnp.completeHold()
        pnp.update(makeRoom(mine: [0, 1, 2], turn: 1))
        #expect(pnp.state == .curtain(1))
    }

    /// `curtains` counts each new curtain (the shell restarts the hold view on it).
    @Test func countsEachNewCurtain() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0, 1], turn: 0))
        #expect(pnp.pnp.curtains == 1)
        pnp.update(makeRoom(mine: [0, 1], turn: 0, step: .play))
        #expect(pnp.pnp.curtains == 1)
        pnp.update(makeRoom(mine: [0, 1], turn: 1))
        #expect(pnp.pnp.curtains == 2)
        pnp.completeHold()
        pnp.update(makeRoom(mine: [0, 1], turn: 2))
        pnp.peek(1)
        #expect(pnp.pnp.curtains == 3)
        pnp.update(makeRoom(mine: [0, 1], turn: 0))
        #expect(pnp.pnp.curtains == 4)
        // A curtain that stays up (never held) across a turn change is the same curtain.
        pnp.update(makeRoom(mine: [0, 1], turn: 0, round: 2))
        #expect(pnp.state == .curtain(0))
        #expect(pnp.pnp.curtains == 4)
    }

    /// The reveal is valid only in its epoch: the same seat and round with every turn in
    /// between missed by the shell still curtains.
    @Test func revealDoesNotSurviveMissedTurns() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: [0, 1], turn: 0))
        pnp.completeHold()
        pnp.missed(makeRoom(mine: [0, 1], turn: 2))
        pnp.missed(makeRoom(mine: [0, 1], turn: 3))
        pnp.update(makeRoom(mine: [0, 1], turn: 0))
        #expect(pnp.state == .curtain(0))
        #expect(pnp.revealed == nil)
    }
}

@Suite struct TurnEpochTests {
    @Test func bumpsOnTurnRoundAndStatusOnly() {
        var e = TurnEpoch()
        #expect(e.value == 0)
        e.observe(makeRoom(turn: 0))
        #expect(e.value == 1)
        // Step, discard and other changes inside the turn: same epoch.
        e.observe(makeRoom(turn: 0, step: .play, discardTop: 7))
        #expect(e.value == 1)
        e.observe(makeRoom(turn: 1))
        #expect(e.value == 2)
        e.observe(makeRoom(turn: 1, gameStatus: .roundOver))
        #expect(e.value == 3)
        e.observe(makeRoom(turn: 1, round: 2))
        #expect(e.value == 4)
        e.observe(makeRoom(turn: 1, round: 2, status: .over, gameStatus: .gameOver))
        #expect(e.value == 5)
        // Back to an earlier key: still a new epoch, never an old one.
        e.observe(makeRoom(turn: 0))
        #expect(e.value == 6)
    }
}
