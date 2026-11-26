#if DEBUG
import Foundation
import Testing
@testable import PounceKit

/// The store in a Birdwatch room: moves go out in the `act` envelope, events arrive under their
/// own kind, the turn folds in for timing, and a House Cat taking a seat is noticed.
@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStoreBirdwatchTests {
    static func room(_ name: String) throws -> RoomView {
        let json = try #require(try Fixtures.birdwatchServerMessages().first { $0.name == name }).json
        guard case .snapshot(_, _, let room) = try Codec.decode(json) as ServerMessage else {
            throw Fixtures.FixtureError.malformed(name)
        }
        return room
    }

    private func snapshot(_ room: RoomView, seq: Int) -> SocketEvent {
        .message(.snapshot(protocol: 1, seq: seq, room: room))
    }

    private func store(_ room: RoomView, link: Bool = false) -> (RoomStore, FakeSocket) {
        let socket = FakeSocket()
        var next = 0
        let store = RoomStore(code: room.code, socket: socket) {
            next += 1
            return "m\(next)"
        }
        var room = room
        if link { room.link = RoomLink(ping: 3000) }
        store.handle(.connected)
        store.handle(snapshot(room, seq: 5))
        return (store, socket)
    }

    private func intents(_ store: RoomStore) async -> [TableIntent] {
        await store.close()
        var out: [TableIntent] = []
        for await intent in store.intents { out.append(intent) }
        return out
    }

    @Test func aBirdwatchSnapshotIsAPlayingRoom() throws {
        let (store, _) = store(try Self.room("snapshot-bidding-your-move"))
        #expect(store.phase == .playing)
        #expect(store.room?.isBirdwatch == true)
        #expect(store.pass.state == .revealed(1))
    }

    @Test func aMoveGoesOutAsAnActAndLocksUntilItsSnapshot() async throws {
        let (store, socket) = store(try Self.room("snapshot-play-follow"))
        #expect(store.actBirdwatch(seat: 1, .play(13)))
        #expect(store.actionInFlight)
        #expect(!store.actBirdwatch(seat: 1, .play(4)))
        await store.settle()
        #expect(socket.calls.sends == [.actBirdwatch(seat: 1, action: .play(13))])
        store.handle(snapshot(try Self.room("snapshot-play-after-trick"), seq: 7))
        #expect(!store.actionInFlight)
    }

    @Test func refusedPlayUnlocks() async throws {
        let (store, _) = store(try Self.room("snapshot-play-follow"))
        #expect(store.actBirdwatch(seat: 1, .play(13)))
        store.handle(.message(.error(.mustFollow)))
        #expect(!store.actionInFlight)
        #expect(store.lastError == .mustFollow)
        #expect(await intents(store).last == .rejected(.mustFollow))
    }

    @Test func aMoveWithLinksCarriesAnId() async throws {
        let (store, socket) = store(try Self.room("snapshot-bidding-your-move"), link: true)
        #expect(store.actBirdwatch(seat: 1, .bid(75)))
        await store.settle()
        #expect(socket.calls.sends == [.actBirdwatch(seat: 1, action: .bid(75), id: "m1")])
        #expect(store.pendingMove?.move == .birdwatch(.bid(75)))
    }

    @Test func eventsFoldTheTurnAndStatusAndAnimate() async throws {
        let (store, _) = store(try Self.room("snapshot-bidding-watching"))
        let epoch = store.turnEpoch
        store.handle(.message(.event(seq: 6, event: .birdwatch(.bid(seat: 1, amount: 75)))))
        store.handle(.message(.event(seq: 7, event: .birdwatch(.turn(seat: 2)))))
        #expect(store.room?.birdwatch?.turn == 2)
        #expect(store.turnEpoch > epoch)
        store.handle(.message(.event(seq: 8, event: .birdwatch(.gameOver(winners: [0, 2], scores: [300, 10], reason: .target)))))
        #expect(store.room?.birdwatch?.status == .over)
        #expect(store.room?.liveTurn == nil)
        let all = await intents(store)
        #expect(all.contains(.birdwatch(.bid(seat: 1, amount: 75), seq: 6)))
        #expect(all.contains(.birdwatch(.turn(seat: 2), seq: 7)))
    }

    @Test func aHouseCatTakingASeatIsNoticed() throws {
        let (store, _) = store(try Self.room("snapshot-play-watching"))
        store.handle(.message(.event(seq: 6, event: .houseCat(seat: 2))))
        #expect(store.houseCatNotice?.seat == 2)
        store.handle(.message(.event(seq: 7, event: .houseCat(seat: 3))))
        #expect(store.houseCatNotice == RoomStore.ForfeitNotice(seat: 3, serial: 2))
        // No seat is ever "out" in Birdwatch: the House Cat plays on.
        #expect(store.room?.isOut(2) == false)
    }

    @Test func lobbyMessagesGoOut() async throws {
        let (store, socket) = store(try Self.room("snapshot-lobby"))
        store.send(.setOptions(RoomOptions(rules: .friesen)))
        store.send(.swapSeats(0, 3))
        await store.settle()
        #expect(socket.calls.sends == [.setOptions(RoomOptions(rules: .friesen)), .swapSeats(0, 3)])
    }
}
#endif
