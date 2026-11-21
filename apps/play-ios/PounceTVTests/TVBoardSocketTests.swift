import Foundation
import PounceKit
import Synchronization
import Testing
@testable import PounceTV

/// One board socket connection a test drives: push frames, drop it.
final class BoardConnection: WebSocketConnection {
    private let stream: AsyncThrowingStream<String, any Error>
    private let feed: AsyncThrowingStream<String, any Error>.Continuation
    private let sentLog = Mutex<[String]>([])
    private let closed = Mutex(false)

    init() { (stream, feed) = AsyncThrowingStream.makeStream(of: String.self) }

    struct Dropped: Error {}

    func push(_ frame: String) { feed.yield(frame) }
    func drop() { feed.finish(throwing: Dropped()) }
    var sent: [String] { sentLog.withLock { $0 } }
    var isClosed: Bool { closed.withLock { $0 } }

    func send(_ text: String) async throws { sentLog.withLock { $0.append(text) } }
    func receive() async throws -> String {
        var it = stream.makeAsyncIterator()
        guard let next = try await it.next() else { throw Dropped() }
        return next
    }
    func sendPing() async throws {}
    func close() async {
        closed.withLock { $0 = true }
        feed.finish(throwing: Dropped())
    }
}

/// Opens a `BoardConnection` per call, unless a failure is queued.
final class BoardConnector: WebSocketConnector {
    private let state = Mutex<(urls: [URL], made: [BoardConnection], failures: [SocketConnectError])>(([], [], []))

    var urls: [URL] { state.withLock { $0.urls } }
    var made: [BoardConnection] { state.withLock { $0.made } }
    func fail(_ errors: SocketConnectError...) { state.withLock { $0.failures += errors } }

    func connect(url: URL, token: String) async throws -> any WebSocketConnection {
        let (failure, made): (SocketConnectError?, BoardConnection?) = state.withLock { s in
            s.urls.append(url)
            if !s.failures.isEmpty { return (s.failures.removeFirst(), nil) }
            let c = BoardConnection()
            s.made.append(c)
            return (nil, c)
        }
        if let failure { throw failure }
        return made!
    }
}

/// Collects a socket's events as they come.
final class BoardEvents: Sendable {
    private let all = Mutex<[BoardSocketEvent]>([])
    var list: [BoardSocketEvent] { all.withLock { $0 } }
    func add(_ e: BoardSocketEvent) { all.withLock { $0.append(e) } }
}

@Suite("The TV's board socket")
struct TVBoardSocketTests {
    private let config = APIConfig(baseURL: URL(string: "https://play.example")!)
    private let board = String(repeating: "B", count: 22)

    private func rig(forget: @escaping @Sendable () async -> Void = {}) -> (TVBoardSocket, BoardConnector, BoardEvents, Task<Void, Never>) {
        let connector = BoardConnector()
        let socket = TVBoardSocket(
            url: TVBoardSocket.url(config: config, board: board),
            credential: { DeviceCredential(deviceId: "tv", token: "tvtok") },
            forget: forget,
            connector: connector,
            backoff: [.milliseconds(1)],
            heartbeat: .seconds(3600))
        let events = BoardEvents()
        let reader = Task { for await e in socket.events { events.add(e) } }
        return (socket, connector, events, reader)
    }

    private func eventually(_ ok: @escaping () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if ok() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return ok()
    }

    @Test func itOpensTheBoardsSocketOnTheServer() async {
        let (socket, connector, _, reader) = rig()
        await socket.start()
        #expect(await eventually { !connector.urls.isEmpty })
        #expect(connector.urls.first?.absoluteString == "wss://play.example/v1/daily/board/ws?board=\(board)")
        await socket.stop()
        reader.cancel()
    }

    @Test func itPassesOnEachMessageInOrder() async {
        let (socket, connector, events, reader) = rig()
        await socket.start()
        #expect(await eventually { !connector.made.isEmpty })
        let c = connector.made[0]
        c.push("nope")
        c.push(BoardFixtures.texts["board"] ?? "")
        c.push(BoardFixtures.texts["result"] ?? "")
        #expect(await eventually { events.list.count == 3 })
        #expect(events.list.first == .online)
        #expect(events.list[1] == .message(BoardFixtures.message("board")))
        #expect(events.list[2] == .message(BoardFixtures.message("result")))
        await socket.stop()
        reader.cancel()
    }

    @Test func aBoardTheServerDoesntKnowIsGoneAndNotTriedAgain() async {
        let (socket, connector, events, reader) = rig()
        connector.fail(.notFound)
        await socket.start()
        #expect(await eventually { events.list == [.gone] })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(connector.urls.count == 1)
        reader.cancel()
    }

    @Test func aDroppedSocketSaysOfflineAndComesBackThenAnUnlinkIsGone() async {
        let (socket, connector, events, reader) = rig()
        await socket.start()
        #expect(await eventually { connector.made.count == 1 })
        // Unlinked from a phone: the server closes the socket, and the reconnect hears 404.
        connector.fail(.notFound)
        connector.made[0].drop()
        #expect(await eventually { events.list.last == .gone })
        #expect(events.list == [.online, .offline, .gone])
        reader.cancel()
    }

    @Test func aRefusedDeviceTokenIsForgottenAndTriedAgain() async {
        let forgot = Mutex(0)
        let (socket, connector, _, reader) = rig(forget: { forgot.withLock { $0 += 1 } })
        connector.fail(.unauthorized)
        await socket.start()
        #expect(await eventually { connector.made.count == 1 })
        #expect(forgot.withLock { $0 } == 1)
        await socket.stop()
        reader.cancel()
    }

    @Test func stoppedItClosesAndSaysNothingMore() async {
        let (socket, connector, events, reader) = rig()
        await socket.start()
        #expect(await eventually { connector.made.count == 1 })
        await socket.stop()
        #expect(connector.made[0].isClosed)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(events.list == [.online])
        reader.cancel()
    }
}
