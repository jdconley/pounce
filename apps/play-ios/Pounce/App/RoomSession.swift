import Foundation
import Network
import Observation
import PounceKit

/// One open room: its `RoomStore`, the socket under it, and the connection rules around them
/// (spec §5.5, §7.4, §7.5). The store lives as long as the room screen; the socket goes down
/// in the background and comes back on return, so the lobby or table never resets.
///
/// - After every (re)connect's first snapshot: `presence active`.
/// - On the first snapshot: the auto-claim for the way the room was opened; refused (the seat
///   was taken first), it retries once on the next lobby snapshot, and never nopes.
/// - Snapshots of a room this device sits at go into the table cache (Home cards).
/// - The network path becoming satisfied again reconnects at once.
@MainActor @Observable
final class RoomSession {
    let code: String
    let intent: RoomIntent
    let store: RoomStore

    /// A first snapshot arrived (the room exists).
    private(set) var arrived = false
    /// Several connect attempts failed before the first snapshot: show the offline card.
    private(set) var offline = false
    /// Bumped by every refused lobby message; the lobby wiggles its last tapped control.
    private(set) var lobbyNope = 0
    /// Set by the app model when the room turned out closed or missing.
    var goneMeaning: NotFoundMeaning?

    /// A seat being moved here from another phone (spec §5.11).
    enum MoveClaim: Equatable {
        case claiming(String)
        case refused(String, ErrorCode)
    }
    /// Non-nil from sending `claimMove` until the seat arrives or the server refuses the code.
    private(set) var move: MoveClaim?
    @ObservationIgnored private var seatsBeforeMove: Set<Seat> = []

    // Hooks the app model fills in.
    @ObservationIgnored var owner: () -> Person? = { nil }
    @ObservationIgnored var onSnapshot: (RoomView) -> Void = { _ in }
    @ObservationIgnored var onArrive: () -> Void = {}
    @ObservationIgnored var onGone: (RoomPhase) -> Void = { _ in }

    @ObservationIgnored private let socket: SuspendableSocket
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var lifecycle: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var backgrounded = false
    @ObservationIgnored private var autoClaim = AutoClaim()
    /// Lobby nopes still to come from refused auto-claims: nobody tapped, so nothing wiggles.
    @ObservationIgnored private var silentNopes = 0
    @ObservationIgnored private var presencePending = false
    @ObservationIgnored private var goneReported = false
    @ObservationIgnored private var failedConnects = 0
    @ObservationIgnored private var tableSink: ((TableIntent) -> Void)?
    @ObservationIgnored private var pendingIntents: [TableIntent] = []

    private static let offlineAfterFailures = 3
    private static let pendingIntentLimit = 32

    init(code: String, intent: RoomIntent, socket: SuspendableSocket) {
        self.code = code
        self.intent = intent
        self.socket = socket
        store = RoomStore(code: code, socket: socket)
    }

    var model: TableModel? { store.room.map(TableModel.init(room:)) }

    // MARK: lifecycle

    func start() {
        guard !started, !closed else { return }
        started = true
        tasks.append(Task { await self.run() })
        tasks.append(Task { await self.routeIntents() })
        tasks.append(Task { [weak self] in await self?.watchNetwork() })
    }

    /// Stops the socket for good and ends every loop. Always called when leaving the room.
    func close() {
        guard !closed else { return }
        closed = true
        for task in tasks { task.cancel() }
        tasks.removeAll()
        let store = store
        Task { await store.close() }
    }

    /// `.background`: tell the room this device stepped away, then drop the socket.
    func background() {
        guard started, !closed, !backgrounded else { return }
        backgrounded = true
        let socket = socket
        let terminal = isTerminal
        enqueue {
            if !terminal { try? await socket.send(.presence(.background)) }
            await socket.suspend()
        }
    }

    /// `.active` after `.background`: connect again; presence follows the snapshot.
    func foreground() {
        guard started, !closed, backgrounded else { return }
        backgrounded = false
        presencePending = true
        let socket = socket
        enqueue { await socket.resume() }
    }

    /// The offline card's retry.
    func retry() {
        offline = false
        failedConnects = 0
        let socket = socket
        Task { await socket.reconnectNow() }
    }

    /// Sends a lobby message (claim, configure, start, leave). Replies come back as snapshots.
    func send(_ message: ClientMessage) {
        store.send(message)
    }

    /// The table scene takes the store's intents from here, in order. `sink` must enqueue
    /// synchronously (the scene's serialized play queue): intents that arrived with no table
    /// attached (the lobby → playing `versusIntro`, say) are handed over right here, before
    /// any live intent can be, so the two can never interleave.
    func attachTable(_ sink: @escaping (TableIntent) -> Void) {
        tableSink = sink
        let pending = pendingIntents
        pendingIntents.removeAll()
        for intent in pending { sink(intent) }
    }

    func detachTable() {
        tableSink = nil
    }

    // MARK: loops

    /// `RoomStore.run()`, with a look at each event after the store applied it.
    private func run() async {
        await socket.start()
        for await event in socket.events {
            store.handle(event)
            after(event)
        }
        reportGoneIfNeeded()
    }

