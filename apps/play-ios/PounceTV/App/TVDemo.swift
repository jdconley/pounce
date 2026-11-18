#if DEBUG
import Foundation
import notify
import PounceKit
import SwiftUI

/// DEBUG `-demo <name>`: the TV with no server, for the UI tests on the Apple TV simulator
/// (`PounceTVUITests`) and `scripts/frame-rate.sh PLATFORM=tvOS`, as the iPhone's `-demo` tables.
///
/// - `tv-hit` (Cat Tower, `-seats` 2 to 6, default 6) and `tv-tiles` (Tuna Tiles, `-seats` 2 to 4,
///   default 4): `TVTablePreview`'s room, shown through the TV's own table path (`TVRoom`,
///   `TableHost`) on a fake socket that plays the game: turns, draws, aims from the phones, hits,
///   discards, lay-downs and plays, over and over.
/// - `tv-shell`: the whole TV (`TVRoot`) on fake services. Home shows a link; a poster makes a
///   table whose lobby is empty until the test says so: the first `Live.releaseDemo` seats
///   everyone, the second starts the game, and `Live.endDemo` ends it.
enum TVDemo: Equatable {
    case table(TVTablePreview.Game, seats: Int)
    case shell

    static func from(arguments: [String] = CommandLine.arguments) -> TVDemo? {
        guard let i = arguments.firstIndex(of: "-demo"), let name = arguments[safe: i + 1] else { return nil }
        let seats = arguments.firstIndex(of: "-seats").flatMap { arguments[safe: $0 + 1] }.flatMap(Int.init)
        switch name {
        case "tv-hit": return .table(.cattower, seats: seats ?? 6)
        case "tv-tiles": return .table(.tiles, seats: seats ?? 4)
        case "tv-shell": return .shell
        default: return nil
        }
    }

    /// The table a demo plays: `TVTablePreview`'s, nobody's hand, at `code`.
    static func room(tiles: Bool, seats: Int? = nil, code: String) -> RoomView {
        var room = tiles ? TVTablePreview.tiles(seats: seats ?? 4) : TVTablePreview.catTower(seats: seats ?? 6)
        room.code = code
        return room
    }

}

/// A UI test's go-ahead to the demo (a Darwin notification: it reads nothing from the screen).
enum TVDemoSignal: String {
    /// Seats everyone in the lobby, then starts the game (`Live.releaseDemo`, as the iPhone's).
    case release = "com.conleychaos.play.demo.release"
    /// Ends the game (`Live.endDemo`).
    case end = "com.conleychaos.play.demo.end"

    /// Every post from now on, until `notify_cancel(token)`: none is missed while the demo is busy
    /// with the step before.
    func listen() -> (posts: AsyncStream<Void>, token: Int32) {
        let (posts, feed) = AsyncStream.makeStream(of: Void.self)
        var token: Int32 = 0
        notify_register_dispatch(rawValue, &token, DispatchQueue.main) { _ in feed.yield() }
        return (posts, token)
    }
}

extension TVServices {
    /// No server: tables made here, a link nobody scans, sockets that play the game, and nothing
    /// kept between launches.
    static func demo() -> TVServices {
        let tables = TVDemoTables()
        return TVServices(
            createRoom: { game in
                try await Task.sleep(for: Pace.duration(.milliseconds(300)))
                return await tables.make(game)
            },
            link: { TVDemoLink() },
            socket: { code in
                TVDemoSocket(room: TVDemo.room(tiles: TVDemoTables.isTiles(code), code: code), lobby: true)
            },
            keep: MemoryScreenKeep())
    }

}

/// The tables a demo TV made. A code says its game, so a socket can be made from it alone.
actor TVDemoTables {
    private var made = 0

    func make(_ game: String) -> String {
        made += 1
        let letters = Array("BCDFGHJKLMNPQRSTVWXZ")
        return (game == GameCatalog.tiles.id ? "TILE" : "CATT") + String(letters[made % letters.count])
    }

    nonisolated static func isTiles(_ code: String) -> Bool { code.hasPrefix("TILE") }
}

/// Home's link, which no phone scans.
final class TVDemoLink: ScreenLinking {
    let events: AsyncStream<ScreenLinkEvent>
    private let feed: AsyncStream<ScreenLinkEvent>.Continuation

    init() { (events, feed) = AsyncStream.makeStream(of: ScreenLinkEvent.self) }

    func start(showing: String?) async {
        feed.yield(.code(token: "demo", code: "KTNPWS", url: URL(string: "https://play.conleychaos.com/tv/KTNPWS")!))
    }

    func stop() async { feed.finish() }
}

