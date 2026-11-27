#if DEBUG
import Foundation
import PounceKit

/// The demo room behind a socket: a 10 Hz tick for the cats, this device's batches refereed as
/// they arrive. All on this actor, never the main thread.
actor TumbleDemoSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private let options: TumbleDemoRoom.Options
    private let tv: Bool
    private var room: TumbleDemoRoom?
    private var ticker: Task<Void, Never>?

    init(options: TumbleDemoRoom.Options, tv: Bool) {
        self.options = options
        self.tv = tv
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    func start() async {
        let made = TumbleDemoRoom(options, now: TumbleTable.now())
        room = made
        continuation.yield(.connected)
        for m in made.connect() { emit(m) }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                await self?.tick()
            }
        }
    }

    private func emit(_ m: ServerMessage) {
        guard tv, case .snapshot(let p, let seq, var r) = m else {
            continuation.yield(.message(m))
            return
        }
        r.screen = true
        continuation.yield(.message(.snapshot(protocol: p, seq: seq, room: r)))
    }

    private func tick() {
        guard let room else { return }
        for m in room.tick(now: TumbleTable.now()) { emit(m) }
    }

    func send(_ m: ClientMessage) async throws {
        guard let room else { return }
        for out in room.receive(m, now: TumbleTable.now()) { emit(out) }
    }

    func reconnectNow() async {
        guard let room else { return }
        continuation.yield(.connected)
        for m in room.connect() { emit(m) }
    }

    func stop() async {
        ticker?.cancel()
        continuation.finish()
    }
}
#endif