    private func routeIntents() async {
        for await intent in store.intents {
            if case .lobbyNope(let code) = intent {
                if silentNopes > 0 {
                    silentNopes -= 1  // a refused auto-claim: retried, never noped
                } else if !moveRefused(code) {
                    lobbyNope += 1
                }
            } else if let tableSink {
                tableSink(intent)
            } else {
                buffer(intent)
            }
        }
        #if DEBUG
        print("[session] intents ended")
        #endif
    }

    /// Keeps an intent for a table that isn't attached. A snapshot (`.reconcile`) is the whole
    /// truth, so it supersedes everything before it, except a `versusIntro` that still has to
    /// play: the backlog becomes that intro and what came after it, or just this snapshot. In
    /// the lobby that keeps one reconcile instead of one per lobby change.
    private func buffer(_ intent: TableIntent) {
        switch intent {
        case .versusIntro:
            pendingIntents = [.versusIntro]
        case .reconcile:
            if let intro = pendingIntents.lastIndex(of: .versusIntro) {
                pendingIntents.removeFirst(intro)
            } else {
                pendingIntents.removeAll()
            }
            pendingIntents.append(.reconcile)
        default:
            pendingIntents.append(intent)
        }
        if pendingIntents.count > Self.pendingIntentLimit {
            // Never drop the intro.
            let drop = pendingIntents.first == .versusIntro ? 1 : 0
            pendingIntents.remove(at: drop)
        }
    }

    /// Reconnects when the network comes back after being down (spec §7.4).
    private func watchNetwork() async {
        var wasSatisfied = true
        for await path in NWPathMonitor() {
            let satisfied = path.status == .satisfied
            if satisfied && !wasSatisfied && !backgrounded {
                await socket.reconnectNow()
            }
            wasSatisfied = satisfied
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = lifecycle
        lifecycle = Task {
            await previous?.value
            await work()
        }
    }

    // MARK: per event

    private func after(_ event: SocketEvent) {
        switch event {
        case .connected:
            presencePending = true
            failedConnects = 0
        case .disconnected:
            if !arrived && !backgrounded {
                failedConnects += 1
                if failedConnects >= Self.offlineAfterFailures { offline = true }
            }
        case .message(.snapshot(_, _, let room)):
            snapshotArrived(room)
        case .message(.error(let code)):
            if autoClaim.refused(code) { silentNopes += 1 }
        default:
            break
        }
        reportGoneIfNeeded()
    }

    private func snapshotArrived(_ room: RoomView) {
        offline = false
        if !arrived {
            arrived = true
            onArrive()
        }
        if presencePending && !backgrounded {
            presencePending = false
            send(.presence(.active))
        }
        let model = TableModel(room: room)
        moveSnapshot(model)
        if let claim = autoClaim.snapshot(model, owner: owner(), first: { firstClaim(model) }) {
            send(claim)
        }
        if !model.mySeats.isEmpty { onSnapshot(room) }
    }

    /// What to send on the first snapshot, by how the room was opened.
    private func firstClaim(_ model: TableModel) -> ClientMessage? {
        guard let owner = owner() else { return nil }
        switch intent {
        case .create:
            // The host sits on seat 0.
            if model.room.status == .lobby, model.mySeats.isEmpty, model.room.seats.first?.kind == .open {
                return .claim(seat: 0, person: owner)
            }
            return RoomEntry.autoClaim(model: model, owner: owner)
        case .join, .rejoin:
            return RoomEntry.autoClaim(model: model, owner: owner)
        case .move(let moveCode):
            beginMove(moveCode, seats: model.mySeats)
            return .claimMove(code: moveCode)
        }
    }

    // MARK: move my seat (receiving phone)

    /// Claims a seat moved from another phone with its 6-character code (spec §5.11).
    func claimMove(_ moveCode: String) {
        beginMove(moveCode, seats: model?.mySeats ?? [])
        send(.claimMove(code: moveCode))
    }

    private func beginMove(_ moveCode: String, seats: [Seat]) {
        move = .claiming(moveCode)
        seatsBeforeMove = Set(seats)
    }

    /// While claiming: a snapshot with a new seat of mine means it worked.
    private func moveSnapshot(_ model: TableModel) {
        guard case .claiming = move, !Set(model.mySeats).subtracting(seatsBeforeMove).isEmpty else { return }
        move = nil
    }

    /// While claiming: the server refused the code.
    private func moveRefused(_ code: ErrorCode) -> Bool {
        guard case .claiming(let moveCode) = move,
              code == .badCode || code == .tooManyAttempts || code == .gameOver else { return false }
        move = .refused(moveCode, code)
        return true
    }

    private var isTerminal: Bool {
        switch store.phase {
        case .closed, .notFound, .needsUpdate: true
        default: false
        }
    }

    private func reportGoneIfNeeded() {
        guard !goneReported, store.phase == .closed || store.phase == .notFound else { return }
        goneReported = true
        onGone(store.phase)
    }
}
