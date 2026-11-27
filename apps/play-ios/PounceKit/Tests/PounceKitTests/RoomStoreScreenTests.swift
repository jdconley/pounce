import Foundation
import Testing
@testable import PounceKit

/// A TV's store (`role: .screen`, docs/tv-protocol.md "A screen"): it connects with `?role=screen`,
/// goes home for good when the room won't take it, sends nothing of its own, and shows the aims
/// the server relays.
@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStoreScreenTests {
    private let config = APIConfig(baseURL: URL(string: "http://localhost:8787")!)
    private let credential = DeviceCredential(deviceId: "tv-1", token: "tok-tv")

    /// The play-api's screen fixture, as a screen sees it: a TV table where no seat is this device's.
    private func screenRoom() throws -> RoomView {
        let data = try Data(contentsOf: Fixtures.url("protocol/screen-server-messages.json"))
        let all = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let message = try #require(all["snapshot"] as? [String: Any])
        let text = String(data: try JSONSerialization.data(withJSONObject: message), encoding: .utf8)!
        guard case .snapshot(_, _, var room) = try Codec.decode(text) else { throw Fixtures.FixtureError.malformed("snapshot") }
        for i in room.seats.indices { room.seats[i].yours = false }
        room.youAreHost = false
        #expect(room.screen == true)
        return room
    }

    /// `eventually`, on the main actor with the store.
    private func soon(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<5_000 {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .microseconds(200))
        }
        return condition()
    }

    private func store(_ connector: FakeConnector, role: RoomRole? = .screen) -> RoomStore {
        let credential = credential
        return RoomStore(code: "BCDFG", config: config, role: role, credential: { credential }, connector: connector)
    }

    // MARK: connecting

    @Test func theSocketAsksForTheScreenRole() async throws {
        let conn = FakeConnection()
        let connector = FakeConnector([.connection(conn)])
        let store = store(connector)
        let run = Task { await store.run() }

        #expect(await soon { store.connected })
        let url = try #require(connector.calls.first?.url)
        #expect(url == config.socketURL(code: "BCDFG", role: .screen))
        #expect(url.absoluteString == "ws://localhost:8787/v1/rooms/BCDFG/ws?role=screen")
        #expect(connector.calls.map(\.token) == ["tok-tv"])
        #expect(store.isScreen)

        await store.close()
        await run.value
    }

    @Test func aPhoneStoreAsksForNoRole() async throws {
        let connector = FakeConnector([.connection(FakeConnection())])
        let store = store(connector, role: nil)
        let run = Task { await store.run() }

        #expect(await soon { store.connected })
        #expect(connector.calls.first?.url.absoluteString == "ws://localhost:8787/v1/rooms/BCDFG/ws")
        #expect(!store.isScreen)

        await store.close()
        await run.value
    }

    /// 403 `not_screen`, 409 `seated` and 404 all send the TV home: terminal, never retried.
    @Test(arguments: [SocketConnectError.forbidden, .conflict, .notFound])
    func aRoomThatWontTakeTheScreenIsNotFoundForGood(_ refusal: SocketConnectError) async throws {
        let connector = FakeConnector([.failure(refusal), .connection(FakeConnection())])
        let store = store(connector)

        await store.run()  // returns only once the socket has stopped for good

        #expect(store.phase == .notFound)
        #expect(!store.connected)
        #expect(connector.calls.count == 1, "no reconnect")
    }

    /// The same statuses on a phone's socket are only a failed connect, retried as they always were.
    @Test(arguments: [SocketConnectError.forbidden, .conflict])
    func aPhoneSocketStillRetriesThem(_ refusal: SocketConnectError) async throws {
        let connector = FakeConnector([.failure(refusal), .connection(FakeConnection())])
        let sleeper = FakeSleeper()
        let credential = credential
        let socket = RoomSocket(
            code: "BCDFG", config: config, credential: { credential }, connector: connector,
            tick: sleeper.pingInterval, sleep: { try await sleeper.sleep($0) })
        var reader = EventReader(socket.events)

        await socket.start()

        #expect(await reader.next(4) == [.connecting, .disconnected, .connecting, .connected])
        #expect(sleeper.backoffs == [.milliseconds(250)])
        await socket.stop()
    }

    /// Purrtrait: a phone that brought a TV's key and got 403 stops, and says it wasn't near.
    @Test func aPhoneWithAKeyThatIsRefusedStops() async throws {
        let connector = FakeConnector([.failure(.forbidden), .connection(FakeConnection())])
        let sleeper = FakeSleeper()
        let credential = credential
        let socket = RoomSocket(
            code: "BCDFG", config: config, near: "ZZZZZZZZ", credential: { credential }, connector: connector,
            tick: sleeper.pingInterval, sleep: { try await sleeper.sleep($0) })
        var reader = EventReader(socket.events)
        await socket.start()
        #expect(await reader.next(2) == [.connecting, .forbidden(.notNear)])
        #expect(connector.calls.count == 1, "no reconnect")
    }

    @Test func notScreenAfterADropIsStillTerminal() async throws {
        // Linked once, then the room stops listing the TV (a new table, or it was unlinked).
        let first = FakeConnection()
        let connector = FakeConnector([.connection(first), .failure(.forbidden), .connection(FakeConnection())])
        let sleeper = FakeSleeper()
        let credential = credential
        let socket = RoomSocket(
            code: "BCDFG", config: config, role: .screen, credential: { credential }, connector: connector,
            tick: sleeper.pingInterval, sleep: { try await sleeper.sleep($0) })
        var reader = EventReader(socket.events)

        await socket.start()
        #expect(await reader.next(2) == [.connecting, .connected])
        first.drop()

        #expect(await reader.rest() == [.disconnected, .connecting, .notFound])
        #expect(connector.calls.count == 2)
        #expect(connector.calls.allSatisfy { $0.url.query() == "role=screen" })
    }

    // MARK: watching

    private func watching() throws -> (RoomStore, FakeSocket) {
        let socket = FakeSocket()
        let store = RoomStore(code: "BCDFG", socket: socket, role: .screen)
        store.handle(.connected)
        store.handle(.message(.snapshot(protocol: 1, seq: 1, room: try screenRoom())))
        return (store, socket)
    }

    @Test func aScreenSendsNothingOfItsOwn() async throws {
        let (store, socket) = try watching()
        #expect(store.phase == .playing)

        store.send(.presence(.active))
        store.send(.presence(.background))
        store.send(.start)
        store.send(.claim(seat: 0, person: Person(id: "p-1", name: "Ada", cat: 1)))
        #expect(!store.act(seat: 0, .discard(card: 46, skipTarget: nil)))
        #expect(!store.actTiles(seat: 0, .pass))
        store.aim(seat: 0, .target(seat: 1, group: 0))
        store.aim(seat: 0, nil)
        let turn = try #require(store.room?.liveTurn)
        #expect(store.nudgeButton(for: turn) == nil)
        #expect(!store.nudge(seat: turn))
        #expect(!store.canRetire(seat: turn))
        #expect(!store.retire(seat: turn))
        await store.settle()

        #expect(socket.calls.sends.isEmpty, "\(socket.calls.sends)")
        #expect(!store.actionInFlight)
    }

    @Test func aPhoneStoreStillSendsPresence() async throws {
        let socket = FakeSocket()
        let store = RoomStore(code: "BCDFG", socket: socket)
        store.handle(.message(.snapshot(protocol: 1, seq: 1, room: try screenRoom())))
        store.send(.presence(.active))
        await store.settle()
        #expect(socket.calls.sends == [.presence(.active)])
    }

    @Test func aScreenShowsTheAimsTheServerRelays() throws {
        let (store, _) = try watching()
        #expect(store.aims.isEmpty)

        store.handle(.message(.aim(seat: 0, aim: .target(seat: 1, group: 0))))
        #expect(store.aims == [0: .target(seat: 1, group: 0)])

        store.handle(.message(.aim(seat: 1, aim: .table([[82, 45, 87]]))))
        #expect(store.aims[1] == .table([[82, 45, 87]]))

        store.handle(.message(.aim(seat: 0, aim: nil)))
        #expect(store.aims == [1: .table([[82, 45, 87]])])
    }

    @Test func aScreenThatWasTurnedAwayIgnoresWhatFollows() throws {
        let (store, _) = try watching()
        store.handle(.notFound)
        store.handle(.message(.aim(seat: 0, aim: .target(seat: 1, group: 0))))
        #expect(store.phase == .notFound)
        #expect(store.aims.isEmpty)
    }
}
