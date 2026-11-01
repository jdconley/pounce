import Foundation
import Synchronization

/// One open WebSocket. `receive()` throws once the socket is gone (including after `close()`).
public protocol WebSocketConnection: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func sendPing() async throws
    func close() async
}

public enum SocketConnectError: Error, Equatable {
    /// The upgrade got 404: the room does not exist (or has expired).
    case notFound
    /// The upgrade got 401: the bearer token was rejected.
    case unauthorized
    case failed(String)
}

public protocol WebSocketConnector: Sendable {
    func connect(url: URL, token: String) async throws -> any WebSocketConnection
}

/// Opens sockets with `URLSessionWebSocketTask`, sending `Authorization: Bearer <token>`.
///
/// `connect` returns only once the upgrade has succeeded: it sends a ping right
/// after `resume()` (URLSession queues it until the handshake finishes) and waits
/// for the pong. URLSession only delivers a pong while a `receive()` is pending, so
/// the first receive starts before the ping and its frame is handed to the
/// connection's first `receive()` call. If the handshake fails instead, the HTTP
/// status of the refused upgrade decides the error: 404 is `.notFound`, 401 is
/// `.unauthorized`.
public struct URLSessionWebSocketConnector: WebSocketConnector {
    private let session: URLSession
    private let timeout: Duration

    /// `timeout` bounds the opening handshake and every later ping.
    public init(session: URLSession = .shared, timeout: Duration = .seconds(15)) {
        self.session = session
        self.timeout = timeout
    }

    public func connect(url: URL, token: String) async throws -> any WebSocketConnection {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        let connection = URLSessionWebSocketConnection(task: task, pingTimeout: timeout)
        task.resume()
        connection.prefetch()
        do {
            try await connection.sendPing()
        } catch {
            let status = (task.response as? HTTPURLResponse)?.statusCode
            task.cancel()
            connection.dropPrefetch()
            if error is CancellationError { throw error }
            switch status {
            case 404: throw SocketConnectError.notFound
            case 401: throw SocketConnectError.unauthorized
            case let code?: throw SocketConnectError.failed("upgrade refused with HTTP \(code)")
            case nil: throw SocketConnectError.failed(String(describing: error))
            }
        }
        return connection
    }
}

final class URLSessionWebSocketConnection: WebSocketConnection {
    private let task: URLSessionWebSocketTask
    private let pingTimeout: Duration
    /// A receive started before the opening ping; the first `receive()` takes its frame.
    private let early = Mutex<Task<URLSessionWebSocketTask.Message, any Error>?>(nil)

    init(task: URLSessionWebSocketTask, pingTimeout: Duration) {
        self.task = task
        self.pingTimeout = pingTimeout
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    /// Keeps a receive pending so the opening ping's pong can arrive.
    func prefetch() {
        let task = task
        early.withLock { $0 = Task { try await task.receive() } }
    }

    func dropPrefetch() {
        early.withLock { pending in
            pending?.cancel()
            pending = nil
        }
    }

    func receive() async throws -> String {
        let pending = early.withLock { pending in
            defer { pending = nil }
            return pending
        }
        let message = if let pending { try await pending.value } else { try await task.receive() }
        switch message {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: throw SocketConnectError.failed("unknown WebSocket frame")
        }
    }

    /// Waits for the pong, failing after `pingTimeout`, on the socket failing, or on
    /// task cancellation (a silent dead connection may never call the pong handler).
    func sendPing() async throws {
        let result = OneShot()
        let timeout = Task { [pingTimeout] in
            do {
                try await Task.sleep(for: pingTimeout)
                result.finish(.failure(SocketConnectError.failed("ping timed out")))
            } catch {}
        }
        defer { timeout.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                result.install(continuation)
                task.sendPing { error in
                    result.finish(error.map { .failure($0) } ?? .success(()))
                }
            }
        } onCancel: {
            result.finish(.failure(CancellationError()))
        }
    }

    func close() async {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

/// Resumes one continuation exactly once with whichever result arrives first,
/// even when that result arrives before the continuation is installed.
private final class OneShot: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, any Error>?
        var result: Result<Void, any Error>?
    }

    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<Void, any Error>) {
        let early = state.withLock { s -> Result<Void, any Error>? in
            if let result = s.result { return result }
            s.continuation = continuation
            return nil
        }
        if let early { continuation.resume(with: early) }
    }

    func finish(_ result: Result<Void, any Error>) {
        let waiting = state.withLock { s -> CheckedContinuation<Void, any Error>? in
            guard s.result == nil else { return nil }
            s.result = result
            defer { s.continuation = nil }
            return s.continuation
        }
        waiting?.resume(with: result)
    }
}
