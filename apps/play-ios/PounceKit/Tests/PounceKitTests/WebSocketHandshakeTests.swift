import Foundation
import Network
import Synchronization
import Testing
@testable import PounceKit

/// A loopback WebSocket server (Network.framework) for the real `URLSessionWebSocketConnector`.
/// On each connection it sends `greeting` as text frames. With `answersPings` false it never
/// sends a pong, so a handshake that only waits for the pong times out.
private final class LoopbackServer: Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "loopback-ws")
    private let connections = Mutex<[NWConnection]>([])

    init(answersPings: Bool, greeting: [String]) throws {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = answersPings
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self, queue] connection in
            self?.connections.withLock { $0.append(connection) }
            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                for text in greeting {
                    let meta = NWProtocolWebSocket.Metadata(opcode: .text)
                    let context = NWConnection.ContentContext(identifier: "text", metadata: [meta])
                    connection.send(
                        content: Data(text.utf8), contentContext: context, isComplete: true,
                        completion: .contentProcessed { _ in })
                }
            }
            connection.start(queue: queue)
        }
    }

    /// Starts listening and returns the `ws://` URL.
    func start() async throws -> URL {
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = Mutex(false)
            listener.stateUpdateHandler = { [listener] state in
                let result: Result<UInt16, any Error>?
                switch state {
                case .ready: result = .success(listener.port?.rawValue ?? 0)
                case .failed(let error): result = .failure(error)
                default: result = nil
                }
                guard let result, once.withLock({ done in defer { done = true }; return !done }) else { return }
                continuation.resume(with: result)
            }
            listener.start(queue: queue)
        }
        return URL(string: "ws://127.0.0.1:\(port)/v1/rooms/BCDFG/ws")!
    }

    func stop() {
        listener.cancel()
        for c in connections.withLock({ $0 }) { c.cancel() }
    }
}

@Suite(.timeLimit(.minutes(1))) struct WebSocketHandshakeTests {
    /// Frames that arrive before the pong (a snapshot, then another seat's event) can keep
    /// URLSession from reading the pong at all; the first frame alone proves the upgrade.
    @Test func firstFrameCompletesTheHandshakeWithoutAPong() async throws {
        let server = try LoopbackServer(answersPings: false, greeting: ["one", "two"])
        defer { server.stop() }
        let url = try await server.start()
        let connector = URLSessionWebSocketConnector(session: URLSession(configuration: .ephemeral), timeout: .seconds(5))

        let started = ContinuousClock.now
        let connection = try await connector.connect(url: url, token: "t")
        #expect(ContinuousClock.now - started < .seconds(4))  // not the ping timeout
        #expect(try await connection.receive() == "one")  // the prefetched frame is kept
        #expect(try await connection.receive() == "two")
        await connection.close()
    }

    /// A quiet server still completes the handshake on the pong.
    @Test func pongCompletesTheHandshakeWhenNoFrameComes() async throws {
        let server = try LoopbackServer(answersPings: true, greeting: [])
        defer { server.stop() }
        let url = try await server.start()
        let connector = URLSessionWebSocketConnector(session: URLSession(configuration: .ephemeral), timeout: .seconds(5))

        let started = ContinuousClock.now
        let connection = try await connector.connect(url: url, token: "t")
        #expect(ContinuousClock.now - started < .seconds(4))
        await connection.close()
    }
}
