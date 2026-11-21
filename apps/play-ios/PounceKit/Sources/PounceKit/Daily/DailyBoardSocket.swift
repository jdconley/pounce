import Foundation

extension APIConfig {
    /// The board socket a phone opens for a person: `ws(s)://host/v1/daily/board/ws?person=`.
    public func dailyBoardSocketURL(person: String?) -> URL {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.scheme = parts.scheme?.lowercased() == "https" ? "wss" : "ws"
        parts.path = "/v1/daily/board/ws"
        parts.queryItems = person.map { [URLQueryItem(name: "person", value: $0)] }
        parts.fragment = nil
        return parts.url ?? baseURL
    }
}

/// The live board (docs/daily-protocol.md, "The board socket"): snapshots, results, progress and
/// the TV count, for one person. It reconnects on its own after a drop (backing off up to 30 s),
/// pings to keep the line warm, and skips kinds it doesn't know. A 404 ends it: the server has the
/// Dish off. Everything runs on this actor; frames are decoded here, never on the main actor.
public actor DailyBoardSocket {
    private let url: URL
    private let connector: any WebSocketConnector
    private let credential: @Sendable () async throws -> DeviceCredential
    private let retry: Duration
    private let ping: Duration
    private var continuations: [Int: AsyncStream<DailyBoardMessage>.Continuation] = [:]
    private var nextID = 0
    private var runner: Task<Void, Never>?
    private var connection: (any WebSocketConnection)?

    public init(
        config: APIConfig, person: String?, connector: any WebSocketConnector,
        credential: @escaping @Sendable () async throws -> DeviceCredential, retry: Duration = .seconds(1), ping: Duration = .seconds(25)
    ) {
        url = config.dailyBoardSocketURL(person: person)
        self.connector = connector
        self.credential = credential
        self.retry = retry
        self.ping = ping
    }

    /// What the socket hears from here on. Finishes when the socket stops for good.
    public func messages() -> AsyncStream<DailyBoardMessage> {
        let (stream, continuation) = AsyncStream<DailyBoardMessage>.makeStream()
        let id = nextID
        nextID += 1
        continuations[id] = continuation
        continuation.onTermination = { _ in Task { await self.drop(id) } }
        return stream
    }

    private func drop(_ id: Int) { continuations[id] = nil }

    public func start() {
        guard runner == nil else { return }
        runner = Task { await self.run() }
    }

    /// Closes the socket and finishes every stream.
    public func stop() async {
        runner?.cancel()
        runner = nil
        await connection?.close()
        connection = nil
        finish()
    }

    private func finish() {
        let all = continuations.values
        continuations = [:]
        for c in all { c.finish() }
    }

    private func run() async {
        var wait = retry
        while !Task.isCancelled {
            do {
                let token = try await credential().token
                let conn = try await connector.connect(url: url, token: token)
                guard !Task.isCancelled else {
                    await conn.close()
                    return
                }
                connection = conn
                wait = retry
                let pinger = Task { [ping] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: ping)
                        guard !Task.isCancelled else { return }
                        try? await conn.send(#"{"t":"ping"}"#)
                    }
                }
                await read(conn)
                pinger.cancel()
                connection = nil
                await conn.close()
            } catch SocketConnectError.notFound {
                finish()
                runner = nil
                return
            } catch APIError.notFound {
                finish()
                runner = nil
                return
            } catch {}
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: wait)
            wait = min(wait * 2, .seconds(30))
        }
    }

    private func read(_ conn: any WebSocketConnection) async {
        while !Task.isCancelled {
            guard let text = try? await conn.receive() else { return }
            guard let message = DailyBoardMessage.decode(text) else { continue }
            switch message {
            case .unknown, .pong, .error: continue
            default: for c in continuations.values { c.yield(message) }
            }
        }
    }
}
