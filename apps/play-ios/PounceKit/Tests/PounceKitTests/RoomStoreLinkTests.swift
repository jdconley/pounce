import Foundation
import Testing
@testable import PounceKit

/// The bad connection indicator in the store: this phone's connection, a move that stays
/// pending until the server acks it (sent again, same id, after a reconnect), and the seats' links.
@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStoreLinkTests {
    private let discard: Action = .discard(card: 46, skipTarget: nil)

    private func room(link: RoomLink? = RoomLink(ping: 3000)) throws -> RoomView {
        let json = try #require(try Fixtures.serverMessages().first { $0.name == "snapshot-playing-with-hand" }).json
        guard case .snapshot(_, _, var room) = try Codec.decode(json) else { throw Fixtures.FixtureError.malformed("snapshot") }
        room.game?.turn = 0
        room.link = link
        return room
    }

    private func snapshot(_ room: RoomView, seq: Int) -> SocketEvent {
        .message(.snapshot(protocol: 1, seq: seq, room: room))
    }

    /// A playing store whose move ids count up: m1, m2, ...
    private func store(link: RoomLink? = RoomLink(ping: 3000)) throws -> (RoomStore, FakeSocket, RoomView) {
        let socket = FakeSocket()
        var next = 0
        let store = RoomStore(code: "BCDFG", socket: socket) {
            next += 1
            return "m\(next)"
        }
        let room = try room(link: link)
        store.handle(.connected)
        store.handle(snapshot(room, seq: 5))
        return (store, socket, room)
    }

    private func acked(_ room: RoomView, _ ids: [String]) -> RoomView {
        var next = room
        next.link?.acks = ids
        return next
    }

    @Test func connectionFollowsTheSocket() throws {
        let (store, _, _) = try store()
        #expect(store.connection == .good)
        store.handle(.link(.weak))
        #expect(store.connection == .weak)
        store.handle(.disconnected)
        #expect(store.connection == .reconnecting)
        store.handle(.connecting)
        #expect(store.connection == .reconnecting)
        // A new connection starts good, whatever the old one was.
        store.handle(.connected)
        #expect(store.connection == .good)
        store.handle(.link(.weak))
        store.handle(.link(.good))
        #expect(store.connection == .good)
    }

    @Test func aMoveCarriesAnIdAndStaysPendingUntilAcked() async throws {
        let (store, socket, room) = try store()
        #expect(store.act(seat: 0, discard))
        await store.settle()
        #expect(socket.calls.sends == [.act(seat: 0, action: discard, id: "m1")])
        #expect(store.pendingMove?.id == "m1")

        // Another phone's change: not this move's answer.
        store.handle(snapshot(room, seq: 6))
        #expect(store.actionInFlight)
        #expect(store.pendingMove?.id == "m1")
        #expect(!store.act(seat: 0, .draw(.deck)))

        store.handle(snapshot(acked(room, ["m1"]), seq: 7))
        #expect(!store.actionInFlight)
        #expect(store.pendingMove == nil)
    }

    @Test func aMoveLostWithItsSocketGoesAgainAfterTheReconnectSnapshot() async throws {
        let (store, socket, room) = try store()
        store.act(seat: 0, discard)
        await store.settle()
        store.handle(.disconnected)
        store.handle(.connecting)
        store.handle(.connected)
        // The reconnect snapshot doesn't have it: it never got there. Same id, sent once more.
        store.handle(snapshot(room, seq: 5))
        await store.settle()
        #expect(socket.calls.sends == [.act(seat: 0, action: discard, id: "m1"), .act(seat: 0, action: discard, id: "m1")])
        #expect(store.actionInFlight)
        #expect(store.pendingMove?.id == "m1")
        // A second snapshot on the same connection doesn't send it a third time.
        store.handle(snapshot(room, seq: 5))
        await store.settle()
        #expect(socket.calls.sends.count == 2)

        store.handle(snapshot(acked(room, ["m1"]), seq: 6))
        #expect(store.pendingMove == nil)
        #expect(!store.actionInFlight)
    }

    @Test func aMoveThatGotThroughBeforeTheDropIsNotSentAgain() async throws {
        let (store, socket, room) = try store()
        store.act(seat: 0, discard)
        await store.settle()
        store.handle(.disconnected)
        store.handle(.connected)
        store.handle(snapshot(acked(room, ["m0", "m1"]), seq: 6))
        await store.settle()
        #expect(socket.calls.sends == [.act(seat: 0, action: discard, id: "m1")])
        #expect(store.pendingMove == nil)
        #expect(!store.actionInFlight)
    }

    @Test func aMoveMadeWhileTheSocketIsDownWaitsForIt() async throws {
        let (store, socket, room) = try store()
        socket.failSends(of: [.act(seat: 0, action: discard, id: "m1")])
        #expect(store.act(seat: 0, discard))
        await store.settle()
        // Not rolled back: it goes once the socket is back.
        #expect(store.actionInFlight)
        #expect(store.pendingMove?.id == "m1")
        socket.failSends(of: [])
        store.handle(.connected)
        store.handle(snapshot(room, seq: 5))
        await store.settle()
        #expect(socket.calls.sends == [.act(seat: 0, action: discard, id: "m1")])
        let intents = await allIntents(store)
        #expect(!intents.contains(.rejected(.notSent)))
    }

    @Test func aRefusedMoveIsNoLongerPending() async throws {
        let (store, _, _) = try store()
        store.act(seat: 0, discard)
        store.handle(.message(.error(.notYourTurn)))
        #expect(store.pendingMove == nil)
        #expect(!store.actionInFlight)
    }

    @Test func withoutLinksAnySnapshotReleasesAsBefore() async throws {
        let (store, socket, room) = try store(link: nil)
        store.act(seat: 0, discard)
        await store.settle()
        #expect(socket.calls.sends == [.act(seat: 0, action: discard)])
        #expect(store.pendingMove == nil)
        store.handle(snapshot(room, seq: 6))
        #expect(!store.actionInFlight)
    }

    @Test func aServerThatLostLinksReleasesAPendingMove() async throws {
        let (store, _, room) = try store()
        store.act(seat: 0, discard)
        var plain = room
        plain.link = nil
        store.handle(snapshot(plain, seq: 6))
        #expect(store.pendingMove == nil)
        #expect(!store.actionInFlight)
    }

    @Test func seatLinksFoldIntoTheRoomAndRedrawTheSeats() async throws {
        let (store, _, room) = try store()
        store.handle(.message(.link(seats: [nil, .weak])))
        #expect(store.room?.seats.map(\.link) == [nil, .weak] + Array(repeating: nil, count: room.seats.count - 2))
        // The same again: nothing to redraw.
        store.handle(.message(.link(seats: [nil, .weak])))
        // Shorter than the room: the rest are fine.
        store.handle(.message(.link(seats: [])))
        #expect(store.room?.seats.allSatisfy { $0.link == nil } == true)
        store.handle(.message(.pong))
        #expect(await allIntents(store) == [.reconcile, .link, .link])
    }

    @Test func seatLinksBeforeAnySnapshotAreDropped() {
        let socket = FakeSocket()
        let store = RoomStore(code: "BCDFG", socket: socket)
        store.handle(.message(.link(seats: [.lost])))
        #expect(store.room == nil)
    }

    private func allIntents(_ store: RoomStore) async -> [TableIntent] {
        await store.close()
        var out: [TableIntent] = []
        for await intent in store.intents { out.append(intent) }
        return out
    }
}
