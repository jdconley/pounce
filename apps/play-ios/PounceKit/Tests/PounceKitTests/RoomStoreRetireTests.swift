import Foundation
import Testing
@testable import PounceKit

/// Retiring a stalled seat in the store: offered only for the seat the server names, once its
/// wait is over, and sent as `retire`.
@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStoreRetireTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    /// Bob's (seat 1, on another phone) move, two seats; `retire` as the server sent it.
    private func room(retire: RetireView? = RetireView(seat: 1, wait: 60_000)) throws -> RoomView {
        let json = try #require(try Fixtures.serverMessages().first { $0.name == "snapshot-playing-nudge-wait" }).json
        guard case .snapshot(_, _, var room) = try Codec.decode(json) else { throw Fixtures.FixtureError.malformed("snapshot") }
        room.game?.turn = 1
        room.retire = retire
        return room
    }

    private func make(_ room: RoomView) -> (RoomStore, FakeSocket, Clock) {
        let socket = FakeSocket()
        let clock = Clock()
        let store = RoomStore(code: "BCDFG", socket: socket, clock: { clock.now })
        store.handle(.connected)
        store.handle(.message(.snapshot(protocol: 1, seq: 5, room: room)))
        return (store, socket, clock)
    }

    @Test func theServersSnapshotCarriesTheSeatAndItsWait() throws {
        let json = try #require(try Fixtures.serverMessages().first { $0.name == "snapshot-playing-nudge-wait" }).json
        guard case .snapshot(_, _, let room) = try Codec.decode(json) else { throw Fixtures.FixtureError.malformed("snapshot") }
        let retire = try #require(room.retire)
        #expect(retire.seat == 1)
        #expect(retire.wait > 0)
    }

    @Test func itWaitsOutTheServersWaitThenRetires() async throws {
        let (store, socket, clock) = try make(room())
        #expect(!store.canRetire(seat: 1))
        #expect(!store.retire(seat: 1))
        clock.now = clock.now.addingTimeInterval(60)
        #expect(store.canRetire(seat: 1))
        #expect(store.retire(seat: 1))
        await store.settle()
        #expect(socket.calls.sends == [.retire(seat: 1)])
    }

    @Test func nobodyTheServerDoesntOffer() throws {
        // No offer at all (an older server, or nobody to retire).
        var (store, _, _) = try make(room(retire: nil))
        #expect(!store.canRetire(seat: 1))
        #expect(store.retireReadyAt == nil)
        // Another seat than the one offered, and this phone's own.
        (store, _, _) = try make(room(retire: RetireView(seat: 1, wait: 0)))
        #expect(store.canRetire(seat: 1))
        #expect(!store.canRetire(seat: 0))
        #expect(!store.canRetire(seat: 7))
        // The move went on: the offer goes with the next snapshot.
        var next = try room(retire: nil)
        next.game?.turn = 0
        store.handle(.message(.snapshot(protocol: 1, seq: 6, room: next)))
        #expect(!store.canRetire(seat: 1))
    }
}
