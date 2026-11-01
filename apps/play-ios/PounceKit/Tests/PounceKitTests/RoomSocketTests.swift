import Foundation
import Synchronization
import Testing
@testable import PounceKit

// MARK: - fakes

/// An unbounded queue whose `take()` suspends until an item arrives, the box is
/// closed, or the taking task is cancelled. The building block of every fake below.
final class Mailbox<T: Sendable>: Sendable {
    private struct State {
        var items: [Result<T, any Error>] = []
        var closedWith: (any Error)?
        var waiters: [(id: Int, continuation: CheckedContinuation<T, any Error>)] = []
        var cancelled: Set<Int> = []
        var nextID = 0
    }

    private let state = Mutex(State())

    func put(_ value: T) { deliver(.success(value)) }

    /// Later `take()`s (and the pending ones) throw `error`; queued items are dropped.
    func close(_ error: any Error) {
        let waiting = state.withLock { s in
            s.closedWith = s.closedWith ?? error
            s.items = []
            defer { s.waiters = [] }
            return s.waiters.map(\.continuation)
        }
        for continuation in waiting { continuation.resume(throwing: error) }
    }

    var isClosed: Bool { state.withLock { $0.closedWith != nil } }
    var waiting: Int { state.withLock { $0.waiters.count } }

    func take() async throws -> T {
        let id = state.withLock { s in
            s.nextID += 1
            return s.nextID
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                let now: Result<T, any Error>? = state.withLock { s in
                    if s.cancelled.remove(id) != nil { return .failure(CancellationError()) }
                    if !s.items.isEmpty { return s.items.removeFirst() }
                    if let error = s.closedWith { return .failure(error) }
                    s.waiters.append((id, continuation))
                    return nil
                }
                if let now { continuation.resume(with: now) }
            }
        } onCancel: {
            let continuation = state.withLock { s -> CheckedContinuation<T, any Error>? in
                if let i = s.waiters.firstIndex(where: { $0.id == id }) { return s.waiters.remove(at: i).continuation }
                s.cancelled.insert(id)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    private func deliver(_ result: Result<T, any Error>) {
        let continuation = state.withLock { s -> CheckedContinuation<T, any Error>? in
            if s.closedWith != nil { return nil }
            if !s.waiters.isEmpty { return s.waiters.removeFirst().continuation }
            s.items.append(result)
            return nil
        }
        continuation?.resume(with: result)
    }
}

struct Dropped: Error {}
struct PingFailed: Error {}

/// One scripted socket: the test pushes frames, drops it, and scripts ping results.
final class FakeConnection: WebSocketConnection {
    private let frames = Mailbox<String>()
    private let sentLog = Mutex<[String]>([])
    private let pingResults: Mutex<[Bool]>
    private let pingCount = Mutex(0)

    /// `pings` are consumed one per `sendPing()` (true = pong); once exhausted every ping succeeds.
    init(frames: [String] = [], pings: [Bool] = []) {
        pingResults = Mutex(pings)
        for frame in frames { self.frames.put(frame) }
    }

    func push(_ frame: String) { frames.put(frame) }
    /// The network went away: the pending and every later `receive()` throws.
    func drop() { frames.close(Dropped()) }

    var sent: [String] { sentLog.withLock { $0 } }
    var pings: Int { pingCount.withLock { $0 } }
    var isClosed: Bool { frames.isClosed }

    func send(_ text: String) async throws {
        if frames.isClosed { throw Dropped() }
        sentLog.withLock { $0.append(text) }
    }

    func receive() async throws -> String { try await frames.take() }

    func sendPing() async throws {
        pingCount.withLock { $0 += 1 }
        let ok = pingResults.withLock { $0.isEmpty ? true : $0.removeFirst() }
        if !ok { throw PingFailed() }
    }

    func close() async { frames.close(Dropped()) }
}

final class FakeConnector: WebSocketConnector {
    enum Outcome: Sendable {
        case connection(FakeConnection)
        case failure(SocketConnectError)
    }

    private let script: Mutex<[Outcome]>
    private let log = Mutex<[(url: URL, token: String)]>([])
    /// Never filled: once the script runs out, `connect` hangs until cancelled.
    private let exhausted = Mailbox<Void>()

    init(_ script: [Outcome]) { self.script = Mutex(script) }

    var calls: [(url: URL, token: String)] { log.withLock { $0 } }

    func connect(url: URL, token: String) async throws -> any WebSocketConnection {
        log.withLock { $0.append((url, token)) }
        switch script.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) {
        case .connection(let connection): return connection
        case .failure(let error): throw error
        case nil:
            try await exhausted.take()
            throw CancellationError()
        }
    }
}

/// The injected `sleep`. Ping sleeps (`pingInterval`) wait for `tickPing()`.
/// Backoff sleeps are recorded and return at once, or, while `holdBackoff` is
/// set, wait for `releaseBackoff()` or cancellation.
final class FakeSleeper: Sendable {
    let pingInterval: Duration
    private let backoffLog = Mutex<[Duration]>([])
    private let cancelledLog = Mutex(0)
    private let hold: Mutex<Bool>
    private let pingGate = Mailbox<Void>()
    private let backoffGate = Mailbox<Void>()

