import Testing
@testable import PounceKit

/// Replays the room sequences from the MixedSeatsTests "stuck" runs (tl14 / tl15 timeline logs)
/// through PassAndPlay, the only thing that decides the curtain. Seats: 0 and 2 local, 1 remote,
/// 3 bot. Rooms the shell sees go through `PassDriver.update`; rooms only the store applied
/// (SwiftUI coalesced them away) go through `missed` or, in the last tests, a real `RoomStore`.
@MainActor @Suite struct CurtainReplayTests {
    private let mine: Set<Seat> = [0, 2]

    /// tl15: seat 0 revealed and played; the shell then synced seq 25 (turn 1 draw) and seq 26
    /// (turn 1 play); seq 27/28 (turn 2) never reached the shell until 4 min later. The first
    /// sync that does arrive (any later room, here seq 28 or the seq 29 presence) must curtain 2.
    @Test func coalescedJumpFromRemoteTurnToLocalSeatCurtains() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: mine, turn: 0))
        #expect(pnp.state == .curtain(0))
        pnp.completeHold()
        pnp.update(makeRoom(mine: mine, turn: 0, step: .play))
        #expect(pnp.state == .revealed(0))
        pnp.update(makeRoom(mine: mine, turn: 1))
        pnp.update(makeRoom(mine: mine, turn: 1, step: .play))
        #expect(pnp.state == CurtainState.none)
        // seq 28 (or the seq 29 presence on top of it): turn 2, draw.
        pnp.update(makeRoom(mine: mine, turn: 2))
        #expect(pnp.state == .curtain(2))
        // The same room again (reconnect snapshot, seq == lastSeq): still the curtain.
        pnp.update(makeRoom(mine: mine, turn: 2))
        #expect(pnp.state == .curtain(2))
    }

    /// tl14: seat 2 revealed; bot's turn synced; the turn to seat 0 never reached the shell.
    @Test func botTurnThenLocalSeatCurtains() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: mine, turn: 2))
        pnp.completeHold()
        pnp.update(makeRoom(mine: mine, turn: 3, step: .play))
        #expect(pnp.state == CurtainState.none)
        pnp.update(makeRoom(mine: mine, turn: 0))
        #expect(pnp.state == .curtain(0))
    }

    /// Round boundary starting on a local seat, including a roundOver snapshot in between.
    @Test func newRoundOnLocalSeatCurtains() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: mine, turn: 0))
        pnp.completeHold()
        pnp.update(makeRoom(mine: mine, turn: 0, step: .play, gameStatus: .roundOver))
        // Round over: a multi-seat phone shows no hand (M-2), so the celebration plays with
        // every hand face down.
        #expect(pnp.state == CurtainState.none)
        #expect(pnp.revealed == nil)
        pnp.update(makeRoom(mine: mine, turn: 0, round: 2))
        #expect(pnp.state == .curtain(0))
        // And the case with no roundOver snapshot seen at all (coalesced): round change alone.
        var direct = PassDriver()
        direct.update(makeRoom(mine: mine, turn: 0))
        direct.completeHold()
        direct.missed(makeRoom(mine: mine, turn: 0, step: .play, gameStatus: .roundOver))
        direct.update(makeRoom(mine: mine, turn: 0, round: 2))
        #expect(direct.state == .curtain(0))
    }

    /// Formerly a known issue: the shell misses every turn between two turns of the same local
    /// seat in the same round. The store saw them all, so its epoch moved and the reveal is gone.
    @Test func fullCycleMissedCurtainsAgain() {
        var pnp = PassDriver()
        pnp.update(makeRoom(mine: mine, turn: 0))
        pnp.completeHold()
        #expect(pnp.state == .revealed(0))
        // Turns 1, 2 (curtain), 3 happen without the shell seeing them; back to 0.
        pnp.missed(makeRoom(mine: mine, turn: 1))
        pnp.missed(makeRoom(mine: mine, turn: 2))
        pnp.missed(makeRoom(mine: mine, turn: 3))
        pnp.update(makeRoom(mine: mine, turn: 0, step: .draw))
        #expect(pnp.state == .curtain(0))
        #expect(pnp.revealed == nil)
    }

    /// The same full cycle through a real `RoomStore`: reveal 0, the store applies three
    /// snapshots of other turns (and the turn events between them) without the shell calling
    /// `update`, then the turn comes back to 0.
    @Test func fullCycleThroughStoreCurtainsAgain() {
        let store = RoomStore(code: "BCDFG", socket: FakeSocket())
        var pnp = PassAndPlay()
        func shellSync() {
            guard let room = store.room else { return }
            pnp.update(TableModel(room: room), epoch: store.turnEpoch)
        }
        var seq = 10
        func snap(_ turn: Seat, _ step: TurnStep = .draw) {
            seq += 1
            store.handle(.message(.snapshot(protocol: 1, seq: seq, room: makeRoom(mine: mine, turn: turn, step: step))))
        }
        func turnEvent(_ turn: Seat) {
            seq += 1
            store.handle(.message(.event(seq: seq, event: .game(.turn(seat: turn)))))
        }

        snap(0)
        shellSync()
        #expect(pnp.state == .curtain(0))
        pnp.completeHold()
        snap(0, .play)
        shellSync()
        #expect(pnp.state == .revealed(0))

        // The shell sees none of these.
        for turn in [1, 2, 3] {
            turnEvent(turn)
            snap(turn, .play)
        }
        turnEvent(0)
        snap(0)

        shellSync()
        #expect(pnp.state == .curtain(0))
        #expect(pnp.revealed == nil)
    }
}
