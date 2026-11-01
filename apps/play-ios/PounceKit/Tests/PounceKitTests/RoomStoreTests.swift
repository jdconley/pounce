import Foundation
import Synchronization
import Testing
@testable import PounceKit

// MARK: - fakes

/// Records every call the store makes. `send` throws, as a disconnected socket
/// does, for any message listed in `failing` (and records nothing).
final class FakeSocket: RoomSocketing {
    struct Calls: Equatable {
        var starts = 0
        var sends: [ClientMessage] = []
        var reconnects = 0
        var stops = 0
    }

    let events: AsyncStream<SocketEvent>
    let feed: AsyncStream<SocketEvent>.Continuation
    private let state = Mutex(Calls())
    private let failing = Mutex<[ClientMessage]>([])

    init() { (events, feed) = AsyncStream.makeStream(of: SocketEvent.self) }

    var calls: Calls { state.withLock { $0 } }

    func failSends(of messages: [ClientMessage]) { failing.withLock { $0 = messages } }

    func start() async { state.withLock { $0.starts += 1 } }

    func send(_ m: ClientMessage) async throws {
        if failing.withLock({ $0.contains(m) }) { throw RoomSocketError.notConnected }
        state.withLock { $0.sends.append(m) }
    }

    func reconnectNow() async { state.withLock { $0.reconnects += 1 } }

    func stop() async {
        state.withLock { $0.stops += 1 }
        feed.finish()
    }
}

// MARK: - helpers

private func fixture(_ name: String) throws -> ServerMessage {
    let json = try #require(try Fixtures.serverMessages().first { $0.name == name }).json
    return try Codec.decode(json)
}

/// The fixture snapshot's room, for building snapshots with any `seq`.
private func fixtureRoom(_ name: String) throws -> RoomView {
    guard case .snapshot(_, _, let room) = try fixture(name) else {
        Issue.record("\(name) is not a snapshot")
        throw Fixtures.FixtureError.malformed(name)
    }
    return room
}

/// The fixture event's payload, for re-sending it with any `seq`.
private func fixtureEvent(_ name: String) throws -> RoomEvent {
    guard case .event(_, let event) = try fixture(name) else {
        Issue.record("\(name) is not an event")
        throw Fixtures.FixtureError.malformed(name)
    }
    return event
}

private func snapshot(_ room: RoomView, seq: Int) -> SocketEvent {
    .message(.snapshot(protocol: 1, seq: seq, room: room))
}

private func event(_ event: RoomEvent, seq: Int) -> SocketEvent {
    .message(.event(seq: seq, event: event))
}

private func serverError(_ code: ErrorCode) -> SocketEvent { .message(.error(code)) }

private let discard: Action = .discard(card: 46, skipTarget: nil)

/// Closes the store and returns every intent it emitted.
@MainActor private func allIntents(_ store: RoomStore) async -> [TableIntent] {
    await store.close()
    var out: [TableIntent] = []
    for await intent in store.intents { out.append(intent) }
    return out
}

// MARK: - tests