    init(pingInterval: Duration = .seconds(25), holdBackoff: Bool = false) {
        self.pingInterval = pingInterval
        hold = Mutex(holdBackoff)
    }

    var backoffs: [Duration] { backoffLog.withLock { $0 } }
    var cancelledBackoffs: Int { cancelledLog.withLock { $0 } }
    var heldBackoffs: Int { backoffGate.waiting }

    func tickPing() { pingGate.put(()) }
    func releaseBackoff() { backoffGate.put(()) }

    func sleep(_ duration: Duration) async throws {
        if duration == pingInterval {
            try await pingGate.take()
            return
        }
        backoffLog.withLock { $0.append(duration) }
        if hold.withLock({ $0 }) {
            do { try await backoffGate.take() } catch {
                cancelledLog.withLock { $0 += 1 }
                throw error
            }
        } else {
            try Task.checkCancellation()
        }
    }
}

/// Reads the event stream in order; a finished stream stops every read.
struct EventReader {
    private var iterator: AsyncStream<SocketEvent>.AsyncIterator
    private(set) var all: [SocketEvent] = []

    init(_ events: AsyncStream<SocketEvent>) { iterator = events.makeAsyncIterator() }

    mutating func next(_ count: Int) async -> [SocketEvent] {
        var out: [SocketEvent] = []
        while out.count < count, let event = await iterator.next() {
            out.append(event)
            all.append(event)
        }
        return out
    }

    /// Reads up to and including the first `event` (or to the end of the stream).
    mutating func until(_ event: SocketEvent) async -> [SocketEvent] {
        var out: [SocketEvent] = []
        while let next = await iterator.next() {
            out.append(next)
            all.append(next)
            if next == event { break }
        }
        return out
    }

    /// Everything left; returns only when the stream finishes.
    mutating func rest() async -> [SocketEvent] {
        var out: [SocketEvent] = []
        while let next = await iterator.next() {
            out.append(next)
            all.append(next)
        }
        return out
    }
}

/// Polls `condition`, yielding in between, for fake state that has no event of its own.
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<5_000 {
        if condition() { return true }
        await Task.yield()
        try? await Task.sleep(for: .microseconds(200))
    }
    return condition()
}

// MARK: - tests

