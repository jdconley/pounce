#if DEBUG
import Foundation
import Testing
@testable import PounceKit

/// The store at a Purrtrait table: moves in the `act` envelope, ink that never waits on the move
/// lock, the turn's ink kept for the easel and dropped with the turn, and the refusals that end a
/// phone's visit.
@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStorePurrtraitTests {
    static func room(_ name: String) throws -> RoomView {
        let json = try #require(try Fixtures.purrtraitServerMessages().first { $0.name == name }).json
        guard case .snapshot(_, _, let room) = try Codec.decode(json) as ServerMessage else {
            throw Fixtures.FixtureError.malformed(name)
        }
        return room
    }

    private func snapshot(_ room: RoomView, seq: Int) -> SocketEvent {
        .message(.snapshot(protocol: 1, seq: seq, room: room))
    }

    private func store(_ room: RoomView, role: RoomRole? = nil) -> (RoomStore, FakeSocket) {
        let socket = FakeSocket()
        let store = RoomStore(code: room.code, socket: socket, role: role)
        store.handle(.connected)
        store.handle(snapshot(room, seq: 5))
        return (store, socket)
    }

    private let stroke = InkOp.stroke(id: 0, color: 0, width: 1, start: InkPoint(10, 10), deltas: [InkPoint(5, 5)])

    @Test func aPickGoesOutAsAnAct() async throws {
        let (store, socket) = store(try Self.room("snapshot-choosing-drawer"))
        #expect(store.phase == .playing)
        #expect(store.actPurrtrait(seat: 0, .choose(.tricky)))
        await store.settle()
        #expect(socket.calls.sends == [.actPurrtrait(seat: 0, action: .choose(.tricky))])
    }

    @Test func inkNeverWaitsOnTheMoveLock() async throws {
        let (store, socket) = store(try Self.room("snapshot-drawing-drawer"))
        #expect(store.actPurrtrait(seat: 0, .giveUp))
        store.sendInk(seat: 0, turn: "1:0", ops: [stroke])
        await store.settle()
        #expect(socket.calls.sends == [.actPurrtrait(seat: 0, action: .giveUp), .ink(seat: 0, turn: "1:0", ops: [stroke])])
    }

    @Test func inkThatNeverLeftSaysSo() async throws {
        let (store, socket) = store(try Self.room("snapshot-drawing-drawer"))
        let message = ClientMessage.ink(seat: 0, turn: "1:0", ops: [stroke])
        socket.failSends(of: [message])
        var failed = 0
        store.sendInk(seat: 0, turn: "1:0", ops: [stroke]) { failed += 1 }
        await store.settle()
        #expect(failed == 1)
    }

    @Test func theTVKeepsThisTurnsInkAndDropsItWithTheTurn() throws {
        let (store, _) = store(try Self.room("snapshot-drawing-screen-paused"), role: .screen)
        var changes: [InkFeed.Change] = []
        store.ink.onChange = { changes.append($0) }
        store.handle(.message(.ink(seat: 0, turn: "1:0", ops: [stroke])))
        store.handle(.message(.ink(seat: 0, turn: "0:9", ops: [.clear])))  // a stale turn: dropped
        #expect(store.ink.ops == [stroke])
        #expect(changes == [.ops([stroke])])
        // The reveal keeps the picture up; the next turn drops it.
        store.handle(snapshot(try Self.room("snapshot-reveal"), seq: 6))
        #expect(store.ink.ops == [stroke])
        var next = try Self.room("snapshot-choosing-guesser")
        next.purrtrait?.turn = "1:1"
        store.handle(snapshot(next, seq: 7))
        #expect(store.ink.ops.isEmpty)
        #expect(changes.last == .reset)
    }

    @Test func inkSyncIsTheWholePictureCompacted() throws {
        let (store, _) = store(try Self.room("snapshot-drawing-screen-paused"), role: .screen)
        let b = InkOp.stroke(id: 1, color: 2, width: 0, start: InkPoint(1, 1), deltas: [])
        store.handle(.message(.inkSync(turn: "1:0", ops: [stroke, b, .undo(id: 1)])))
        #expect(store.ink.ops == [stroke])
        #expect(store.ink.turn == "1:0")
    }

    @Test func inkResendReachesTheDrawer() throws {
        let (store, _) = store(try Self.room("snapshot-drawing-drawer"))
        var changes: [InkFeed.Change] = []
        store.ink.onChange = { changes.append($0) }
        store.handle(.message(.inkResend(turn: "1:0")))
        store.handle(.message(.inkResend(turn: "9:9")))
        #expect(changes == [.resend(turn: "1:0")])
    }

    @Test func aFullEaselIsANoticeNotARefusedMove() throws {
        let (store, _) = store(try Self.room("snapshot-drawing-drawer"))
        store.handle(.message(.error(.easelFull)))
        #expect(store.easelFull?.serial == 1)
        #expect(store.phase == .playing)
    }

    @Test func aRefusedPhoneStaysOut() async throws {
        let socket = FakeSocket()
        let store = RoomStore(code: "KQ7XPM", socket: socket)
        store.handle(.forbidden(.notNear))
        #expect(store.phase == .notNear)
        store.handle(snapshot(try Self.room("snapshot-lobby-phone"), seq: 1))
        #expect(store.phase == .notNear)

        let (removed, _) = self.store(try Self.room("snapshot-drawing-guesser"))
        removed.handle(.message(.error(.removed)))
        #expect(removed.phase == .removed)
        await removed.settle()
    }

    @Test func eventsFoldInTheDrawerAndThePhase() throws {
        let (store, _) = store(try Self.room("snapshot-reveal"))
        store.handle(.message(.event(seq: 6, event: .purrtrait(.turn(drawer: 1, round: 1)))))
        #expect(store.room?.purrtrait?.drawer == 1)
        #expect(store.room?.purrtrait?.phase == .choosing)
        #expect(store.room?.liveTurn == 1)
    }

    @Test func aSharedPhoneCurtainsEachTurnNotEachPick() throws {
        var choosing = try Self.room("snapshot-choosing-drawer")
        choosing.seats[1].yours = true
        let (store, _) = store(choosing)
        let epoch = store.turnEpoch
        var drawing = try Self.room("snapshot-drawing-drawer")
        drawing.seats[1].yours = true
        store.handle(snapshot(drawing, seq: 6))
        #expect(store.turnEpoch == epoch)
        var next = drawing
        next.purrtrait?.turn = "1:1"
        next.purrtrait?.drawer = 1
        store.handle(snapshot(next, seq: 7))
        #expect(store.turnEpoch == epoch + 1)
    }
}
#endif
