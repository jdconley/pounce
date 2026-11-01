import Foundation
import Testing
@testable import PounceKit

@Suite struct PushPolicyTests {
    /// Seats 0..n with `mine` on this phone; `bots` are House Cat seats.
    private func room(mine: Set<Seat>, bots: Set<Seat> = [], status: RoomStatus = .playing, turn: Seat = 0) -> TableModel {
        var view = makeRoom(seatCount: 4, mine: mine, turn: turn, status: status)
        for seat in bots {
            view.seats[seat] = SeatView(kind: .bot)
        }
        return TableModel(room: view)
    }

    @Test func primesOnlyWhenARemoteHumanExists() {
        #expect(PushPolicy.shouldPrime(model: room(mine: [0]), primed: false))
        #expect(PushPolicy.shouldPrime(model: room(mine: [0, 1], bots: [2]), primed: false))
    }

    @Test func neverPrimesForBotsOnlyOrAllLocal() {
        #expect(!PushPolicy.shouldPrime(model: room(mine: [0], bots: [1, 2, 3]), primed: false))
        #expect(!PushPolicy.shouldPrime(model: room(mine: [0, 1, 2, 3]), primed: false))
        #expect(!PushPolicy.shouldPrime(model: room(mine: [0, 1], bots: [2, 3]), primed: false))
    }

    @Test func neverPrimesTwiceOrOutsidePlay() {
        #expect(!PushPolicy.shouldPrime(model: room(mine: [0]), primed: true))
        #expect(!PushPolicy.shouldPrime(model: room(mine: [0], status: .lobby), primed: false))
        #expect(!PushPolicy.shouldPrime(model: room(mine: [0], status: .over), primed: false))
        // Watching a game this phone has no seat in: nothing to remind about.
        #expect(!PushPolicy.shouldPrime(model: room(mine: []), primed: false))
    }

    @Test func reminderOnlyOnMyTurn() {
        #expect(PushPolicy.reminderDelay(model: room(mine: [0], turn: 0)) == .seconds(600))
        #expect(PushPolicy.reminderDelay(model: room(mine: [0, 1], turn: 1)) == .seconds(600))
        #expect(PushPolicy.reminderDelay(model: room(mine: [0], turn: 2)) == nil)
        #expect(PushPolicy.reminderDelay(model: room(mine: [0], status: .lobby)) == nil)
    }

    @Test func hexTokenIsLowercasePairs() {
        #expect(PushPolicy.hexToken(Data([0xAB, 0x01])) == "ab01")
        #expect(PushPolicy.hexToken(Data()) == "")
    }

    @Test func payloadCodeIsValidated() {
        #expect(PushPolicy.code(fromPayload: ["code": "K7QM4"]) == "K7QM4")
        #expect(PushPolicy.code(fromPayload: ["code": "bad"]) == nil)
        #expect(PushPolicy.code(fromPayload: ["code": 12345]) == nil)
        #expect(PushPolicy.code(fromPayload: ["aps": ["thread-id": "K7QM4"]]) == nil)
    }

    @Test func reminderIDsAreRecognisedByPrefix() {
        #expect(PushPolicy.reminderID(code: "K7QM4") == "turn-reminder-K7QM4")
        #expect(PushPolicy.isReminderID(PushPolicy.reminderID(code: "K7QM4")))
        #expect(PushPolicy.isReminderID("turn-reminder-BCDFG"))
        // Server pushes and anything else on the phone are never touched.
        #expect(!PushPolicy.isReminderID("K7QM4"))
        #expect(!PushPolicy.isReminderID("other-turn-reminder-K7QM4"))
        #expect(!PushPolicy.isReminderID(""))
    }
}
