#if DEBUG
import PounceKit
import SwiftUI

/// DEBUG launch arguments `-tv-preview <cattower|tiles> [-seats N] [-aim]`: the TV's table for a
/// hand-made room (`DemoFixtures`), fed to a screen's store with no server, full screen. For
/// screenshots and for looking at the TV table before the shell around it exists. `-seats` is 2
/// to 6 for Cat Tower and 2 to 4 for Tuna Tiles; one player has a 20-character name and the scores
/// run to three digits. `-aim` adds the acting player's aim from their phone: a laid group in Cat
/// Tower, a draft adding pieces in Tuna Tiles. `-moment`: a second in, Kiki lays down (Cat Tower's
/// big moment). `-lost`: a second in, the TV loses the table ("Reconnecting"). `-cancel` (with
/// `-aim`): two seconds in, the player takes their aim back and no play follows. `-busy`: the table
/// keeps moving (the aim hops between groups or the draft comes and goes, a lay-down moment every
/// few seconds), for watching its frames with `-watchdog -watchdog-log`.
enum TVTablePreview {
    enum Game: String { case cattower, tiles, birdwatch, purrtrait }

    static func from(arguments: [String] = CommandLine.arguments) -> (game: Game, seats: Int, aim: Bool)? {
        guard let i = arguments.firstIndex(of: "-tv-preview"), let game = arguments[safe: i + 1].flatMap(Game.init) else { return nil }
        let seats = arguments.firstIndex(of: "-seats").flatMap { arguments[safe: $0 + 1] }.flatMap(Int.init)
        return (game, seats ?? (game == .cattower ? 6 : 4), arguments.contains("-aim"))
    }

    static let longName = "Great Aunt Josephine"

    /// Cat Tower for `seats` players, mid-round on seat 1's play step: most seats laid down (long
    /// runs and big sets), nobody's hand, a long name and three-digit scores.
    static func catTower(seats: Int) -> RoomView {
        let n = min(max(seats, 2), 6)
        var room = DemoFixtures.crowded()
        let laid = room.game!.laid
        room.seats = Array(room.seats.prefix(n)).map { seat in
            var seat = seat
            seat.yours = false
            return seat
        }
        if room.seats[1].kind == .human { room.seats[1].person?.name = longName }
        var game = room.game!
        game.turn = 1
        game.step = .play
        game.hands = [:]
        game.phase = Array(game.phase.prefix(n))
        game.scores = [245, 120, 5, 310, 75, 190].prefix(n).map { $0 }
        game.handCounts = Array([4, 1, 2, 3, 2, 2].prefix(n))
        game.pendingSkip = Array(repeating: false, count: n)
        // Seat 0 down with two sets; the others as crowded as `crowded()` has them.
        game.laid = Array(laid.prefix(n))
        func card(_ value: Int, _ coat: Coat) -> CardID { Coat.allCases.firstIndex(of: coat)! * 24 + value - 1 + 12 }
        game.laid[0] = [
            .set(cards: [card(6, .calico), card(6, .gray), card(6, .tuxedo)], value: 6),
            .run(cards: [card(3, .gray), card(4, .gray), card(5, .tabby), card(6, .tabby)], start: 3, end: 6),
        ]
        game.forfeited = Array(repeating: false, count: n)
        room.game = game
        room.youAreHost = false
        room.screen = true
        return room
    }

    /// Birdwatch for 4, 5 or 6 players as a TV sees it: mid-trick (four), the partner called and
    /// still hidden (five), bidding with a House Cat for someone who left (six). No hand, no
    /// choices and no partner mark: a screen's view never has them.
    static func birdwatch(seats: Int) -> RoomView {
        let demo: DemoFixtures.BirdDemo = switch seats {
        case 5: .partnerMark
        case 6: .six
        default: .play
        }
        var room = DemoFixtures.birdRoom(demo)
        room.seats = room.seats.map { seat in
            var seat = seat
            seat.yours = false
            return seat
        }
        if room.seats[1].kind == .human { room.seats[1].person?.name = longName }
        var view = room.birdwatch!
        view.hands = [:]
        view.playable = nil
        view.bidRange = nil
        view.fromNest = nil
        view.putBack = nil
        view.partnerChoices = nil
        view.youArePartner = nil
        room.birdwatch = view
        room.youAreHost = false
        room.screen = true
        return room
    }

    /// Tuna Tiles for `seats` players (2 to 4), mid-game on seat 1's move, nobody's stash.
    static func tiles(seats: Int) -> RoomView {
        let n = min(max(seats, 2), 4)
        let mid = DemoFixtures.tilesMid()
        var room = DemoFixtures.tilesRoom(
            seats: n, me: 0, turn: 1, turns: 31, table: mid.tiles!.table, rack: [], others: [6, 11, 8],
            opened: Array([true, true, true, false].prefix(n)))
        room.seats = room.seats.map { seat in
            var seat = seat
            seat.yours = false
            return seat
        }
        if room.seats[1].kind == .human { room.seats[1].person?.name = longName }
        room.tiles!.racks = [:]
        room.tiles!.rackCounts[0] = 9
        room.youAreHost = false
        room.screen = true
        return room
    }

