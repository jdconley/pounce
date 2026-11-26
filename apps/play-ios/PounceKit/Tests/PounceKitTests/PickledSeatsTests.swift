import Testing
@testable import PounceKit

/// "Pickled": a seat a Cucumber skips. Its cat says so from the moment the Cucumber is aimed at
/// it until the turn played in its place is over.
@Suite struct PickledSeatsTests {
    /// Four seats in round 3, `turn` on the move, `pending` skips waiting.
    private func game(turn: Seat, pending: [Seat] = [], round: Int = 3, status: GameStatus = .playing, out: [Seat] = []) -> GameView {
        var g = DemoFixtures.table(seats: 4, mySeat: 0, phase: 0).game!
        g.turn = turn
        g.round = round
        g.status = status
        g.pendingSkip = (0..<4).map { pending.contains($0) }
        g.forfeited = (0..<4).map { out.contains($0) }
        return g
    }

    /// Aimed at a seat further round: pickled while the skip waits (the server's `pendingSkip`),
    /// and still through the turn played instead of theirs; gone once that turn ends.
    @Test func aSkipWaitingThenTheTurnPlayedInsteadOfTheirs() {
        var pickled = PickledSeats()
        // Mia (0) aims at Kiki (2); Leo (1) plays.
        pickled.note(.discarded(seat: 0, card: 104, skipTarget: 2), round: 3)
        pickled.note(.turn(seat: 1), round: 3)
        #expect(pickled.seats(in: game(turn: 1, pending: [2])) == [2])
        // Leo's turn ends: Kiki is passed over and Nova (3) plays in her place.
        pickled.note(.discarded(seat: 1, card: 5, skipTarget: nil), round: 3)
        pickled.note(.skipped(seat: 2), round: 3)
        pickled.note(.turn(seat: 3), round: 3)
        #expect(pickled.seats(in: game(turn: 3)) == [2])
        // Nova's turn ends: Kiki's skipped turn is over.
        pickled.note(.discarded(seat: 3, card: 6, skipTarget: nil), round: 3)
        pickled.note(.turn(seat: 0), round: 3)
        #expect(pickled.seats(in: game(turn: 0)).isEmpty)
    }

    /// The mark comes with the Cucumber's discard, before the snapshot that sets `pendingSkip`.
    @Test func theMarkComesWithTheDiscard() {
        var pickled = PickledSeats()
        pickled.note(.discarded(seat: 0, card: 104, skipTarget: 2), round: 3)
        #expect(pickled.seats(in: game(turn: 0)) == [2])
        pickled.note(.discarded(seat: 0, card: 5, skipTarget: nil), round: 3)
        #expect(pickled.seats(in: game(turn: 0)) == [2])
        // A new round deals the aim away.
        pickled.note(.roundStarted(round: 4, dealer: 1), round: 3)
        #expect(pickled.seats(in: game(turn: 2, round: 4)).isEmpty)
    }

    /// Aimed at the next seat: the server skips it in the same move, so `pendingSkip` is never
    /// set in a snapshot. The mark lasts through the turn played instead.
    @Test func theNextSeatIsPickledThroughTheTurnThatReplacesIt() {
        var pickled = PickledSeats()
        pickled.note(.discarded(seat: 0, card: 104, skipTarget: 1), round: 3)
        pickled.note(.skipped(seat: 1), round: 3)
        pickled.note(.turn(seat: 2), round: 3)
        #expect(pickled.seats(in: game(turn: 2)) == [1])
        pickled.note(.turn(seat: 3), round: 3)
        #expect(pickled.seats(in: game(turn: 3)).isEmpty)
    }

    /// Two players: the Cucumber's thrower plays again, and the other stays pickled until that
    /// extra turn is done.
    @Test func twoPlayersTheExtraTurn() {
        var pickled = PickledSeats()
        pickled.note(.skipped(seat: 1), round: 3)
        pickled.note(.turn(seat: 0), round: 3)
        #expect(pickled.seats(in: game(turn: 0)) == [1])
        pickled.note(.turn(seat: 1), round: 3)
        #expect(pickled.seats(in: game(turn: 1)).isEmpty)
    }

    /// A pickle never outlives its round, a game that ended, or a seat that forfeited, and a
    /// table opened mid-game still shows the skips waiting.
    @Test func roundsGameOverForfeitsAndAFreshTable() {
        var pickled = PickledSeats()
        pickled.note(.skipped(seat: 1), round: 3)
        pickled.note(.turn(seat: 2), round: 3)
        #expect(pickled.seats(in: game(turn: 2, round: 4)).isEmpty)
        #expect(pickled.seats(in: game(turn: 2, status: .roundOver)).isEmpty)
        #expect(pickled.seats(in: game(turn: 2, out: [1])).isEmpty)
        pickled.note(.roundOver(wentOut: 2, points: [0, 0, 0, 0], advanced: [], scores: [0, 0, 0, 0], phase: [0, 0, 0, 0]), round: 3)
        #expect(pickled.seats(in: game(turn: 2)).isEmpty)
        #expect(PickledSeats().seats(in: game(turn: 0, pending: [2, 3])) == [2, 3])
    }

    /// A round dealt with a Cucumber up skips the first seat: pickled through the first turn.
    @Test func aCucumberDealtUpPicklesTheFirstSeat() {
        var pickled = PickledSeats()
        pickled.note(.skipped(seat: 1), round: 3)
        pickled.note(.turn(seat: 2), round: 3)
        pickled.note(.roundStarted(round: 4, dealer: 0), round: 3)
        pickled.note(.skipped(seat: 1), round: 3)
        pickled.note(.turn(seat: 2), round: 3)
        #expect(pickled.seats(in: game(turn: 2, round: 4)) == [1])
    }
}
