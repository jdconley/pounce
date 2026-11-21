import Foundation
import Observation
import PounceKit

/// Tonight's board on the TV: one board socket, the board it shows (`TVBoardState`), and the clock
/// that ends the watch card, a watched result and a cheer. The TV's model owns one while the board
/// is on screen, as it owns a table (`TVRoom`): a new one per connection, so going to the
/// background and back makes another.
@MainActor @Observable
final class TVBoard {
    let token: String
    private(set) var state = TVBoardState()
    private(set) var online = false
    private(set) var everConnected = false

    /// The server no longer knows this board.
    @ObservationIgnored var onGone: (() -> Void)?
    /// A result landed (`solved`: a run that finished well), or someone offered a run.
    @ObservationIgnored var onCheer: ((Bool) -> Void)?
    @ObservationIgnored var onOffer: (() -> Void)?

    @ObservationIgnored private let socket: any BoardSocketing
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(token: String, socket: any BoardSocketing, now: @escaping @Sendable () -> Date) {
        self.token = token
        self.socket = socket
        self.now = now
    }

    func start() {
        guard reader == nil else { return }
        let socket = socket
        reader = Task { [weak self] in
            await socket.start()
            for await event in socket.events {
                guard !Task.isCancelled else { return }
                self?.handle(event)
            }
        }
    }

    /// Closes the socket. Returns once it's closed.
    func close() async {
        reader?.cancel()
        reader = nil
        timer?.cancel()
        timer = nil
        await socket.stop()
    }

    func watch() { change { $0.watch() } }
    func notNow() { change { $0.notNow() } }
    func stopWatching() { change { $0.stopWatching() } }

    /// Moves the clock on (tests, and the timer).
    func tick() { change { $0.tick(now: now()) } }

    private func handle(_ event: BoardSocketEvent) {
        switch event {
        case .online:
            online = true
            everConnected = true
        case .offline:
            online = false
        case .gone:
            onGone?()
        case .message(let message):
            change { $0.apply(message, now: now()) }
            if case .result(_, let result) = message { onCheer?(result.finished) }
            if case .watchOffer = message { onOffer?() }
        }
    }

    private func change(_ edit: (inout TVBoardState) -> Void) {
        let work = FrameWork("tv.board.change"); defer { work.end() }
        var next = state
        edit(&next)
        if next != state { state = next }
        schedule()
    }

    /// One timer, for the next thing time ends.
    private func schedule() {
        timer?.cancel()
        timer = nil
        guard let at = state.nextTick else { return }
        let wait = max(0, at.timeIntervalSince(now()))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }
}
