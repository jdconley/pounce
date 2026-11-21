import Foundation
import Testing

@testable import PounceKit

/// One scripted socket: hands out its frames, then fails (a drop) or waits forever.
private actor ScriptedConnection: WebSocketConnection {
    var frames: [String]
    let dropsAtEnd: Bool
    var sent: [String] = []
    var closed = false

    init(_ frames: [String], dropsAtEnd: Bool) {
        self.frames = frames
        self.dropsAtEnd = dropsAtEnd
    }

    func send(_ text: String) async throws { sent.append(text) }
    func receive() async throws -> String {
        if !frames.isEmpty { return frames.removeFirst() }
        if dropsAtEnd || closed { throw SocketConnectError.failed("dropped") }
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
    func sendPing() async throws {}
    func close() async { closed = true }
}

private actor ScriptedConnector: WebSocketConnector {
    var script: [Result<ScriptedConnection, SocketConnectError>]
    var urls: [URL] = []

    init(_ script: [Result<ScriptedConnection, SocketConnectError>]) { self.script = script }

    func connect(url: URL, token: String) async throws -> any WebSocketConnection {
        urls.append(url)
        guard !script.isEmpty else {
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }
        return try script.removeFirst().get()
    }
}

@Suite struct DailyBoardSocketTests {
    private static let board = #"{"t":"board","board":{"date":"2026-11-23","games":[],"dish":{"rows":[]},"tvs":0}}"#
    private let config = APIConfig(baseURL: URL(string: "http://h:1")!)

    private func socket(_ connector: ScriptedConnector) -> DailyBoardSocket {
        DailyBoardSocket(
            config: config, person: "p1", connector: connector,
            credential: { DeviceCredential(deviceId: "d", token: "t") }, retry: .milliseconds(10))
    }

    @Test func urlCarriesPerson() {
        #expect(config.dailyBoardSocketURL(person: "p1").absoluteString == "ws://h:1/v1/daily/board/ws?person=p1")
        #expect(APIConfig(baseURL: URL(string: "https://x.com")!).dailyBoardSocketURL(person: nil).absoluteString == "wss://x.com/v1/daily/board/ws")
    }

    @Test func decodesAndSkipsUnknown() async {
        let connector = ScriptedConnector([.success(ScriptedConnection([Self.board, #"{"t":"later"}"#, #"{"t":"tvs","count":1}"#], dropsAtEnd: false))])
        let s = socket(connector)
        var got: [DailyBoardMessage] = []
        let stream = await s.messages()
        await s.start()
        for await m in stream {
            got.append(m)
            if got.count == 2 { break }
        }
        await s.stop()
        guard case .board = got.first else { Issue.record("\(got)"); return }
        #expect(got.last == .tvs(1))
    }

    @Test func reconnectsAfterADrop() async {
        let connector = ScriptedConnector([
            .success(ScriptedConnection([#"{"t":"tvs","count":1}"#], dropsAtEnd: true)),
            .failure(.failed("offline")),
            .success(ScriptedConnection([#"{"t":"tvs","count":2}"#], dropsAtEnd: false)),
        ])
        let s = socket(connector)
        let stream = await s.messages()
        await s.start()
        var got: [DailyBoardMessage] = []
        for await m in stream {
            got.append(m)
            if got.count == 2 { break }
        }
        await s.stop()
        #expect(got == [.tvs(1), .tvs(2)])
        #expect(await connector.urls.count == 3)
    }

    @Test func notFoundStops() async {
        let connector = ScriptedConnector([.failure(.notFound)])
        let s = socket(connector)
        let stream = await s.messages()
        await s.start()
        var count = 0
        for await _ in stream { count += 1 }
        #expect(count == 0)
        #expect(await connector.urls.count == 1)
    }
}
