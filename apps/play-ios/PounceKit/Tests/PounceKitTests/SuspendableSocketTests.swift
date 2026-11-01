import Foundation
import Synchronization
import Testing
@testable import PounceKit

/// Hands out a fresh `FakeSocket` per connection and keeps them all.
private final class Maker: Sendable {
    private let made = Mutex<[FakeSocket]>([])

    var sockets: [FakeSocket] { made.withLock { $0 } }

    func make() -> any RoomSocketing {
        let socket = FakeSocket()
        made.withLock { $0.append(socket) }
        return socket
    }
}

private let lobbyRoom = RoomView(code: "BCDFG", status: .lobby, youAreHost: true, seats: [SeatView(kind: .open)])
private let snap = SocketEvent.message(.snapshot(protocol: 1, seq: 0, room: lobbyRoom))

@Suite struct SuspendableSocketTests {
    @Test func forwardsTheInnerSocket() async throws {
        let maker = Maker()
        let socket = SuspendableSocket { maker.make() }
        var events = socket.events.makeAsyncIterator()
        await socket.start()
        await socket.start()  // idempotent
        let inner = try #require(maker.sockets.first)
        #expect(maker.sockets.count == 1)
        #expect(inner.calls.starts == 1)

        inner.feed.yield(.connected)
        inner.feed.yield(snap)
        #expect(await events.next() == .connected)
        #expect(await events.next() == snap)

        try await socket.send(.start)
        #expect(inner.calls.sends == [.start])
        await socket.reconnectNow()
        #expect(inner.calls.reconnects == 1)
    }

    @Test func suspendThenResumeUsesAFreshConnection() async throws {
        let maker = Maker()
        let socket = SuspendableSocket { maker.make() }
        var events = socket.events.makeAsyncIterator()
        await socket.start()
        let first = try #require(maker.sockets.first)

        await socket.suspend()
        #expect(first.calls.stops == 1)
        #expect(await events.next() == .disconnected)
        await #expect(throws: RoomSocketError.notConnected) { try await socket.send(.start) }
        await socket.reconnectNow()  // ignored while suspended
        #expect(maker.sockets.count == 1)
        #expect(first.calls.reconnects == 0)

        await socket.resume()
        #expect(maker.sockets.count == 2)
        let second = maker.sockets[1]
        #expect(second.calls.starts == 1)
        second.feed.yield(.connected)
        #expect(await events.next() == .connected)
        try await socket.send(.presence(.active))
        #expect(second.calls.sends == [.presence(.active)])
        #expect(first.calls.sends.isEmpty)
    }

    @Test func terminalInnerEventFinishesTheStream() async throws {
        let maker = Maker()
        let socket = SuspendableSocket { maker.make() }
        var events = socket.events.makeAsyncIterator()
        await socket.start()
        let inner = try #require(maker.sockets.first)
        inner.feed.yield(.notFound)
        #expect(await events.next() == .notFound)
        #expect(await events.next() == nil)
        await socket.resume()
        #expect(maker.sockets.count == 1)
    }

    @Test func stopIsForGood() async throws {
        let maker = Maker()
        let socket = SuspendableSocket { maker.make() }
        var events = socket.events.makeAsyncIterator()
        await socket.start()
        let inner = try #require(maker.sockets.first)
        await socket.stop()
        #expect(inner.calls.stops == 1)
        #expect(await events.next() == nil)
        await socket.suspend()
        await socket.resume()
        await socket.start()
        #expect(maker.sockets.count == 1)
    }

    @Test func suspendBeforeStartDefersTheConnection() async {
        let maker = Maker()
        let socket = SuspendableSocket { maker.make() }
        await socket.suspend()
        await socket.start()
        #expect(maker.sockets.isEmpty)
        await socket.resume()
        #expect(maker.sockets.count == 1)
    }
}