@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStoreTests {
    private func makeStore() -> (RoomStore, FakeSocket) {
        let socket = FakeSocket()
        return (RoomStore(code: "BCDFG", socket: socket), socket)
    }

    /// A store already showing the playing fixture at `seq`, its own seat 0 on turn.
    private func playingStore(seq: Int = 5) async throws -> (RoomStore, FakeSocket, RoomView) {
        let (store, socket) = makeStore()
        var room = try fixtureRoom("snapshot-playing-with-hand")
        room.game?.turn = 0
        store.handle(.connected)
        store.handle(snapshot(room, seq: seq))
        return (store, socket, room)
    }

    @Test func startsConnecting() {
        let (store, _) = makeStore()
        #expect(store.code == "BCDFG")
        #expect(store.phase == .connecting)
        #expect(store.lastSeq == -1)
        #expect(store.room == nil)
        #expect(!store.actionInFlight)
        #expect(!store.connected)
        #expect(store.moveCode == nil)
        #expect(store.lastError == nil)
    }

    @Test func snapshotWithEqualSeqIsApplied() async throws {
        let (store, _) = makeStore()
        let first = try fixtureRoom("snapshot-playing-with-hand")
        var second = first
        second.game?.turn = 0
        second.game?.deckCount = 70
        let turn = try fixtureEvent("event-turn")

        store.handle(snapshot(first, seq: 5))
        store.handle(event(turn, seq: 6))
        store.handle(snapshot(second, seq: 6))

        #expect(store.room == second)
        #expect(store.lastSeq == 6)
        #expect(store.phase == .playing)
        let intents = await allIntents(store)
        #expect(intents == [.reconcile, .game(.turn(seat: 0), seq: 6), .reconcile])
        #expect(intents.last == .reconcile)
    }

    @Test func eventGapRequestsReconnect() async throws {
        let (store, socket, room) = try await playingStore(seq: 5)
        store.handle(event(try fixtureEvent("event-turn"), seq: 7))
        await store.settle()

        #expect(socket.calls.reconnects == 1)
        #expect(store.lastSeq == 5)
        #expect(store.room == room)
        #expect(await allIntents(store) == [.reconcile])
    }

    @Test func staleEventIgnored() async throws {
        let (store, socket, room) = try await playingStore(seq: 5)
        store.handle(event(try fixtureEvent("event-turn"), seq: 5))
        store.handle(event(try fixtureEvent("event-presence"), seq: 4))
        await store.settle()

        #expect(store.lastSeq == 5)
        #expect(store.room == room)
        #expect(socket.calls.reconnects == 0)
        #expect(await allIntents(store) == [.reconcile])
    }

    @Test func presenceEventUpdatesSeat() async throws {
        let (store, _, room) = try await playingStore(seq: 1)
        store.handle(.message(try fixture("event-presence")))  // seq 2: seat 1 away

        var expected = room
        expected.seats[1].presence = .away
        #expect(store.room == expected)
        #expect(store.lastSeq == 2)
        #expect(await allIntents(store) == [.reconcile, .presence(seat: 1, presence: .away)])
    }

    @Test func gameEventsUpdateWhatTheyCarry() async throws {
        let (store, _, room) = try await playingStore(seq: 11)
        store.handle(.message(try fixture("event-turn")))  // seq 12: seat 0
        #expect(store.room?.game?.turn == 0)
        #expect(store.room?.game?.step == .draw)

        store.handle(event(try fixtureEvent("event-roundOver"), seq: 13))
        #expect(store.room?.game?.status == .roundOver)
        store.handle(event(try fixtureEvent("event-gameOver"), seq: 14))
        #expect(store.room?.game?.status == .gameOver)

        store.handle(event(try fixtureEvent("event-reshuffled"), seq: 15))
        var expected = room
        expected.game?.turn = 0
        expected.game?.step = .draw
        expected.game?.status = .gameOver
        #expect(store.room == expected)  // the snapshot after the action carries the deck count
        #expect(store.lastSeq == 15)
        #expect(store.phase == .playing)
    }

    @Test func snapshotAfterActionCarriesTheDrawnCard() async throws {
        let (store, _, room) = try await playingStore(seq: 5)
        #expect(store.act(seat: 0, .draw(.deck)))
        let drew = GameEvent.drew(seat: 0, from: .deck, card: 17)
        store.handle(event(.game(drew), seq: 6))

        var after = room
        after.game?.step = .play
        after.game?.deckCount -= 1
        after.game?.handCounts[0] += 1
        after.game?.hands[0]?.append(17)
        store.handle(snapshot(after, seq: 6))

        #expect(store.room == after)
        #expect(store.room?.game?.hands[0]?.contains(17) == true)
        #expect(store.room?.game?.step == .play)
        #expect(!store.actionInFlight)
        #expect(store.lastSeq == 6)
        let intents = await allIntents(store)
        #expect(Array(intents.suffix(2)) == [.game(drew, seq: 6), .reconcile])
    }

    @Test func lobbyToPlayingEmitsVersusIntro() async throws {
        let (store, _) = makeStore()
        store.handle(.message(try fixture("snapshot-lobby")))  // seq 3
        #expect(store.phase == .lobby)
        store.handle(.message(try fixture("snapshot-playing-with-hand")))  // seq 4
        #expect(store.phase == .playing)
        store.handle(snapshot(try fixtureRoom("snapshot-playing-with-hand"), seq: 4))

        #expect(await allIntents(store) == [.reconcile, .versusIntro, .reconcile, .reconcile])
    }

    @Test func firstSnapshotPlayingHasNoIntro() async throws {
        let (store, _) = makeStore()
        store.handle(.message(try fixture("snapshot-playing-with-hand")))
        #expect(await allIntents(store) == [.reconcile])
    }

    @Test func overRoomSetsOverPhase() throws {
        let (store, _) = makeStore()
        var room = try fixtureRoom("snapshot-playing-with-hand")
        room.status = .over
        store.handle(snapshot(room, seq: 9))
        #expect(store.phase == .over)
    }

    @Test func secondActWhileInFlightIsRefused() async throws {
        let (store, socket, _) = try await playingStore()
        #expect(store.act(seat: 0, discard))
        #expect(store.actionInFlight)
        #expect(!store.act(seat: 0, .draw(.deck)))
        await store.settle()

        #expect(socket.calls.sends == [.act(seat: 0, action: discard)])
        #expect(store.actionInFlight)
    }

    @Test func actOutsidePlayIsRefused() async throws {
        let (store, socket) = makeStore()
        #expect(!store.act(seat: 0, discard))  // connecting
        store.handle(.message(try fixture("snapshot-lobby")))
        #expect(!store.act(seat: 0, discard))  // lobby
        await store.settle()

        #expect(socket.calls.sends.isEmpty)
        #expect(!store.actionInFlight)
    }

    @Test func gameEventClearsInFlight() async throws {
        let (store, _, _) = try await playingStore(seq: 8)
        store.act(seat: 0, discard)
        store.handle(.message(try fixture("event-discarded")))  // seq 9
        #expect(!store.actionInFlight)
        #expect(store.act(seat: 0, .draw(.deck)))
    }

    @Test func presenceEventKeepsInFlight() async throws {
        let (store, _, _) = try await playingStore(seq: 1)
        store.act(seat: 0, discard)
        store.handle(.message(try fixture("event-presence")))  // seq 2
        #expect(store.actionInFlight)
    }

    @Test func failedSendClearsInFlight() async throws {
        let (store, socket, _) = try await playingStore()
        socket.failSends(of: [.act(seat: 0, action: discard)])
        #expect(store.act(seat: 0, discard))
        await store.settle()

        #expect(!store.actionInFlight)
        #expect(socket.calls.sends.isEmpty)
        #expect(await allIntents(store) == [.reconcile])  // no rejection for a send that never left
    }

    @Test func staleSendFailureKeepsNewerLock() async throws {
        let (store, socket, room) = try await playingStore(seq: 5)
        socket.failSends(of: [.act(seat: 0, action: discard)])
        store.act(seat: 0, discard)
        store.handle(snapshot(room, seq: 5))  // clears the first lock before its send fails
        #expect(store.act(seat: 0, .draw(.deck)))
        await store.settle()

        // The first send's failure must not release the second act's lock.
        #expect(socket.calls.sends == [.act(seat: 0, action: .draw(.deck))])
        #expect(store.actionInFlight)
    }

    @Test func errorWhileInFlightRejects() async throws {
        let (store, _, _) = try await playingStore()
        store.act(seat: 0, discard)
        store.handle(serverError(.notYourTurn))

        #expect(!store.actionInFlight)
        #expect(store.lastError == .notYourTurn)
        #expect(await allIntents(store) == [.reconcile, .rejected(.notYourTurn)])
    }

    @Test func lobbyErrorNopes() async throws {
        let (store, _) = makeStore()
        store.handle(.message(try fixture("snapshot-lobby")))
        store.send(.start)
        store.handle(serverError(.seatsOpen))

        #expect(!store.actionInFlight)
        #expect(store.lastError == .seatsOpen)
        #expect(await allIntents(store) == [.reconcile, .lobbyNope(.seatsOpen)])
    }

    @Test func sendNeverLocks() async throws {
        let (store, socket) = makeStore()
        store.handle(.message(try fixture("snapshot-lobby")))
        store.send(.configure(seat: 2, kind: .bot))
        store.send(.start)
        await store.settle()

        #expect(!store.actionInFlight)
        #expect(socket.calls.sends == [.configure(seat: 2, kind: .bot), .start])
    }

    @Test func sendsKeepTheirOrder() async throws {
        let (store, socket, _) = try await playingStore()
        var expected: [ClientMessage] = []
        for i in 0..<30 {
            let message: ClientMessage = i.isMultiple(of: 2) ? .presence(.active) : .moveSeat(seat: i % 6)
            store.send(message)
            expected.append(message)
        }
        store.act(seat: 0, discard)
        expected.append(.act(seat: 0, action: discard))
        store.send(.presence(.background))
        expected.append(.presence(.background))
        await store.settle()

        #expect(socket.calls.sends == expected)
    }

    @Test func inFlightClearsOnReconnectSnapshot() async throws {
        let (store, socket, room) = try await playingStore(seq: 5)
        store.act(seat: 0, .draw(.deck))
        store.handle(event(.game(.drew(seat: 0, from: .deck, card: 17)), seq: 6))
        #expect(store.act(seat: 0, discard))

        store.handle(.disconnected)
        #expect(!store.connected)
        #expect(store.actionInFlight)  // kept until the reconnect snapshot

        store.handle(.connecting)
        store.handle(.connected)
        #expect(store.connected)
        var after = room
        after.game?.step = .play
        after.game?.hands[0]?.append(17)
        store.handle(snapshot(after, seq: 6))  // same seq as the last event

        #expect(!store.actionInFlight)
        #expect(store.room == after)
        #expect(store.lastSeq == 6)
        #expect(store.act(seat: 0, .discard(card: 17, skipTarget: nil)))
        await store.settle()
        #expect(socket.calls.sends.count == 3)
    }

    @Test func moveCodeIsKept() throws {
        let (store, _) = makeStore()
        store.handle(.message(try fixture("moveCode")))
        #expect(store.moveCode == MoveCode(seat: 1, code: "BCDFGH"))
        store.handle(.message(.moveCode(seat: 3, code: "ZZZZZZ")))
        #expect(store.moveCode == MoveCode(seat: 3, code: "ZZZZZZ"))
    }

    @Test func roomClosedIsTerminal() async throws {
        let (store, socket, room) = try await playingStore()
        store.act(seat: 0, discard)
        store.handle(.message(try fixture("error-room_closed")))
        await store.settle()

        #expect(store.phase == .closed)
        #expect(store.lastError == .roomClosed)
        #expect(socket.calls.stops == 1)

        store.handle(.closed)
        store.handle(snapshot(room, seq: 9))
        #expect(store.phase == .closed)
        #expect(store.lastSeq == 5)
    }

    @Test func botStalledShowsStalled() async throws {
        let (store, socket, _) = try await playingStore()
        store.handle(serverError(.botStalled))
        await store.settle()

        #expect(store.phase == .stalled)
        #expect(store.lastError == .botStalled)
        #expect(socket.calls.stops == 0)  // keep the socket
        #expect(await allIntents(store) == [.reconcile])
    }

    @Test func wrongProtocolNeedsUpdate() async throws {
        let (store, socket) = makeStore()
        store.handle(.message(.snapshot(protocol: 2, seq: 1, room: try fixtureRoom("snapshot-lobby"))))
        await store.settle()

        #expect(store.phase == .needsUpdate)
        #expect(store.room == nil)
        #expect(store.lastSeq == -1)
        #expect(socket.calls.stops == 1)

        store.handle(.closed)
        #expect(store.phase == .needsUpdate)
    }

    @Test func unsupportedProtocolNeedsUpdate() async throws {
        let (store, socket) = makeStore()
        let future = #"{"t":"snapshot","protocol":2,"seq":1,"room":{"shape":"new"}}"#
        store.handle(.message(try Codec.decode(future)))
        await store.settle()

        #expect(store.phase == .needsUpdate)
        #expect(store.room == nil)
        #expect(socket.calls.stops == 1)
    }

    @Test func notFoundAndClosedSocketEvents() {
        let (a, _) = makeStore()
        a.handle(.notFound)
        #expect(a.phase == .notFound)

        let (b, _) = makeStore()
        b.handle(.closed)
        #expect(b.phase == .closed)
    }

    @Test func runConsumesSocketEventsUntilTheStreamEnds() async throws {
        let (store, socket) = makeStore()
        let room = try fixtureRoom("snapshot-lobby")
        socket.feed.yield(.connecting)
        socket.feed.yield(.connected)
        socket.feed.yield(snapshot(room, seq: 3))
        socket.feed.finish()

        await store.run()

        #expect(socket.calls.starts == 1)
        #expect(store.connected)
        #expect(store.room == room)
        #expect(store.phase == .lobby)
    }
}