@Suite(.timeLimit(.minutes(1))) struct RoomSocketTests {
    private let config = APIConfig(baseURL: URL(string: "http://localhost:8787")!)
    private let credential = DeviceCredential(deviceId: "dev-1", token: "tok-1")
    private let roomClosedFrame = #"{"t":"error","code":"room_closed"}"#

    private func snapshotFrame() throws -> String {
        try #require(try Fixtures.serverMessages().first { $0.name == "snapshot-lobby" }).json
    }

    private func makeSocket(_ connector: FakeConnector, _ sleeper: FakeSleeper) -> RoomSocket {
        let credential = credential
        return RoomSocket(
            code: "BCDFG", config: config, credential: { credential }, connector: connector,
            pingInterval: sleeper.pingInterval, sleep: { try await sleeper.sleep($0) })
    }

    @Test func connectsAndForwardsSnapshot() async throws {
        let frame = try snapshotFrame()
        let connector = FakeConnector([.connection(FakeConnection(frames: [frame]))])
        let socket = makeSocket(connector, FakeSleeper())
        var reader = EventReader(socket.events)

        await socket.start()
        let events = await reader.next(3)

        #expect(events == [.connecting, .connected, .message(try Codec.decode(frame))])
        guard case .message(.snapshot(1, 3, _)) = events.last else { Issue.record("no snapshot"); return }
        #expect(connector.calls.map(\.url) == [config.socketURL(code: "BCDFG")])
        #expect(connector.calls.map(\.token) == ["tok-1"])
        await socket.stop()
    }

    @Test func reconnectsWithBackoffAfterDrop() async throws {
        let conns = (0..<4).map { _ in FakeConnection() }
        let connector = FakeConnector(conns.map { .connection($0) })
        let sleeper = FakeSleeper()
        let socket = makeSocket(connector, sleeper)
        var reader = EventReader(socket.events)

        await socket.start()
        #expect(await reader.next(2) == [.connecting, .connected])

        // Two drops with no snapshot in between: the backoff climbs.
        conns[0].drop()
        #expect(await reader.next(3) == [.disconnected, .connecting, .connected])
        conns[1].drop()
        #expect(await reader.next(3) == [.disconnected, .connecting, .connected])
        #expect(sleeper.backoffs == [.milliseconds(250), .milliseconds(500)])

        // A snapshot resets it.
        let frame = try snapshotFrame()
        conns[2].push(frame)
        #expect(await reader.next(1) == [.message(try Codec.decode(frame))])
        conns[2].drop()
        #expect(await reader.next(3) == [.disconnected, .connecting, .connected])
        #expect(sleeper.backoffs == [.milliseconds(250), .milliseconds(500), .milliseconds(250)])
        #expect(connector.calls.count == 4)
        #expect(conns[0].isClosed && conns[1].isClosed && conns[2].isClosed)
        await socket.stop()
    }

    @Test func backoffStopsClimbingAtTheLastStep() async throws {
        let connector = FakeConnector(Array(repeating: .failure(.failed("down")), count: 8))
        let sleeper = FakeSleeper()
        let socket = RoomSocket(
            code: "BCDFG", config: config, credential: { [credential] in credential }, connector: connector,
            backoff: [.milliseconds(250), .milliseconds(500), .seconds(1)],
            pingInterval: sleeper.pingInterval, sleep: { try await sleeper.sleep($0) })
        var reader = EventReader(socket.events)

        await socket.start()
        // Each failed connect: connecting, disconnected, backoff. The ninth connect hangs.
        let events = await reader.next(17)
        #expect(events == Array(repeating: [SocketEvent.connecting, .disconnected], count: 8).flatMap { $0 } + [.connecting])
        #expect(sleeper.backoffs == [.milliseconds(250), .milliseconds(500)] + Array(repeating: .seconds(1), count: 6))
        await socket.stop()
    }

    @Test func notFoundIsTerminal() async throws {
        let connector = FakeConnector([.failure(.notFound), .connection(FakeConnection())])
        let sleeper = FakeSleeper()
        let socket = makeSocket(connector, sleeper)
        var reader = EventReader(socket.events)

        await socket.start()

        #expect(await reader.rest() == [.connecting, .notFound])
        #expect(connector.calls.count == 1)
        #expect(sleeper.backoffs.isEmpty)
    }

    @Test func roomClosedIsTerminal() async throws {
        let frame = try snapshotFrame()
        let conn = FakeConnection(frames: [frame, roomClosedFrame])
        let connector = FakeConnector([.connection(conn), .connection(FakeConnection())])
        let sleeper = FakeSleeper()
        let socket = makeSocket(connector, sleeper)
        var reader = EventReader(socket.events)

        await socket.start()

        #expect(await reader.rest() == [
            .connecting, .connected, .message(try Codec.decode(frame)), .message(.error(.roomClosed)), .closed,
        ])
        #expect(conn.isClosed)
        #expect(connector.calls.count == 1)
        #expect(sleeper.backoffs.isEmpty)
        await #expect(throws: RoomSocketError.notConnected) { try await socket.send(.start) }
    }

    @Test func stopPreventsReconnect() async throws {
        // Stopped mid-backoff: the sleep is cancelled and nothing reconnects.
        let first = FakeConnection()
        let connector = FakeConnector([.connection(first), .connection(FakeConnection())])
        let sleeper = FakeSleeper(holdBackoff: true)
        let socket = makeSocket(connector, sleeper)
        var reader = EventReader(socket.events)

        await socket.start()
        #expect(await reader.next(2) == [.connecting, .connected])
        first.drop()
        #expect(await reader.next(1) == [.disconnected])
        #expect(await eventually { sleeper.heldBackoffs == 1 })

        await socket.stop()

        #expect(await reader.rest() == [])
        #expect(await eventually { sleeper.cancelledBackoffs == 1 })
        sleeper.releaseBackoff()  // even a late wake-up must not reconnect
        await Task.yield()
        #expect(connector.calls.count == 1)

        // Stopped while connected: the connection is closed and the stream ends.
        let live = FakeConnection()
        let socket2 = makeSocket(FakeConnector([.connection(live), .connection(FakeConnection())]), FakeSleeper())
        var reader2 = EventReader(socket2.events)
        await socket2.start()
        #expect(await reader2.next(2) == [.connecting, .connected])
        await socket2.stop()
        #expect(await reader2.rest() == [])
        #expect(live.isClosed)
    }

    @Test func reconnectNowReconnectsImmediately() async throws {
        let conns = (0..<4).map { _ in FakeConnection() }
        let connector = FakeConnector(conns.map { .connection($0) })
        let sleeper = FakeSleeper(holdBackoff: true)
        let socket = makeSocket(connector, sleeper)
        var reader = EventReader(socket.events)

        await socket.start()
        #expect(await reader.next(2) == [.connecting, .connected])

        // Climb the backoff, then sit in the 0.5 s wait.
        conns[0].drop()
        #expect(await reader.next(1) == [.disconnected])
        #expect(await eventually { sleeper.heldBackoffs == 1 })
        sleeper.releaseBackoff()
        #expect(await reader.next(2) == [.connecting, .connected])
        conns[1].drop()
        #expect(await reader.next(1) == [.disconnected])
        #expect(await eventually { sleeper.heldBackoffs == 1 })

        await socket.reconnectNow()

        // Connects without the held sleep ever finishing.
        #expect(await reader.next(2) == [.connecting, .connected])
        #expect(await eventually { sleeper.cancelledBackoffs == 1 })
        #expect(connector.calls.count == 3)

        // reconnectNow on a live connection drops it and reconnects at once.
        await socket.reconnectNow()
        #expect(await reader.next(3) == [.disconnected, .connecting, .connected])
        #expect(conns[2].isClosed)
        #expect(connector.calls.count == 4)

        // The attempt counter went back to 0.
        conns[3].drop()
        #expect(await reader.next(1) == [.disconnected])
        #expect(await eventually { sleeper.heldBackoffs == 1 })
        #expect(sleeper.backoffs == [.milliseconds(250), .milliseconds(500), .milliseconds(250)])
        await socket.stop()
    }

    @Test func badFramesAreIgnored() async throws {
        let frame = try snapshotFrame()
        let conn = FakeConnection(frames: [
            "not json", #"{"t":"mystery"}"#, #"{"t":"event","seq":1,"event":{"kind":"nope"}}"#, frame,
        ])
        let connector = FakeConnector([.connection(conn)])
        let socket = makeSocket(connector, FakeSleeper())
        var reader = EventReader(socket.events)

        await socket.start()

        #expect(await reader.next(3) == [.connecting, .connected, .message(try Codec.decode(frame))])
        #expect(!conn.isClosed)
        #expect(connector.calls.count == 1)
        await socket.stop()
    }

    @Test func sendWhileDisconnectedThrows() async throws {
        let first = FakeConnection()
        let connector = FakeConnector([.connection(first), .connection(FakeConnection())])
        let sleeper = FakeSleeper(holdBackoff: true)
        let socket = makeSocket(connector, sleeper)
        var reader = EventReader(socket.events)

        await #expect(throws: RoomSocketError.notConnected) { try await socket.send(.start) }

        await socket.start()
        #expect(await reader.next(2) == [.connecting, .connected])
        try await socket.send(.presence(.active))
        #expect(first.sent == [try Codec.encode(.presence(.active))])

        first.drop()
        #expect(await reader.next(1) == [.disconnected])
        await #expect(throws: RoomSocketError.notConnected) { try await socket.send(.start) }
        #expect(first.sent.count == 1)
        await socket.stop()
    }

    @Test func twoConsecutivePingFailuresForceReconnect() async throws {
        // fail, pong, fail, fail: only the second run of two failures reconnects.
        let first = FakeConnection(pings: [false, true, false, false])
        let second = FakeConnection()
        let connector = FakeConnector([.connection(first), .connection(second)])
        let sleeper = FakeSleeper()
        let socket = makeSocket(connector, sleeper)
        var reader = EventReader(socket.events)

        await socket.start()
        #expect(await reader.next(2) == [.connecting, .connected])
        for _ in 0..<4 { sleeper.tickPing() }

        #expect(await reader.next(3) == [.disconnected, .connecting, .connected])
        #expect(first.pings == 4)
        #expect(first.isClosed)
        #expect(sleeper.backoffs == [.milliseconds(250)])

        // The new connection gets its own ping loop.
        sleeper.tickPing()
        #expect(await eventually { second.pings == 1 })
        #expect(first.pings == 4)
        await socket.stop()
    }

    @Test func futureProtocolSnapshotIsForwarded() async throws {
        let conn = FakeConnection(frames: [#"{"t":"snapshot","protocol":2,"seq":1,"room":{"weird":true}}"#])
        let socket = makeSocket(FakeConnector([.connection(conn)]), FakeSleeper())
        var reader = EventReader(socket.events)

        await socket.start()

        #expect(await reader.next(3) == [.connecting, .connected, .message(.unsupportedProtocol(2))])
        await socket.stop()
    }
}
