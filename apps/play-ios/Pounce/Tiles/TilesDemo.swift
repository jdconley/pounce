#if DEBUG
import Foundation
import PounceKit
import SwiftUI

/// The tile game's DEBUG demos (`-demo tiles…`): the real table fed by a fake socket that runs a
/// whole game on the device (`TilesLocalGame`), so every screen draws, and a turn can be played
/// against the local House Cat, with no server. Nothing in Home starts the game yet: these
/// launch arguments are the only way in.
///
/// - `tiles`: the middle of a four-seat game, my move, already opened.
/// - `tiles-early`: before my opening (the rug locked, the opening meter); `tiles-opened`: the
///   same table after it.
/// - `tiles-draft`: `tiles` with a valid turn half built (two pieces placed, a Yarn swapped out);
///   `tiles-invalid`: with a set that isn't one yet; `tiles-loupe`: with a set open in the loupe.
/// - `tiles-late`: 25 sets on the rug and 22 pieces in the stash; `tiles-long`: a row of thirteen.
/// - `tiles-pass`: the toy box empty; `tiles-other`: Kiki's move, then the House Cat's (watch
///   other seats play); `tiles-curtain`: two seats on this phone; `tiles-over`: a finished game.
/// - `tiles-play`: a fresh two-seat game against the local House Cat, from the deal.
/// - `tiles-last`: my last three pieces, each of which fits a row: play them all and win (the How
///   to play video's ending).
///
/// `tiles-over -tiles-game-off`: Play again is refused with `game_off` (the server stopped dealing
/// the game), and the card says no new table can be dealt.
///
/// Add `-tiles-easy` for easy mode (as a kitten gets it), `-tiles-tricks` for its tricks,
/// `-tiles-hint` to light its hint, `-tiles-recap` to play "what changed" back,
/// `-tiles-sheet` for the piece sheet (every piece at stash and rug size, both designs) and
/// `-piece-style flat` for the design that wasn't chosen.
enum TilesDemo {
    static func room(_ mode: DemoMode) -> RoomView {
        switch mode {
        case .tilesEarly: DemoFixtures.tilesEarly()
        case .tilesOpened: DemoFixtures.tilesEarly(opened: true)
        case .tilesLate: DemoFixtures.tilesLate()
        case .tilesLong: DemoFixtures.tilesLong()
        case .tilesPass: DemoFixtures.tilesPass()
        case .tilesOther: DemoFixtures.tilesOther()
        case .tilesCurtain: DemoFixtures.tilesCurtain()
        case .tilesOver: DemoFixtures.tilesOver()
        case .tilesPlay: fresh()
        case .tilesLast: DemoFixtures.tilesLast()
        default: DemoFixtures.tilesMid()
        }
    }

    /// A new two-seat game against the House Cat, dealt the same way every time.
    static func fresh() -> RoomView {
        let game = TilesLocalGame(seats: 2, seed: 20261111)
        var room = DemoFixtures.tilesRoom(seats: 2, turns: 0, table: [], rack: [], others: [14], opened: [false, false])
        room.seats[1] = SeatView(kind: .bot)
        room.tiles = game.view(for: [0])
        return room
    }

    static func socket(_ mode: DemoMode) -> any RoomSocketing {
        let room = room(mode)
        let game = mode == .tilesPlay ? TilesLocalGame(seats: 2, seed: 20261111) : room.tiles.map { TilesLocalGame(view: $0, seed: 7) }
        return TilesDemoSocket(room: room, game: game)
    }

    /// Sets a demo's turn up once the table is on screen.
    @MainActor
    static func stage(_ scene: TilesScene) {
        guard let mode = DemoMode.from() else { return }
        let t = DemoFixtures.tile
        switch mode {
        case .tilesDraft:
            scene.apply([t(7, .fish, 0)], to: .set(0))
            scene.apply([t(13, .mouse, 0)], to: .set(2))
            scene.apply([t(7, .bell, 0)], to: .set(5))
        case .tilesInvalid:
            scene.apply([t(7, .fish, 0)], to: .set(0))
            scene.apply([t(11, .bell, 0), t(13, .fish, 0)], to: .newSet())
            scene.apply([t(1, .mouse, 0)], to: .set(4))
        case .tilesLoupe:
            scene.apply([t(7, .fish, 0)], to: .set(0))
            scene.openLoupe(0)
        default:
            break
        }
        if CommandLine.arguments.contains("-tiles-select") {
            // Two stash pieces picked up, for the tap path's screenshot.
            scene.selection = Array(scene.rackShown.prefix(2))
            scene.redraw()
        }
        if CommandLine.arguments.contains("-tiles-hint") { scene.showHint() }
        if CommandLine.arguments.contains("-tiles-recap") {
            // As if Leo and Kiki had played since my last turn.
            var recap = TilesRecap()
            if let table = scene.model?.view.table, table.count > 4 {
                recap.note(.played(seat: 1, table: table, placed: Array(table[2].suffix(2)), opened: false), mine: [0])
                recap.note(.played(seat: 2, table: table, placed: table[4], opened: true), mine: [0])
            }
            scene.recap = recap
            scene.redraw()
            scene.showRecap()
        }
    }
}

