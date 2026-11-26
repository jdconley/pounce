#if DEBUG
import Foundation
import PounceKit

/// Toy Tumble's DEBUG demos (`-demo tumble-<name>`), on `TumbleDemoSocket`: a round against House
/// Cat boxes run by `TumbleDemoRoom` on the socket's own actor, so the real table plays with no
/// server.
/// - `tumble-play`: four seats, mid-round, two tricks in hand.
/// - `tumble-six`: six seats (five cats), for the busiest phone screen and the frame gate.
/// - `tumble-two`: one cat.
/// - `tumble-tv`: a TV shows the table: the minis are chips.
/// - `tumble-countdown`: the 3-2-1 before a round.
/// - `tumble-lobby`: the lobby, three seats, with the Cats pills.
/// - `tumble-junk`: boxes start four rows deep, so clears and junk come at once (the screenshots).
/// `-tumble-autoplay` makes this phone's box play itself through the scene's own input calls.
enum TumbleDemo {
    static func options(_ mode: DemoMode) -> TumbleDemoRoom.Options {
        var o = TumbleDemoRoom.Options()
        o.held = [.hairball, .scoop]
        switch mode {
        case .tumbleSix: o.seats = 6
        case .tumbleTwo: o.seats = 2
        case .tumbleCountdown: o.playing = false
        case .tumbleJunk:
            o.stack = 4
            o.held = [.hairball, .swipe, .nap, .bath]
        default: break
        }
        // UI tests and the frame gate: a cat thinks fast so things happen.
        if CommandLine.arguments.contains("-tumble-busy") {
            o.think = 500...900
            o.sloppy = 0.15
        }
        return o
    }

    static func room(_ mode: DemoMode) -> RoomView {
        if mode == .tumbleLobby { return lobby() }
        var room = TumbleDemoRoom(options(mode), now: TumbleTable.now()).room
        if mode == .tumbleTV { room.screen = true }
        return room
    }

    static func lobby() -> RoomView {
        RoomView(
            code: "TUMBLE", name: "Toy night", status: .lobby, youAreHost: true,
            seats: [
                SeatView(kind: .human, person: Person(id: "p0", name: "Sam", cat: 0), yours: true, presence: .awake),
                SeatView(kind: .human, person: Person(id: "p1", name: "Mia", cat: 2), presence: .awake),
                SeatView(kind: .bot), SeatView(kind: .open), SeatView(kind: .closed), SeatView(kind: .closed),
            ],
            gameId: GameID.tumble, options: RoomOptions(cats: .easy))
    }

    static func socket(_ mode: DemoMode) -> any RoomSocketing {
        if mode == .tumbleLobby { return DemoSocket(room: mode.room) }
        return TumbleDemoSocket(options: options(mode), tv: mode == .tumbleTV)
    }
}

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