    /// Seat 1's draft on its phone: the fish row grows to 7 and a new match of 11s goes down.
    static func tilesDraft(_ room: RoomView) -> [[TileID]] {
        var sets = room.tiles!.table
        sets[0].append(DemoFixtures.tile(7, .fish))
        sets.append([DemoFixtures.tile(11, .bell), DemoFixtures.tile(11, .feather), DemoFixtures.tile(11, .fish)])
        return sets
    }
}

/// A socket that never connects anywhere: the preview hands the store its events itself.
private actor PreviewSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation

    init() { (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self) }

    func start() async {}
    func send(_ m: ClientMessage) async throws {}
    func reconnectNow() async {}
    func stop() async { continuation.finish() }
}

/// The TV's table for a `TVTablePreview` room, full screen inside the TV-safe area.
struct TVTablePreviewView: View {
    let game: TVTablePreview.Game
    let seats: Int
    let aim: Bool
    @State private var table: Table?

    enum Table {
        case catTower(TableScene)
        case tiles(TilesScene)
        case birdwatch(BirdScene)
    }

    var body: some View {
        ZStack {
            Color(Palette.night)
            switch table {
            case .catTower(let scene): TableView(scene: scene)
            case .tiles(let scene): TilesTableView(scene: scene)
            case .birdwatch(let scene): BirdTableView(scene: scene)
            case nil: EmptyView()
            }
        }
        .ignoresSafeArea()
        .task { start() }
    }

    private func start() {
        guard table == nil else { return }
        MainThreadWatchdog.startIfAsked()
        let store = RoomStore(code: DemoFixtures.code, socket: PreviewSocket(), role: .screen)
        let room = switch game {
        case .tiles: TVTablePreview.tiles(seats: seats)
        case .birdwatch: TVTablePreview.birdwatch(seats: seats)
        case .cattower, .purrtrait: TVTablePreview.catTower(seats: seats)
        }
        switch game {
        case .purrtrait:
            return  // drawn by `TVDemoTableView` (PounceTVApp)
        case .birdwatch:
            let scene = BirdScene(store: store)
            table = .birdwatch(scene)
            Task {
                await BirdCardFactory.shared.prewarm()
                for await intent in store.intents { scene.enqueue(intent) }
            }
        case .cattower:
            let scene = TableScene(store: store)
            table = .catTower(scene)
            Task { for await intent in store.intents { scene.enqueue(intent) } }
        case .tiles:
            let scene = TilesScene(store: store)
            table = .tiles(scene)
            Task { for await intent in store.intents { scene.enqueue(intent) } }
        }
        store.handle(.connected)
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        let arguments = CommandLine.arguments
        if arguments.contains("-moment"), game == .cattower, let groups = room.game?.laid[safe: 2] ?? nil {
            Task {
                try? await Task.sleep(for: .seconds(1))
                store.handle(.message(.event(seq: 2, event: .game(.laidDown(seat: 2, groups: groups)))))
            }
        }
        if arguments.contains("-lost") {
            Task {
                try? await Task.sleep(for: .seconds(1))
                store.handle(.disconnected)
            }
        }
        if arguments.contains("-busy") {
            let draft = game == .tiles ? TVTablePreview.tilesDraft(room) : []
            Task {
                // The snapshot is seq 1 and `-moment`'s lay-down 2: each event is the one after (a
                // gap would be dropped).
                var seq = arguments.contains("-moment") ? 2 : 1
                for i in 1... {
                    try? await Task.sleep(for: .milliseconds(800))
                    if game == .tiles {
                        store.handle(.message(.aim(seat: 1, aim: i.isMultiple(of: 2) ? .table(draft) : nil)))
                    } else if i.isMultiple(of: 6), let groups = room.game?.laid[safe: 2] ?? nil {
                        seq += 1
                        store.handle(.message(.event(seq: seq, event: .game(.laidDown(seat: 2, groups: groups)))))
                    } else {
                        store.handle(.message(.aim(seat: 1, aim: .target(seat: 1, group: i % 2))))
                    }
                }
            }
        }
        guard aim else { return }
        let target: GameAim = game == .tiles ? .table(TVTablePreview.tilesDraft(room)) : .target(seat: 1, group: 0)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            store.handle(.message(.aim(seat: 1, aim: target)))
            guard arguments.contains("-cancel") else { return }
            try? await Task.sleep(for: .seconds(1.4))
            store.handle(.message(.aim(seat: 1, aim: nil)))
        }
    }
}
#endif
