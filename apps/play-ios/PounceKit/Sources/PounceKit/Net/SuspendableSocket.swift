import Foundation

/// A room socket that can be put down and picked up again, so one `RoomStore`
/// (and the table scene holding it) lives for the whole room screen while the
/// app goes to the background and back (spec §7.5).
///
/// Each connection is a fresh inner socket from `make` (a stopped `RoomSocket`
/// can't restart). `suspend()` stops the inner socket and reports `.disconnected`;
/// `resume()` makes and starts a new one, whose snapshot then flows through as
/// usual. The inner socket's terminal events (`.notFound`, `.closed`) finish
/// this socket too, as does `stop()`.
public actor SuspendableSocket: RoomSocketing {
    public nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private let make: @Sendable () -> any RoomSocketing

    private var started = false
    private var suspended = false
    private var finished = false
    /// Bumped whenever the inner socket is replaced or dropped, so a late event
    /// from an old connection is never forwarded.
    private var generation = 0
    private var inner: (any RoomSocketing)?
    private var forward: Task<Void, Never>?

    public init(make: @escaping @Sendable () -> any RoomSocketing) {
        self.make = make
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    /// Connects (once). Deferred until `resume()` when called while suspended.
    public func start() async {
        guard !started, !finished else { return }
        started = true
        if !suspended { await connect() }
    }

    public func send(_ m: ClientMessage) async throws {
        guard let inner else { throw RoomSocketError.notConnected }
        try await inner.send(m)
    }

    /// Reconnects the live connection now. Ignored while suspended or stopped.
    public func reconnectNow() async {
        guard !finished, !suspended else { return }
        if let inner {
            await inner.reconnectNow()
        } else if started {
            await connect()
        }
    }

    /// Drops the connection until `resume()`.
    public func suspend() async {
        guard !finished, !suspended else { return }
        suspended = true
        guard let old = drop() else { return }
        continuation.yield(.disconnected)
        await old.stop()
    }

    /// Connects again after `suspend()` (if `start()` was called).
    public func resume() async {
        guard !finished, suspended else { return }
        suspended = false
        if started { await connect() }
    }

    public func stop() async {
        guard !finished else { return }
        finished = true
        let old = drop()
        continuation.finish()
        await old?.stop()
    }

    // MARK: private

    private func connect() async {
        generation += 1
        let gen = generation
        let socket = make()
        inner = socket
        await socket.start()
        guard gen == generation, !finished else { return }
        forward = Task { [weak self] in
            for await event in socket.events {
                guard let self else { return }
                await self.relay(event, gen)
            }
        }
    }

    private func drop() -> (any RoomSocketing)? {
        generation += 1
        forward?.cancel()
        forward = nil
        defer { inner = nil }
        return inner
    }

    private func relay(_ event: SocketEvent, _ gen: Int) {
        guard gen == generation, !finished else { return }
        continuation.yield(event)
        switch event {
        case .notFound, .locked, .closed:
            finished = true
            _ = drop()
            continuation.finish()
        default:
            break
        }
    }
}