/// A screen's socket to a table that plays itself, as a server would send it: each move's events,
/// then the snapshot that carries its truth, and the acting phone's aims between. Waits run at the
/// app's speed (`Pace`).
actor TVDemoSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let feed: AsyncStream<SocketEvent>.Continuation
    private var room: RoomView
    /// The game the lobby turns into.
    private let playing: RoomView
    private var seq = 1
    private var player: Task<Void, Never>?
    private var ending = false
    /// The test's go-aheads, listened for from the moment the socket is made, so one posted as
    /// soon as the lobby shows is never missed.
    private let releases: AsyncStream<Void>
    private let ends: AsyncStream<Void>
    private var tokens: [Int32]

    init(room: RoomView, lobby: Bool) {
        playing = room
        self.room = lobby ? Self.lobby(room) : room
        (events, feed) = AsyncStream.makeStream(of: SocketEvent.self)
        let release = TVDemoSignal.release.listen()
        let end = TVDemoSignal.end.listen()
        releases = release.posts
        ends = end.posts
        tokens = [release.token, end.token]
    }

    /// The table before anyone sits.
    static func lobby(_ room: RoomView) -> RoomView {
        var lobby = room
        lobby.status = .lobby
        lobby.game = nil
        lobby.tiles = nil
        lobby.seats = room.seats.map { _ in SeatView(kind: .open) }
        return lobby
    }

    func start() async {
        feed.yield(.connected)
        snapshot()
        player = Task { await self.run() }
    }

    func send(_ m: ClientMessage) async throws {}

    func reconnectNow() async {}

    func stop() async {
        player?.cancel()
        player = nil
        for token in tokens { notify_cancel(token) }
        tokens = []
        feed.finish()
    }

    // MARK: the script

    private func run() async {
        // A finished game just stays finished.
        guard room.status != .over else { return }
        if room.status == .lobby {
            var release = releases.makeAsyncIterator()
            guard await release.next() != nil, !Task.isCancelled else { return }
            for i in room.seats.indices {
                guard await pause(0.3) else { return }
                room.seats[i] = playing.seats[i]
                snapshot()
            }
            guard await release.next() != nil, !Task.isCancelled else { return }
            room = playing
            room.status = .playing
            snapshot()
            guard await pause(1.5) else { return }
        }
        let ends = ends
        let watch = Task { [weak self] in
            for await _ in ends {
                await self?.end()
                return
            }
        }
        defer { watch.cancel() }
        if room.tiles != nil {
            await playTiles()
        } else {
            await playCatTower()
        }
    }

    private func end() { ending = true }

    /// Waits `seconds` at the app's speed; false once the socket stopped.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: Pace.duration(.milliseconds(Int(seconds * 1000))))
        return !Task.isCancelled
    }

    private func snapshot() {
        feed.yield(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
    }

    private func event(_ event: RoomEvent) {
        seq += 1
        feed.yield(.message(.event(seq: seq, event: event)))
    }

    private func aim(_ seat: Seat, _ aim: GameAim?) {
        feed.yield(.message(.aim(seat: seat, aim: aim)))
    }

    // MARK: Cat Tower

    /// Each turn: the turn, a draw from the deck, the phone's aim, then a hit on a set, a discard
    /// or (every fourth turn) a lay-down with its big moment. Every sixth turn the laid groups go
    /// back to how they began, so no group grows past its room.
    private func playCatTower() async {
        guard let start = room.game else { return }
        var turn = 0
        var hits = 0
        while !ending {
            guard var game = room.game else { return }
            let s = (game.turn + 1) % room.seats.count
            if turn > 0, turn.isMultiple(of: 6) {
                game.laid = start.laid
                game.handCounts = start.handCounts
            }
            game.turn = s
            game.step = .draw
            room.game = game
            event(.game(.turn(seat: s)))
            snapshot()
            guard await pause(0.9) else { return }

            game.deckCount = game.deckCount > 8 ? game.deckCount - 1 : 40
            game.handCounts[s] += 1
            game.step = .play
            room.game = game
            event(.game(.drew(seat: s, from: .deck, card: nil)))
            snapshot()
            guard await pause(0.6) else { return }

            let hit = Self.hit(game, hits)
            if let hit { aim(s, .target(seat: hit.target.seat, group: hit.target.group)) }
            guard await pause(0.9) else { return }
            aim(s, nil)

            if turn % 4 == 3, let groups = game.laid[safe: s] ?? nil {
                event(.game(.laidDown(seat: s, groups: groups)))
            } else if turn.isMultiple(of: 2), let hit {
                hits += 1
                game.laid[hit.target.seat]?[hit.target.group] = .set(cards: hit.cards, value: hit.value)
                game.handCounts[s] -= 1
                room.game = game
                event(.game(.hit(seat: s, card: hit.card, target: hit.target, group: .set(cards: hit.cards, value: hit.value))))
            } else {
                let card = Self.card(2 + turn % 9, Coat.allCases[turn % Coat.allCases.count], copy: 1)
                game.discardTop = card
                game.discardCount += 1
                game.handCounts[s] -= 1
                room.game = game
                event(.game(.discarded(seat: s, card: card, skipTarget: nil)))
            }
            snapshot()
            guard await pause(0.8) else { return }
            turn += 1
        }
        guard var game = room.game else { return }
        let winner = game.scores.indices.max { game.scores[$0] < game.scores[$1] } ?? 0
        game.status = .gameOver
        game.winners = [winner]
        room.game = game
        room.status = .over
        event(.game(.gameOver(winners: [winner])))
        snapshot()
    }

    /// The `n`th hit: one more card on a laid set (taking turns between the sets), with a card no
    /// group holds yet, and the set's cards and value after it.
    private static func hit(_ game: GameView, _ n: Int) -> (target: HitTarget, card: CardID, cards: [CardID], value: Int)? {
        var sets: [(HitTarget, [CardID], Int)] = []
        for (seat, groups) in game.laid.enumerated() {
            for (i, group) in (groups ?? []).enumerated() {
                if case .set(let cards, let value) = group { sets.append((HitTarget(seat: seat, group: i), cards, value)) }
            }
        }
        guard !sets.isEmpty else { return nil }
        let (target, cards, value) = sets[n % sets.count]
        let used = Set(game.laid.compactMap { $0 }.flatMap { $0 }.flatMap(\.cards))
        let free = (0...1).lazy.flatMap { copy in Coat.allCases.map { card(value, $0, copy: copy) } }.first { !used.contains($0) }
        guard let free else { return nil }
        return (target, free, cards + [free], value)
    }

    /// A number card's id (`DemoFixtures`' numbering).
    private static func card(_ value: Int, _ coat: Coat, copy: Int = 0) -> CardID {
        Coat.allCases.firstIndex(of: coat)! * 24 + value - 1 + copy * 12
    }

    // MARK: Tuna Tiles

    /// Turns that take each other's place: a play (the phone's draft as it grows, then the play
    /// landing) and a draw from the toy box. Before each play the rug goes back to how it began.
    private func playTiles() async {
        guard let start = room.tiles else { return }
        var turn = 0
        while !ending {
            guard var tiles = room.tiles else { return }
            let s = (tiles.turn + 1) % tiles.rackCounts.count
            let plays = turn.isMultiple(of: 2)
            if plays {
                tiles.table = start.table
                tiles.rackCounts = start.rackCounts
                tiles.poolCount = start.poolCount
                tiles.opened = start.opened
            }
            tiles.turn = s
            tiles.turns += 1
            room.tiles = tiles
            event(.tiles(.turn(seat: s)))
            snapshot()
            guard await pause(0.8) else { return }

            if plays {
                let (first, second, placed) = Self.drafts(tiles.table)
                aim(s, .table(first))
                guard await pause(0.8) else { return }
                aim(s, .table(second))
                guard await pause(0.8) else { return }
                aim(s, nil)
                let opening = !tiles.opened[s]
                tiles.table = second
                tiles.rackCounts[s] = max(tiles.rackCounts[s] - placed.count, 1)
                tiles.opened[s] = true
                room.tiles = tiles
                event(.tiles(.played(seat: s, table: second, placed: placed, opened: opening)))
            } else {
                guard await pause(0.6) else { return }
                tiles.poolCount = max(tiles.poolCount - 1, 0)
                tiles.rackCounts[s] += 1
                room.tiles = tiles
                event(.tiles(.drew(seat: s, tile: nil, poolCount: tiles.poolCount)))
            }
            snapshot()
            guard await pause(0.9) else { return }
            turn += 1
        }
        guard var tiles = room.tiles else { return }
        let winner = 0
        var left = tiles.rackCounts
        left[winner] = 0
        var scores = left.map { -$0 }
        scores[winner] = left.reduce(0, +)
        tiles.status = .gameOver
        tiles.winners = [winner]
        tiles.scores = scores
        tiles.endReason = .out
        room.tiles = tiles
        room.status = .over
        event(.tiles(.gameOver(winners: [winner], reason: .out, scores: scores, left: left)))
        snapshot()
    }

    /// A phone's draft as it grows: fish 7 on the fish row, then a new match of 11s. The rug's
    /// first row is the fish run from 3 (`DemoFixtures.tilesMid`).
    private static func drafts(_ table: [[TileID]]) -> (first: [[TileID]], second: [[TileID]], placed: [TileID]) {
        let fish7 = DemoFixtures.tile(7, .fish)
        let elevens = [DemoFixtures.tile(11, .bell), DemoFixtures.tile(11, .feather), DemoFixtures.tile(11, .fish)]
        var first = table
        if !first.isEmpty { first[0].append(fish7) }
        var second = first
        second.append(elevens)
        return (first, second, [fish7] + elevens)
    }
}

/// `-demo tv-hit` and `-demo tv-tiles`: the TV's table for the demo's room, full screen, through
/// the same `TVRoom` and `TableHost` as a real table.
struct TVDemoTableView: View {
    let game: TVTablePreview.Game
    let seats: Int
    @State private var table: TVRoom?

    var body: some View {
        ZStack {
            Color(Palette.night)
            if let table { TableHost(table: table) }
        }
        .ignoresSafeArea()
        .task { start() }
    }

    private func start() {
        guard table == nil else { return }
        let room = TVDemo.room(tiles: game == .tiles, seats: seats, code: DemoFixtures.code)
        let next = TVRoom(code: room.code, socket: { _ in TVDemoSocket(room: room, lobby: false) }, watchesNetwork: false)
        next.onChange = { table in
            if table.store.phase == .playing || table.store.phase == .over { table.openTable() }
        }
        table = next
        next.start()
    }
}
#endif
