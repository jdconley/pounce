import Foundation
import Testing
@testable import PounceKit

/// Forfeiting a game (spec §5.13): the protocol, the table model and pass-and-play.
@Suite struct ForfeitTests {
    private func server(_ name: String) throws -> ServerMessage {
        let json = try #require(try Fixtures.serverMessages().first { $0.name == name }).json
        return try Codec.decode(json)
    }

    // MARK: protocol

    @Test func encodesTheForfeitAction() throws {
        #expect(try Codec.encode(.act(seat: 1, action: .forfeit)) == #"{"action":{"type":"forfeit"},"seat":1,"t":"act"}"#)
    }

    @Test func decodesTheForfeitedEventAndSeats() throws {
        guard case .event(_, .game(.forfeited(let seat))) = try server("event-forfeited") else {
            Issue.record("not a forfeited event")
            return
        }
        #expect(seat == 1)
        guard case .snapshot(_, _, let room) = try server("snapshot-playing-forfeited"), let game = room.game else {
            Issue.record("no game")
            return
        }
        #expect(game.forfeited == [false, true, false])
        #expect(game.isOut(1) && !game.isOut(0) && !game.isOut(7))
        #expect(game.handCounts[1] == 0)
        guard case .error(let code) = try server("error-forfeited") else {
            Issue.record("not an error")
            return
        }
        #expect(code == .forfeited)
    }

    @Test func aServerWithoutForfeitsMeansNobodyIsOut() throws {
        guard case .snapshot(_, _, let room) = try server("snapshot-playing-with-hand"), var game = room.game else {
            Issue.record("no game")
            return
        }
        #expect(game.forfeited == [false, false, false])
        // A game view with no `forfeited` key at all (an older server).
        game.forfeited = []
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as! [String: Any]
        json.removeValue(forKey: "forfeited")
        let decoded = try JSONDecoder().decode(GameView.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.forfeited == [false, false, false])
    }

    // MARK: table model

    @Test func forfeitSeatIsTheHandUpThenTheTurnThenTheFirstStillIn() {
        let solo = TableModel(room: makeRoom(seatCount: 3, mine: [0], turn: 1))
        #expect(solo.forfeitSeat(shown: nil) == 0)
        let shared = TableModel(room: makeRoom(seatCount: 3, mine: [0, 1], turn: 1))
        #expect(shared.forfeitSeat(shown: 0) == 0)
        #expect(shared.forfeitSeat(shown: nil) == 1)
        #expect(TableModel(room: makeRoom(seatCount: 3, mine: [0, 1], turn: 2)).forfeitSeat(shown: nil) == 0)
        // A seat already out is never the one.
        let oneOut = TableModel(room: makeRoom(seatCount: 3, mine: [0, 1], turn: 1, forfeited: [true, false, false]))
        #expect(oneOut.forfeitSeat(shown: 0) == 1)
        #expect(oneOut.myActiveSeats == [1])
    }

    @Test func nothingToForfeitOutsidePlayOrOnceOut() {
        #expect(TableModel(room: makeRoom(status: .lobby)).forfeitSeat(shown: nil) == nil)
        #expect(TableModel(room: makeRoom(status: .over, gameStatus: .gameOver)).forfeitSeat(shown: nil) == nil)
        #expect(TableModel(room: makeRoom(mine: [0], forfeited: [true, false, false, false])).forfeitSeat(shown: nil) == nil)
        #expect(TableModel(room: makeRoom(mine: [])).forfeitSeat(shown: nil) == nil)
        // Between rounds is still play.
        #expect(TableModel(room: makeRoom(gameStatus: .roundOver)).forfeitSeat(shown: nil) == 0)
    }

    @Test func outcomeEndsTheGameWithOneOtherSeatLeft() {
        #expect(TableModel(room: makeRoom(seatCount: 2)).forfeitOutcome(0) == .ends(winner: 1))
        #expect(TableModel(room: makeRoom(seatCount: 3)).forfeitOutcome(0) == .out)
        #expect(TableModel(room: makeRoom(seatCount: 3, forfeited: [false, false, true])).forfeitOutcome(0) == .ends(winner: 1))
    }

    @Test func outForMeOnlyWhileTheOthersPlayOn() {
        #expect(TableModel(room: makeRoom(mine: [0], forfeited: [true, false, false, false])).isOutForMe)
        #expect(!TableModel(room: makeRoom(mine: [0, 1], forfeited: [true, false, false, false])).isOutForMe)
        #expect(!TableModel(room: makeRoom(mine: [0])).isOutForMe)
        #expect(!TableModel(room: makeRoom(mine: [0], status: .over, gameStatus: .gameOver, forfeited: [true, false, false, false])).isOutForMe)
    }

    @Test func aCucumberCantSkipAForfeitedSeat() {
        let model = TableModel(room: makeRoom(seatCount: 4, step: .play, forfeited: [false, true, false, false]))
        #expect(model.skipTargets(for: 0) == [2, 3])
        #expect(model.discardAction(card: 104, target: 1) == .discard(card: 104, skipTarget: nil))
    }

    @Test func announcesAForfeit() {
        let model = TableModel(room: makeRoom(mine: [0]))
        #expect(TableAnnouncement.announcement(for: .forfeited(seat: 2), model: model) == .forfeited(seat: 2, mine: false))
        #expect(TableAnnouncement.announcement(for: .forfeited(seat: 0), model: model) == .forfeited(seat: 0, mine: true))
    }

    // MARK: pass-and-play

    @Test func aSharedPhoneWithOneSeatLeftShowsThatHand() {
        var pnp = PassDriver()
        pnp.update(makeRoom(seatCount: 3, mine: [0, 1], turn: 0))
        #expect(pnp.state == .curtain(0))
        // Seat 0 forfeits: seat 1 is the only hand left, so no more curtains.
        pnp.update(makeRoom(seatCount: 3, mine: [0, 1], turn: 1, forfeited: [true, false, false]))
        #expect(pnp.state == .revealed(1))
        pnp.update(makeRoom(seatCount: 3, mine: [0, 1], turn: 2, forfeited: [true, false, false]))
        #expect(pnp.state == .revealed(1))
    }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStoreForfeitTests {
    @Test func aForfeitedEventPostsANotice() throws {
        let socket = FakeSocket()
        let store = RoomStore(code: "BCDFG", socket: socket)
        let json = try #require(try Fixtures.serverMessages().first { $0.name == "snapshot-playing-with-hand" }).json
        guard case .snapshot(_, _, let room) = try Codec.decode(json) else { throw Fixtures.FixtureError.malformed("snap") }
        store.handle(.connected)
        store.handle(.message(.snapshot(protocol: 1, seq: 5, room: room)))
        #expect(store.forfeitNotice == nil)
        store.handle(.message(.event(seq: 6, event: .game(.forfeited(seat: 1)))))
        #expect(store.forfeitNotice == RoomStore.ForfeitNotice(seat: 1, serial: 1))
        store.handle(.message(.event(seq: 7, event: .game(.forfeited(seat: 2)))))
        #expect(store.forfeitNotice == RoomStore.ForfeitNotice(seat: 2, serial: 2))
    }
}
