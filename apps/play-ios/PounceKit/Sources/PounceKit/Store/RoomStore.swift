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
/// - At most one `act` is in flight. The snapshot that follows it (R13: every
///   successful action ends with one), an error, or a send that never left releases
///   it; its game events and a disconnect do not, so a quick second gesture can't
///   act on the room before the action's truth lands. A send that never left yields
///   `.rejected(.notSent)` so the scene rolls the provisional move back.
/// - With a server that has links (`room.link`), each `act` carries a move id and stays pending
///   until a snapshot lists it in `link.acks` (or an error refuses it). A snapshot that doesn't
///   list it keeps the lock; the first snapshot on a newer connection sends it again, same id,
///   which the server applies once. Without links, any snapshot releases the lock as before.
/// - `closed`, `notFound` and `needsUpdate` are terminal: later messages are ignored.
///   `stalled` survives snapshots too (the bot clock stays stopped), but the room
///   keeps updating.
@MainActor @Observable public final class RoomStore {
    public let code: String
    public private(set) var room: RoomView?
    public private(set) var phase: RoomPhase = .connecting
    /// -1 before the first snapshot.
    public private(set) var lastSeq = -1
    /// The seq up to which `room` holds every event's full effect (-1 before the first
    /// snapshot): the last snapshot's, or a presence event right after it (presence is
    /// folded in whole). Game events after it only fold in turn, step and status, so a
    /// table drawn from `room` shows events up to here, not up to `lastSeq`.
    public private(set) var settledSeq = -1
    public private(set) var actionInFlight = false
    public private(set) var connected = false
    /// The open connection's quality (`.link` socket events); `good` on every new connection.
    public private(set) var linkQuality: LinkQuality = .good
    /// The in-flight move, while the server hasn't acked it (only with a server that has links).
    public private(set) var pendingMove: PendingMove?
    public private(set) var moveCode: MoveCode?
    public private(set) var lastError: ErrorCode?
    /// Goes up whenever an applied room's round, turn or status differs from the previous one
    /// (see `TurnEpoch`), from snapshots and from the turn and status folded in from events.
    /// 0 before the first snapshot. Pass-and-play (`pass`) and the scene key a reveal on it, so
    /// a reveal never survives its turn.
    public private(set) var turnEpoch = 0
    /// Pass-and-play for this phone (spec §5.9), updated with every room the store applies, so
    /// the curtain always matches the room. Never from the shell's `onChange`: SwiftUI calls an
    /// `onChange` action at most once per frame and drops a second change in that frame, which
    /// left a pass-and-play seat's turn face down with no curtain until some later message.
    public private(set) var pass = PassAndPlay()
    /// The last `look` event (§9.4): who changed the table and to what. `serial` goes up with
    /// each, so the same look twice still floats its pill. Nil until one arrives.
    public private(set) var lookChange: LookChange?
    /// Play again's table (§10.4): from `{t:"rematch"}`, or a snapshot that already has one.
    public private(set) var rematch: String?
    /// Each `{t:"streak"}` for this device's people: pair, person, view. Set by the session.
    @ObservationIgnored public var onStreak: ((String, String, StreakView) -> Void)?

    /// This phone's connection as the table shows it.
    public enum Connection: Equatable, Sendable {
        case good, weak, reconnecting
    }

    public var connection: Connection {
        guard connected else { return .reconnecting }
        return linkQuality == .weak ? .weak : .good
    }

    /// A move sent and not yet acked, with the connection it was last sent on.
    public struct PendingMove: Equatable, Sendable {
        public let id: String
        public let seat: Seat
        public let action: Action
        fileprivate var connection: Int
    }

    public struct LookChange: Equatable, Sendable {
        public var seat: Seat
        public var look: Look
        public var serial: Int
    }
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
    @ObservationIgnored private var epochs = TurnEpoch()
    /// Connections opened so far: a pending move sent on an older one goes again.
    @ObservationIgnored private var connections = 0
    @ObservationIgnored private let makeMoveID: () -> String

