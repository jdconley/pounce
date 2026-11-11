import Foundation
import Synchronization

/// One open WebSocket. `receive()` throws once the socket is gone (including after `close()`).
public protocol WebSocketConnection: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func sendPing() async throws
    func close() async
    /// Drops the socket with no close frame, as a dead network would: the server sees an
    /// abnormal close, not a goodbye, and shows the seat as reconnecting. Defaults to `close()`.
    func abort() async
}

extension WebSocketConnection {
    public func abort() async { await close() }
}

public enum SocketConnectError: Error, Equatable {
    /// The upgrade got 404: the room does not exist (or has expired).
    case notFound
    /// The upgrade got 401: the bearer token was rejected.
    case unauthorized
    /// The upgrade got 429: too many wrong room codes from this phone or its network.
    case tooManyAttempts
    case failed(String)
}

public protocol WebSocketConnector: Sendable {
    func connect(url: URL, token: String) async throws -> any WebSocketConnection
}

/// Opens sockets with `URLSessionWebSocketTask`, sending `Authorization: Bearer <token>`.
///
/// `connect` returns only once the upgrade has succeeded. Right after `resume()` it
/// starts the first `receive()` (its frame is handed to the connection's first
/// `receive()` call) and sends a ping (URLSession queues it until the handshake
/// finishes), then waits for whichever comes first: the pong, or that first frame.
/// Either proves the upgrade went through. The race matters because URLSession may
/// stop reading once one data frame is buffered unconsumed: when the server sends
/// two frames before the pong (the snapshot, then another seat's event or a bot
/// step), the pong can sit behind them until the ping times out. If the handshake
/// fails instead, the HTTP status of the refused upgrade decides the error: 404 is
/// `.notFound`, 401 is `.unauthorized`, 429 is `.tooManyAttempts`.
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
            try await connection.handshake()
        } catch {
            let status = (task.response as? HTTPURLResponse)?.statusCode
            task.cancel()
            connection.dropPrefetch()
            if error is CancellationError { throw error }
            switch status {
            case 404: throw SocketConnectError.notFound
            case 401: throw SocketConnectError.unauthorized
            case 429: throw SocketConnectError.tooManyAttempts
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

    /// Waits for the opening ping's pong or the prefetched first frame, whichever
    /// lands first (see `URLSessionWebSocketConnector`). The first frame stays queued
    /// for `receive()`; a prefetch that fails fails the handshake.
    func handshake() async throws {
        let result = OneShot()
        let first = early.withLock { $0 }
        let watcher = Task {
            guard let first else { return }
            do {
                _ = try await first.value
                result.finish(.success(()))
            } catch {
                result.finish(.failure(error))
            }
        }
        defer { watcher.cancel() }  // never cancels `first`: awaiting a task's value doesn't own it
        try await ping(settling: result)
    }

    /// Waits for the pong, failing after `pingTimeout`, on the socket failing, or on
    /// task cancellation (a silent dead connection may never call the pong handler).
    func sendPing() async throws {
        try await ping(settling: OneShot())
    }

    /// Sends a ping and waits for `result`, which the pong, the timeout, cancellation,
    /// or another racer (the handshake's first frame) settles first.
    private func ping(settling result: OneShot) async throws {
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

    func abort() async {
        task.cancel()
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