/// A room socket that runs a tile game on the device: it answers each turn as the server would
/// (the events, then a snapshot) and plays every seat that isn't on this phone with the local
/// House Cat.
actor TilesDemoSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private var room: RoomView
    private var game: TilesLocalGame?
    private var seq = 1
    private var bots: Task<Void, Never>?
    private var started = false

    init(room: RoomView, game: TilesLocalGame?) {
        self.room = room
        self.game = game
        (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    private var mine: [Seat] { room.seats.indices.filter { room.seats[$0].yours } }

    func start() async {
        continuation.yield(.connected)
        continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
        guard !started else { return }
        started = true
        runBots()
    }

    func send(_ m: ClientMessage) async throws {
        if case .rematch = m {
            // `-tiles-game-off`: as a server that stopped dealing the game answers Play again.
            // Without it nothing answers, as when the deal fails.
            try? await Task.sleep(for: Pace.duration(.milliseconds(300)))
            if CommandLine.arguments.contains("-tiles-game-off") { continuation.yield(.message(.error(.gameOff))) }
            return
        }
        guard case .actTiles(let seat, let action, _) = m else { return }
        try? await Task.sleep(for: Pace.duration(.milliseconds(250)))
        act(seat: seat, action)
        runBots()
    }

    func reconnectNow() async {}

    func stop() async {
        bots?.cancel()
        continuation.finish()
    }

    /// One action as the server answers it: an error, or the events and then a snapshot.
    private func act(seat: Seat, _ action: TilesAction) {
        guard var game else { return }
        switch game.apply(seat: seat, action) {
        case .failure(let refused):
            print("[tiles] refused \(action): \(refused.code.rawValue)")
            continuation.yield(.message(.error(refused.code)))
        case .success(let events):
            self.game = game
            let mine = mine
            for event in events {
                seq += 1
                continuation.yield(.message(.event(seq: seq, event: .tiles(TilesLocalGame.event(event, for: mine)))))
            }
            room.tiles = game.view(for: mine)
            if game.status == .gameOver { room.status = .over }
            continuation.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
            print("[tiles] seat \(seat) \(Self.name(action)) -> turn \(game.turn) rug \(game.table.count) sets, racks \(game.racks.map(\.count))")
        }
    }

    private static func name(_ action: TilesAction) -> String {
        switch action {
        case .draw: "drew"
        case .pass: "passed"
        case .forfeit: "forfeited"
        case .play(let table): "played \(table.count) sets"
        }
    }

    /// While the move belongs to a seat that isn't on this phone, the House Cat takes it after a
    /// moment, as the server's does.
    private func runBots() {
        bots?.cancel()
        bots = Task {
            while !Task.isCancelled {
                guard let game = await self.game, game.status == .playing, !(await self.mine).contains(game.turn) else { return }
                try? await Task.sleep(for: Pace.duration(.milliseconds(1400)))
                guard !Task.isCancelled else { return }
                await self.botTurn()
            }
        }
    }

    private func botTurn() {
        guard let game, game.status == .playing, !mine.contains(game.turn) else { return }
        act(seat: game.turn, game.botAction(game.turn))
    }
}

/// Every piece at stash size and at rug size, in both designs, for judging them side by side on
/// a real screen (`-tiles-sheet`).
struct TilesPieceSheet: View {
    private func row(_ style: TilePieceStyle, _ suit: TileSuit, width: CGFloat) -> some View {
        HStack(spacing: 1) {
            ForEach([8, 10, 13], id: \.self) { value in
                piece(Tile.id(value, suit), style: style, width: width)
            }
            piece(Tile.yarnIDs[0], style: style, width: width, standing: TileStanding(value: 6, suit: suit))
        }
    }

    private func piece(_ tile: TileID, style: TilePieceStyle, width: CGFloat, standing: TileStanding? = nil) -> some View {
        let factory = TilePieceFactory.shared
        factory.style = style
        let texture = factory.face(tile, size: width >= 42 ? .large : .small, standing: standing)
        factory.style = TilePieceStyle.current
        return Image(uiImage: UIImage(cgImage: texture.cgImage(), scale: UIScreen.main.scale, orientation: .up))
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: (width * TilesLayout.pieceAspect).rounded())
    }

    private func column(_ style: TilePieceStyle) -> some View {
        VStack(spacing: 12) {
            OutlinedText(style == .token ? "A: token" : "B: flat", size: 18, fill: Palette.orange)
            ForEach([CGFloat(48), 30, 24], id: \.self) { width in
                VStack(spacing: 3) {
                    ForEach(TileSuit.allCases, id: \.self) { suit in row(style, suit, width: width) }
                }
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            column(.token).frame(maxWidth: .infinity)
            column(.flat).frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Image(ArtName.Tiles.rug).resizable().ignoresSafeArea())
        .background(Palette.night.ignoresSafeArea())
        .accessibilityIdentifier("tiles.sheet")
    }
}
#endif
