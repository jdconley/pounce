import Foundation
import Synchronization
import Testing
@testable import PounceKit

/// A clock the test moves, and the store's wait for the rest of an aim's 120 ms, which the test
/// releases: nothing here waits in real time.
private func fixtureRoom(_ name: String) throws -> RoomView {
    let json = try #require(try Fixtures.serverMessages().first { $0.name == name }).json
    guard case .snapshot(_, _, let room) = try Codec.decode(json) else { throw Fixtures.FixtureError.malformed(name) }
    return room
}

private final class AimClock: Sendable {
    private let time = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    private let waits = Mutex<[Duration]>([])
    private let gate = Mailbox<Void>()

    var now: Date { time.withLock { $0 } }
    var requested: [Duration] { waits.withLock { $0 } }
    func advance(_ seconds: Double) { time.withLock { $0 = $0.addingTimeInterval(seconds) } }
    func release() { gate.put(()) }

    func sleep(_ duration: Duration) async {
        waits.withLock { $0.append(duration) }
        try? await gate.take()
    }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct RoomStoreAimTests {
    private func makeStore() -> (RoomStore, FakeSocket, AimClock) {
        let socket = FakeSocket()
        let clock = AimClock()
        let store = RoomStore(code: "BCDFG", socket: socket, clock: { clock.now }, aimSleep: { await clock.sleep($0) })
        // A table with a TV: aims go only then.
        if let room = try? room() { store.handle(.message(.snapshot(protocol: 1, seq: 1, room: room))) }
        return (store, socket, clock)
    }

    private func room(turn: Seat = 0) throws -> RoomView {
        var room = try fixtureRoom("snapshot-playing-with-hand")
        room.game?.turn = turn
        room.screen = true
        return room
    }

    private func aims(_ socket: FakeSocket) -> [ClientMessage] {
        socket.calls.sends.filter { if case .aim = $0 { true } else { false } }
    }

    /// Yields up to 1000 times for `done`, then fails the test instead of hanging.
    private func yields(until done: () -> Bool) async throws {
        for _ in 0..<1000 where !done() { await Task.yield() }
        try #require(done(), "never happened")
    }

    private func target(_ group: Int) -> GameAim { .target(seat: 1, group: group) }

    /// Lets the store's queued sends reach the socket.
    private func settled(_ store: RoomStore) async { await store.settle() }

    @Test func theFirstAimGoesAtOnce() async {
        let (store, socket, _) = makeStore()
        store.aim(seat: 0, target(0))
        await settled(store)
        #expect(aims(socket) == [.aim(seat: 0, aim: target(0))])
    }

    @Test func aimsWithin120msSendTheLatestOnceTheWaitIsOver() async throws {
        let (store, socket, clock) = makeStore()
        store.aim(seat: 0, target(0))
        clock.advance(0.03)
        store.aim(seat: 0, target(1))
        clock.advance(0.03)
        store.aim(seat: 0, target(2))
        await settled(store)
        #expect(aims(socket) == [.aim(seat: 0, aim: target(0))], "held back")

        // One wait for the rest of the 120 ms, from the first held aim (30 ms in), however many came.
        try await yields(until: { !clock.requested.isEmpty })
        #expect(clock.requested.count == 1)
        #expect(abs(clock.requested[0] / .milliseconds(90) - 1) < 0.01, "90 ms: \(clock.requested)")
        clock.advance(0.06)
        clock.release()
        try await yields(until: { !store.hasHeldAim })
        await settled(store)
        #expect(aims(socket) == [.aim(seat: 0, aim: target(0)), .aim(seat: 0, aim: target(2))])
    }

    @Test func anAimAfter120msGoesAtOnce() async {
        let (store, socket, clock) = makeStore()
        store.aim(seat: 0, target(0))
        clock.advance(0.12)
        store.aim(seat: 0, target(1))
        await settled(store)
        #expect(aims(socket) == [.aim(seat: 0, aim: target(0)), .aim(seat: 0, aim: target(1))])
        #expect(clock.requested.isEmpty)
    }

    @Test func aClearGoesAtOnceAndCancelsTheHeldAim() async {
        let (store, socket, clock) = makeStore()
        store.aim(seat: 0, target(0))
        clock.advance(0.01)
        store.aim(seat: 0, target(1))
        store.aim(seat: 0, nil)
        await settled(store)
        #expect(aims(socket) == [.aim(seat: 0, aim: target(0)), .aim(seat: 0, aim: nil)])
        #expect(!store.hasHeldAim)
        // Letting the cancelled wait go sends nothing more.
        clock.release()
        clock.advance(1)
        for _ in 0..<50 { await Task.yield() }
        await settled(store)
        #expect(aims(socket).count == 2)
    }

    @Test func tilesAimsLoseTheirEmptySets() async {
        let (store, socket, _) = makeStore()
        store.aim(seat: 1, .table([[1, 2, 3], [], [40, 41]]))
        await settled(store)
        #expect(aims(socket) == [.aim(seat: 1, aim: .table([[1, 2, 3], [40, 41]]))])
    }

    @Test func aTableWithoutATVSendsNoAimAndNoClear() async throws {
        let (store, socket, _) = makeStore()
        var room = try room()
        room.screen = nil
        store.handle(.message(.snapshot(protocol: 1, seq: 2, room: room)))
        store.aim(seat: 0, target(0))
        store.aim(seat: 0, target(1))
        store.aim(seat: 0, nil)
        await settled(store)
        #expect(aims(socket).isEmpty)
        #expect(!store.hasHeldAim)
    }

    @Test func aDraftOverTheLimitsIsNotSentAndTheNextGoodOneIs() async {
        let (store, socket, clock) = makeStore()
        let good: GameAim = .table([[1, 2, 3]])
        store.aim(seat: 1, good)
        let tooMany: [[TileID]] = (0..<61).map { [$0] }
        let tooLong: [[TileID]] = [Array(0..<14)]
        let twice: [[TileID]] = [[5, 6], [6, 7]]
        let outOfRange: [[TileID]] = [[104, 106]]
        let negative: [[TileID]] = [[-1]]
        for bad in [tooMany, tooLong, twice, outOfRange, negative] {
            clock.advance(1)
            store.aim(seat: 1, .table(bad))
        }
        await settled(store)
        #expect(aims(socket) == [.aim(seat: 1, aim: good)])
        #expect(!store.hasHeldAim)
        clock.advance(1)
        store.aim(seat: 1, .table([[7, 8, 9]]))
        await settled(store)
        #expect(aims(socket).count == 2)
        // The limits themselves are fine: 60 sets, 13 pieces, ids 0 and 105.
        clock.advance(1)
        store.aim(seat: 1, .table((0..<60).map { [$0] }))
        clock.advance(1)
        store.aim(seat: 1, .table([Array(0..<12) + [105]]))
        await settled(store)
        #expect(aims(socket).count == 4)
    }

    @Test func receivedAimsAreShownAndAClearDropsOne() throws {
        let (store, _, _) = makeStore()
        store.handle(.message(.aim(seat: 1, aim: target(0))))
        store.handle(.message(.aim(seat: 2, aim: .table([[5]]))))
        #expect(store.aims == [1: target(0), 2: .table([[5]])])
        store.handle(.message(.aim(seat: 1, aim: nil)))
        #expect(store.aims == [2: .table([[5]])])
    }

    @Test func aSnapshotThatChangesTheTurnClearsTheAims() throws {
        let (store, _, _) = makeStore()
        store.handle(.connected)
        store.handle(.message(.snapshot(protocol: 1, seq: 5, room: try room(turn: 0))))
        store.handle(.message(.aim(seat: 1, aim: target(0))))
        // The same turn again (a reconnect's snapshot): the aim stays.
        store.handle(.message(.snapshot(protocol: 1, seq: 6, room: try room(turn: 0))))
        #expect(store.aims == [1: target(0)])
        store.handle(.message(.snapshot(protocol: 1, seq: 7, room: try room(turn: 1))))
        #expect(store.aims.isEmpty)
    }

    @Test func aSnapshotThatChangesTheStatusClearsTheAims() throws {
        let (store, _, _) = makeStore()
        store.handle(.message(.snapshot(protocol: 1, seq: 5, room: try room(turn: 0))))
        store.handle(.message(.aim(seat: 1, aim: target(0))))
        var over = try room(turn: 0)
        over.status = .over
        store.handle(.message(.snapshot(protocol: 1, seq: 6, room: over)))
        #expect(store.aims.isEmpty)
    }
}