    public init(code: String, socket: any RoomSocketing, makeMoveID: @escaping () -> String = { UUID().uuidString }) {
        self.code = code
        self.socket = socket
        self.makeMoveID = makeMoveID
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
        let id = room?.link != nil ? makeMoveID() : nil
        if let id { pendingMove = PendingMove(id: id, seat: seat, action: action, connection: connections) }
        let message = ClientMessage.act(seat: seat, action: action, id: id)
        callSocket(inOrder: true) { [weak self] socket in
            do {
                try await socket.send(message)
            } catch {
                guard let self, self.actionInFlight, self.actToken == token else { return }
                // A pending move waits for the next connection and goes again then.
                if let id, self.pendingMove?.id == id { return }
                // Never left the device: input must not stick, and the scene's
                // provisional move goes back (no server error will come for it).
                self.actionInFlight = false
                self.continuation.yield(.rejected(.notSent))
            }
        }
        return true
    }

    /// Sends a lobby, presence or move message. Never locks; replies arrive as
    /// snapshots (or an error that nopes the last control). Asking for a move code
    /// drops the one held, since the server replaces a seat's code.
    public func send(_ message: ClientMessage) {
        if case .moveSeat = message { moveCode = nil }
        callSocket(inOrder: true) { socket in try? await socket.send(message) }
    }

    // MARK: pass and play

    /// The hold on the curtain finished: that seat's hand shows, for this turn only.
    public func completeHold() {
        var next = pass
        next.completeHold()
        setPass(next)
    }

    /// Puts the curtain up for one of this phone's seats outside its turn.
    public func peek(_ seat: Seat) {
        var next = pass
        next.peek(seat)
        setPass(next)
    }

    /// Back to the table with no hand shown (a peek put away).
    public func hidePass() {
        var next = pass
        next.hide()
        setPass(next)
    }

    private func setPass(_ next: PassAndPlay) {
        if next != pass { pass = next }
    }

    // MARK: reducer

    public func handle(_ event: SocketEvent) {
        switch event {
        case .connecting:
            break
        case .connected:
            connected = true
            connections += 1
            if linkQuality != .good { linkQuality = .good }
        case .disconnected:
            connected = false  // keep actionInFlight: the reconnect snapshot clears it (or resends it)
        case .link(let quality):
            if linkQuality != quality { linkQuality = quality }
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
        case .streak(let pair, let person, let view):
            onStreak?(pair, person, view)
        case .rematch(let code):
            rematch = code
        case .link(let seats):
            applyLinks(seats)
        case .pong:
            break
        }
    }

    /// Folded into the room as is: not a state change, so no seq (the next snapshot agrees).
    private func applyLinks(_ links: [SeatLink?]) {
        guard var next = room else { return }
        for i in next.seats.indices {
            next.seats[i].link = links.indices.contains(i) ? links[i] : nil
        }
        guard next != room else { return }
        room = next
        continuation.yield(.link)
    }

    private func needsUpdate() {
        phase = .needsUpdate
        callSocket { await $0.stop() }
    }

    private func applySnapshot(seq: Int, room new: RoomView) {
        let previous = room?.status
        room = new
        if let code = new.rematch, rematch != code { rematch = code }
        lastSeq = seq
        settledSeq = seq
        settlePending(new)
        noteTurn()
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

    /// Releases the lock, unless a pending move isn't in this snapshot's acks yet: then it waits
    /// (its own snapshot or error is coming), or goes again if it was sent on an older connection.
    private func settlePending(_ new: RoomView) {
        guard var pending = pendingMove else {
            actionInFlight = false
            return
        }
        guard let link = new.link, !link.acks.contains(pending.id) else {
            pendingMove = nil
            actionInFlight = false
            return
        }
        guard pending.connection < connections else { return }
        pending.connection = connections
        pendingMove = pending
        let message = ClientMessage.act(seat: pending.seat, action: pending.action, id: pending.id)
        callSocket(inOrder: true) { socket in try? await socket.send(message) }
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
            if settledSeq == seq - 1 { settledSeq = seq }
            noteTurn()
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
            noteTurn()
            // actionInFlight stays: that snapshot releases it.
            continuation.yield(.game(game, seq: seq))
        case .look(let seat, let look):
            // Folded in whole, like presence: the snapshot that follows says the same.
            room?.look = look
            if settledSeq == seq - 1 { settledSeq = seq }
            lookChange = LookChange(seat: seat, look: look, serial: (lookChange?.serial ?? 0) + 1)
        }
    }

    /// After every room applied: the turn epoch, then pass-and-play for that room.
    private func noteTurn() {
        guard let room else { return }
        epochs.observe(room)
        if turnEpoch != epochs.value { turnEpoch = epochs.value }
        var next = pass
        next.update(TableModel(room: room), epoch: epochs.value)
        setPass(next)
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
            pendingMove = nil
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
