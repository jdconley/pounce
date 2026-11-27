import Foundation
import Network
import Observation
import PounceKit

/// The table this TV shows, joined as its screen: the room's store, the socket under it, and
/// the table's scene once the game is on. The socket goes down in the background and comes
/// back on return, so the store and the scene live as long as the TV shows this table.
@MainActor @Observable
final class TVRoom {
    let code: String
    let store: RoomStore

    /// The table's scene, made when the game starts (or when the TV arrives mid-game).
    enum Scene {
        case catTower(TableScene)
        case tiles(TilesScene)
        case birdwatch(BirdScene)
        case tumble(TumbleScene)
    }

    /// Toy Tumble's boxes, replayed from the live stream (a screen has no box of its own).
    let tumble: TumbleTable

    private(set) var scene: Scene?

    /// After every socket event the store applied: the TV's model reads the room's news.
    @ObservationIgnored var onChange: (TVRoom) -> Void = { _ in }
    /// The table finished cheering the game's end (the scenes' `onGameOver`).
    @ObservationIgnored var onGameOver: ([Seat]) -> Void = { _ in }

    @ObservationIgnored private let socket: SuspendableSocket
    @ObservationIgnored private let watchesNetwork: Bool
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var asleep = false
    /// Intents that came before the scene, handed to it when it's made (`RoomSession.buffer`).
    @ObservationIgnored private var pending: [TableIntent] = []

    private static let pendingLimit = 32

    init(code: String, socket: @escaping @Sendable (String) -> any RoomSocketing, watchesNetwork: Bool) {
        self.code = code
        self.socket = SuspendableSocket { socket(code) }
        self.watchesNetwork = watchesNetwork
        let store = RoomStore(code: code, socket: self.socket, role: .screen)
        self.store = store
        // A screen can't ask for a sync: a missed relay reconnects, and the server syncs every box.
        let suspendable = self.socket
        tumble = TumbleTable(screen: true) { message in
            if case .tumble(_, let ev) = message, ev.isEmpty { Task { await suspendable.reconnectNow() } }
        }
        let tumble = self.tumble
        store.onTumble = { live in tumble.receive(live, now: TumbleTable.now()) }
    }

    /// The table drawn by a game this build knows, whichever the room plays.
    var isTiles: Bool { store.room?.gameId == GameCatalog.tiles.id }
    var isBirdwatch: Bool { store.room?.gameId == GameCatalog.birdwatch.id }
    var isTumble: Bool { store.room?.gameId == GameCatalog.tumble.id }

    /// The TV has the room, and lost its connection to it.
    var reconnecting: Bool { store.room != nil && !store.connected }

    // MARK: lifecycle

    func start() {
        guard !started, !closed else { return }
        started = true
        tasks.append(Task { [weak self, socket] in
            await socket.start()
            for await event in socket.events {
                guard let self, !self.closed else { return }
                self.store.handle(event)
                if case .message(.snapshot(_, _, let room)) = event, room.isTumble {
                    self.tumble.update(room: room, now: TumbleTable.now())
                }
                self.onChange(self)
            }
        })
        tasks.append(Task { [weak self, store] in
            for await intent in store.intents {
                guard let self else { return }
                self.route(intent)
            }
        })
        if watchesNetwork {
            tasks.append(Task { [weak self] in await self?.watchNetwork() })
        }
    }

    /// Closes the screen socket for good. Returns once it is closed.
    func close() async {
        guard !closed else { return }
        closed = true
        for task in tasks { task.cancel() }
        tasks.removeAll()
        await store.close()
    }

    /// The app went to the background: the socket closes, and the phones see the TV go after
    /// their grace period.
    func suspend() async {
        guard started, !closed, !asleep else { return }
        asleep = true
        await socket.suspend()
    }

    /// Back from the background: the TV joins the same table again as its screen.
    func resume() async {
        guard started, !closed, asleep else { return }
        asleep = false
        await socket.resume()
    }

    /// Makes the table's scene for the room's game, once.
    func openTable() {
        guard scene == nil, !closed, store.room != nil else { return }
        let finished: ([Seat]) -> Void = { [weak self] winners in self?.gameOver(winners) }
        if isTumble {
            let scene = TumbleScene(store: store, table: tumble)
            scene.onGameOver = finished
            self.scene = .tumble(scene)
        } else if isBirdwatch {
            let bird = BirdScene(store: store)
            bird.onGameOver = finished
            scene = .birdwatch(bird)
        } else if isTiles {
            let tiles = TilesScene(store: store)
            tiles.onGameOver = finished
            scene = .tiles(tiles)
        } else {
            let table = TableScene(store: store)
            table.onGameOver = finished
            scene = .catTower(table)
        }
        let backlog = pending
        pending.removeAll()
        for intent in backlog { enqueue(intent) }
    }

    /// The table finished cheering the game's end.
    func gameOver(_ winners: [Seat]) {
        guard !closed else { return }
        onGameOver(winners)
    }

    // MARK: intents

    private func route(_ intent: TableIntent) {
        if scene != nil {
            enqueue(intent)
        } else {
            buffer(intent)
        }
    }

    private func enqueue(_ intent: TableIntent) {
        switch scene {
        case .catTower(let table): table.enqueue(intent)
        case .tiles(let tiles): tiles.enqueue(intent)
        case .birdwatch(let bird): bird.enqueue(intent)
        case .tumble, nil: break
        }
    }

    /// As `RoomSession.buffer`: a snapshot supersedes what came before it, except a versus intro
    /// still to play.
    private func buffer(_ intent: TableIntent) {
        switch intent {
        case .versusIntro:
            pending = [.versusIntro]
        case .reconcile:
            if let intro = pending.lastIndex(of: .versusIntro) {
                pending.removeFirst(intro)
            } else {
                pending.removeAll()
            }
            pending.append(.reconcile)
        default:
            pending.append(intent)
        }
        if pending.count > Self.pendingLimit {
            pending.remove(at: pending.first == .versusIntro ? 1 : 0)
        }
    }

    /// Reconnects when the network comes back after being down.
    private func watchNetwork() async {
        var wasSatisfied = true
        for await path in NWPathMonitor() {
            let satisfied = path.status == .satisfied
            if satisfied && !wasSatisfied && !asleep && !closed {
                await socket.reconnectNow()
            }
            wasSatisfied = satisfied
        }
    }
}
