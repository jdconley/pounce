import Foundation
import Testing
@testable import PounceKit

@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStoreLookTests {
    private func playing() throws -> (RoomStore, FakeSocket, RoomView) {
        let socket = FakeSocket()
        let store = RoomStore(code: "BCDFG", socket: socket)
        let json = try #require(try Fixtures.serverMessages().first { $0.name == "snapshot-playing-with-hand" }).json
        guard case .snapshot(_, _, var room) = try Codec.decode(json) else { throw Fixtures.FixtureError.malformed("snap") }
        room.look = .standard
        store.handle(.connected)
        store.handle(.message(.snapshot(protocol: 1, seq: 5, room: room)))
        return (store, socket, room)
    }

    @Test func lookEventChangesTheRoomAndFoldsInLikePresence() throws {
        let (store, socket, _) = try playing()
        let crown = Look(rug: "rug-night-sky", back: "back-crown")
        store.handle(.message(.event(seq: 6, event: .look(seat: 1, look: crown))))
        #expect(store.room?.look == crown)
        #expect(store.lastSeq == 6 && store.settledSeq == 6)
        #expect(store.lookChange == RoomStore.LookChange(seat: 1, look: crown, serial: 1))
        // The next game event still applies (no gap).
        store.handle(.message(.event(seq: 7, event: .game(.turn(seat: 1)))))
        #expect(store.lastSeq == 7)
        #expect(socket.calls.reconnects == 0)
        store.handle(.message(.event(seq: 8, event: .look(seat: 0, look: .standard))))
        #expect(store.lookChange?.serial == 2)
    }

    @Test func aLookAfterAGapReconnects() async throws {
        let (store, socket, _) = try playing()
        store.handle(.message(.event(seq: 9, event: .look(seat: 1, look: .standard))))
        #expect(store.lookChange == nil)
        await store.settle()
        #expect(socket.calls.reconnects == 1)
    }

    @Test func rematchMessageAndSnapshotSetTheCode() throws {
        let (store, _, room) = try playing()
        #expect(store.rematch == nil)
        store.handle(.message(.rematch(code: "NWCDF")))
        #expect(store.rematch == "NWCDF")
        let (other, _, _) = try playing()
        var over = room
        over.status = .over
        over.rematch = "QRSTV"
        other.handle(.message(.snapshot(protocol: 1, seq: 6, room: over)))
        #expect(other.rematch == "QRSTV")
    }

    @Test func streakMessageGoesToTheHook() throws {
        let (store, _, _) = try playing()
        var heard: [(String, String, Int)] = []
        store.onStreak = { pair, person, view in heard.append((pair, person, view.count)) }
        store.handle(.message(.streak(pair: "pr_x", person: "me", view: streakView("pr_x", count: 3))))
        #expect(heard.count == 1 && heard[0].0 == "pr_x" && heard[0].1 == "me" && heard[0].2 == 3)
        #expect(store.lastSeq == 5, "a streak message has no seq")
    }

    @Test func lookErrorsAreLobbyNopesNotRejections() async throws {
        let (store, _, _) = try playing()
        store.handle(.message(.error(.tooSoon)))
        let intents = await { () async -> [TableIntent] in
            await store.close()
            var out: [TableIntent] = []
            for await i in store.intents { out.append(i) }
            return out
        }()
        #expect(intents.contains(.lobbyNope(.tooSoon)))
    }
}
