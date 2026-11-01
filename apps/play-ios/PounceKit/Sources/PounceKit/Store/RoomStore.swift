import Foundation
import Observation

/// The live state of one room, kept by applying the server's protocol-1 client
/// contract (spec §7.3) to the socket's events, plus the ordered animation
/// intents the table scene plays.
///
/// - Every protocol-1 snapshot is applied, even one whose `seq` equals `lastSeq`
///   (the reconnect snapshot after a drop), and clears the in-flight lock.
/// - Events apply only when `seq == lastSeq + 1`; older ones are ignored and a gap
///   drops the event and reconnects for a fresh snapshot. Events animate; the
///   server follows every game action with a snapshot at the seq of its last
///   event, which carries the truth. Only turn, step and status are folded in
///   from events, so the scene's timing is right before that snapshot lands.
/// - At most one `act` is in flight. A game event, an error, a snapshot or a send
///   that never left releases it; a disconnect does not.
/// - `closed`, `notFound` and `needsUpdate` are terminal: later messages are ignored.
///   `stalled` survives snapshots too (the bot clock stays stopped), but the room
///   keeps updating.
@MainActor @Observable public final class RoomStore {
    public let code: String
    public private(set) var room: RoomView?
    public private(set) var phase: RoomPhase = .connecting
    /// -1 before the first snapshot.
    public private(set) var lastSeq = -1
    public private(set) var actionInFlight = false
    public private(set) var connected = false
    public private(set) var moveCode: MoveCode?
    public private(set) var lastError: ErrorCode?
    /// Single consumer (the table scene). Unbounded, so no intent is ever dropped.
    @ObservationIgnored public let intents: AsyncStream<TableIntent>

    @ObservationIgnored private let continuation: AsyncStream<TableIntent>.Continuation
    @ObservationIgnored private let socket: any RoomSocketing
    /// Bumped by every `act`, so a late send failure only releases its own lock.
    @ObservationIgnored private var actToken = 0
    /// Socket calls still running; each removes itself when done.
    @ObservationIgnored private var socketTasks: [Int: Task<Void, Never>] = [:]
    /// The last send queued; each send waits for the one before it, so the server
    /// sees messages in the order they were made.
    @ObservationIgnored private var lastSend: Task<Void, Never>?
    @ObservationIgnored private var nextTaskID = 0

    public init(code: String, socket: any RoomSocketing) {
        self.code = code
        self.socket = socket
        (intents, continuation) = AsyncStream.makeStream(of: TableIntent.self, bufferingPolicy: .unbounded)
    }

    /// Starts the socket and applies its events until the stream ends.
    public func run() async {
        await socket.start()
        for await event in socket.events {
            handle(event)
        }
    }

    /// Stops the socket and ends `intents`.
    public func close() async {
        await socket.stop()
        continuation.finish()
    }

    /// Sends one game action, locking game input until the server answers.
    /// Returns false, sending nothing, while another action is in flight or
    /// outside play.
    @discardableResult public func act(seat: Seat, _ action: Action) -> Bool {
        guard !actionInFlight, phase == .playing else { return false }
        actionInFlight = true
        actToken += 1
        let token = actToken
        let message = ClientMessage.act(seat: seat, action: action)
        callSocket(inOrder: true) { [weak self] socket in
            do {
                try await socket.send(message)
            } catch {
                // Never left the device: nothing to reject, but input must not stick.
                guard let self, self.actionInFlight, self.actToken == token else { return }
                self.actionInFlight = false
            }
        }
        return true
    }

    /// Sends a lobby, presence or move message. Never locks; replies arrive as
    /// snapshots (or an error that nopes the last control).
    public func send(_ message: ClientMessage) {
        callSocket(inOrder: true) { socket in try? await socket.send(message) }
    }

    // MARK: reducer

    public func handle(_ event: SocketEvent) {
        switch event {
        case .connecting:
            break
        case .connected:
            connected = true
        case .disconnected:
            connected = false  // keep actionInFlight: the reconnect snapshot clears it
        case .notFound:
            connected = false
            if !isTerminal { phase = .notFound }
        case .closed:
            connected = false
            if !isTerminal { phase = .closed }
        case .message(let message):
            guard !isTerminal else { return }
            apply(message)
        }
    }

    private var isTerminal: Bool {
        switch phase {
        case .closed, .notFound, .needsUpdate: true
        default: false
        }
    }

    private func apply(_ message: ServerMessage) {
        switch message {
        case .snapshot(let version, let seq, let room):
            guard version == PounceKit.protocolVersion else { return needsUpdate() }
            applySnapshot(seq: seq, room: room)
        case .unsupportedProtocol:
            needsUpdate()
        case .event(let seq, let event):
            applyEvent(seq: seq, event: event)
        case .moveCode(let seat, let code):
            moveCode = MoveCode(seat: seat, code: code)
        case .error(let code):
            applyError(code)
        }
    }

    private func needsUpdate() {
        phase = .needsUpdate
        callSocket { await $0.stop() }
    }

    private func applySnapshot(seq: Int, room new: RoomView) {
        let previous = room?.status
        room = new
        lastSeq = seq
        actionInFlight = false
        if phase != .stalled {
            switch new.status {
            case .lobby: phase = .lobby
            case .playing: phase = .playing
            case .over: phase = .over
            }
        }
        if previous == .lobby && new.status == .playing {
            continuation.yield(.versusIntro)
        }
        continuation.yield(.reconcile)
    }

    private func applyEvent(seq: Int, event: RoomEvent) {
        guard lastSeq >= 0, seq > lastSeq else { return }  // before any snapshot, or already covered
        guard seq == lastSeq + 1 else {
            callSocket { await $0.reconnectNow() }  // gap: the server never replays
            return
        }
        lastSeq = seq
        switch event {
        case .presence(let seat, let presence):
            if let room, room.seats.indices.contains(seat) {
                self.room?.seats[seat].presence = presence
            }
            continuation.yield(.presence(seat: seat, presence: presence))
        case .game(let game):
            switch game {
            case .turn(let seat):
                room?.game?.turn = seat
                room?.game?.step = .draw
            case .roundOver:
                room?.game?.status = .roundOver
            case .gameOver:
                room?.game?.status = .gameOver
            default:
                break  // the snapshot that follows this action carries the rest
            }
            actionInFlight = false
            continuation.yield(.game(game, seq: seq))
        }
    }

    private func applyError(_ code: ErrorCode) {
        lastError = code
        if code == .roomClosed {
            phase = .closed
            callSocket { await $0.stop() }
        } else if code == .botStalled {
            phase = .stalled
        } else if actionInFlight {
            actionInFlight = false
            continuation.yield(.rejected(code))
        } else {
            continuation.yield(.lobbyNope(code))
        }
    }

    // MARK: socket calls

    /// Runs a socket call off the synchronous reducer, tracked until it finishes.
    /// `inOrder` calls (sends) run one at a time in call order; the others
    /// (`stop`, `reconnectNow`) start at once.
    private func callSocket(
        inOrder: Bool = false, _ body: @escaping @MainActor (any RoomSocketing) async -> Void
    ) {
        let id = nextTaskID
        nextTaskID += 1
        let socket = self.socket
        let previous = inOrder ? lastSend : nil
        let task = Task { [weak self] in
            await previous?.value
            await body(socket)
            self?.socketTasks[id] = nil
        }
        socketTasks[id] = task
        if inOrder { lastSend = task }
    }

    /// Waits until every socket call made so far (and any they lead to) has finished.
    func settle() async {
        while let task = socketTasks.values.first {
            await task.value
        }
    }
}
