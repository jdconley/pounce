import Foundation
import Testing
@testable import PounceKit

/// Nudges in the store: the player card's button from the server's `nudge`, a send, its answer,
/// a refusal, and a nudge for this phone.
@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStoreNudgeTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    /// Bob's (seat 1, on another phone) move, two seats; `nudge` as the server sent it.
    private func room(nudge: NudgeView? = NudgeView(seat: 1, sent: false, wait: 30_000)) throws -> RoomView {
        let json = try #require(try Fixtures.serverMessages().first { $0.name == "snapshot-playing-nudge-wait" }).json
        guard case .snapshot(_, _, var room) = try Codec.decode(json) else { throw Fixtures.FixtureError.malformed("snapshot") }
        room.game?.turn = 1
        room.nudge = nudge
        return room
    }

    private func snapshot(_ room: RoomView, seq: Int) -> SocketEvent {
        .message(.snapshot(protocol: 1, seq: seq, room: room))
    }

    private func make(_ room: RoomView) -> (RoomStore, FakeSocket, Clock) {
        let socket = FakeSocket()
        let clock = Clock()
        let store = RoomStore(code: "BCDFG", socket: socket, clock: { clock.now })
        store.handle(.connected)
        store.handle(snapshot(room, seq: 5))
        return (store, socket, clock)
    }

    @Test func theButtonWaitsOutTheServersWaitThenNudges() async throws {
        let (store, socket, clock) = try make(room())
        let ready = clock.now.addingTimeInterval(30)
        #expect(store.nudgeButton(for: 1) == .wait(until: ready))
        #expect(!store.nudge(seat: 1))
        clock.now = ready
        #expect(store.nudgeButton(for: 1) == .ready)
        #expect(store.nudge(seat: 1))
        #expect(store.nudgeButton(for: 1) == .sending)
        #expect(!store.nudge(seat: 1))
        await store.settle()
        #expect(socket.calls.sends == [.nudge(seat: 1)])

        store.handle(.message(.nudgeSent(seat: 1)))
        #expect(store.nudgePending == nil)
        #expect(store.nudgeButton(for: 1) == .sent)
        #expect(store.room?.nudge?.sent == true)
    }

    @Test func noButtonForAnyoneTheServerDoesntOffer() throws {
        let (store, _, _) = try make(room())
        // This phone's own seat, a seat that isn't on the move, one out of range.
        #expect(store.nudgeButton(for: 0) == nil)
        #expect(store.nudgeButton(for: 7) == nil)
        // A server without nudges, or with nobody to nudge.
        let (off, _, _) = try make(room(nudge: nil))
        #expect(off.nudgeButton(for: 1) == nil)
        #expect(off.nudgeReadyAt == nil)
        #expect(!off.nudge(seat: 1))
        // Not mid-round.
        var over = try room()
        over.game?.status = .roundOver
        let (between, _, _) = make(over)
        #expect(between.nudgeButton(for: 1) == nil)
    }

    @Test func aRefusalOnlyClearsTheSendAndNopesNothing() async throws {
        let (store, _, _) = try make(room(nudge: NudgeView(seat: 1)))
        var nopes = 0
        let watch = Task { for await intent in store.intents { if case .lobbyNope = intent { nopes += 1 } } }
        #expect(store.nudge(seat: 1))
        store.handle(.message(.error(.tooSoon)))
        #expect(store.nudgePending == nil)
        #expect(store.nudgeButton(for: 1) == .ready)
        // With nothing pending, an error is a lobby nope as before.
        store.handle(.message(.error(.notTheirTurn)))
        await store.close()
        await watch.value
        #expect(nopes == 1)
    }

    @Test func aSendThatNeverLeftComesBack() async throws {
        let (store, socket, _) = try make(room(nudge: NudgeView(seat: 1)))
        socket.failSends(of: [.nudge(seat: 1)])
        #expect(store.nudge(seat: 1))
        await store.settle()
        #expect(store.nudgePending == nil)
        #expect(store.nudgeButton(for: 1) == .ready)
    }

    @Test func theMoveGoingOnEndsThePendingNudge() throws {
        let (store, _, _) = try make(room(nudge: NudgeView(seat: 1)))
        #expect(store.nudge(seat: 1))
        var next = try room(nudge: nil)
        next.game?.turn = 0
        store.handle(snapshot(next, seq: 6))
        #expect(store.nudgePending == nil)
        #expect(store.nudgeReadyAt == nil)
    }

    @Test func aSentSnapshotAfterAReconnectShowsSent() throws {
        let (store, _, _) = try make(room(nudge: NudgeView(seat: 1)))
        #expect(store.nudge(seat: 1))
        store.handle(snapshot(try room(nudge: NudgeView(seat: 1, sent: true)), seq: 6))
        #expect(store.nudgePending == nil)
        #expect(store.nudgeButton(for: 1) == .sent)
    }

    @Test func aNudgeForThisPhoneBecomesANotice() throws {
        let (store, _, _) = try make(room())
        // Seat 1 isn't this phone's: nothing.
        store.handle(.message(.nudged(seat: 1, from: 0)))
        #expect(store.nudgeNotice == nil)
        store.handle(.message(.nudged(seat: 0, from: 1)))
        #expect(store.nudgeNotice == RoomStore.NudgeNotice(seat: 0, from: 1, serial: 1))
        store.handle(.message(.nudged(seat: 0, from: 1)))
        #expect(store.nudgeNotice?.serial == 2)
    }

    @Test func aNudgeSentForAnotherSeatChangesNothing() throws {
        let (store, _, _) = try make(room(nudge: NudgeView(seat: 1)))
        store.handle(.message(.nudgeSent(seat: 0)))
        #expect(store.nudgeButton(for: 1) == .ready)
    }
}
