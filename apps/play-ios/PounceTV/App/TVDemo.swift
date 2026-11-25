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
/// - `tv-over` (`-seats` 2 to 6, default 4): the whole TV back at a Cat Tower table that just
///   finished, so game over shows over it (the App Store shot): three-digit scores, everyone on a
///   different level and cat, nobody left.
/// - `tv-board`: the whole TV opening to Tonight's board (a kept board token) on a fake board
///   socket: six people across the four games, someone's progress and a new result every 1.5 s
///   (at the app's pace). Each `Live.releaseDemo` offers a run to watch, then plays it.
enum TVDemo: Equatable {
    case table(TVTablePreview.Game, seats: Int)
    case shell
    case over(seats: Int)
    case board

    static func from(arguments: [String] = CommandLine.arguments) -> TVDemo? {
        guard let i = arguments.firstIndex(of: "-demo"), let name = arguments[safe: i + 1] else { return nil }
        let seats = arguments.firstIndex(of: "-seats").flatMap { arguments[safe: $0 + 1] }.flatMap(Int.init)
        switch name {
        case "tv-hit": return .table(.cattower, seats: seats ?? 6)
        case "tv-tiles": return .table(.tiles, seats: seats ?? 4)
        case "tv-shell": return .shell
        case "tv-over": return .over(seats: seats ?? 4)
        case "tv-board": return .board
        default: return nil
        }
    }

    /// The table a demo plays: `TVTablePreview`'s, nobody's hand, at `code`.
    static func room(tiles: Bool, seats: Int? = nil, code: String) -> RoomView {
        var room = tiles ? TVTablePreview.tiles(seats: seats ?? 4) : TVTablePreview.catTower(seats: seats ?? 6)
        room.code = code
        return room
    }

    /// A Cat Tower game just finished, for `tv-over`: the 20-letter name won on level 10, and the
    /// others stopped on different levels with three-digit scores, each with their own cat.
    static func finished(seats: Int, code: String) -> RoomView {
        let n = min(max(seats, 2), 6)
        var room = TVTablePreview.catTower(seats: n)
        room.code = code
        room.status = .over
        let cats = [3, 5, 1, 7, 2, 6]
        for i in room.seats.indices where room.seats[i].kind == .human {
            room.seats[i].person?.cat = cats[i % cats.count] % ArtName.catCount
        }
        guard var game = room.game else { return room }
        game.status = .gameOver
        game.phase = Array([7, 9, 4, 8, 5, 6].prefix(n))
        game.scores = Array([185, 140, 320, 215, 275, 240].prefix(n))
        game.winners = [1]
        game.handCounts = Array(repeating: 0, count: n)
        game.forfeited = Array(repeating: false, count: n)
        room.game = game
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

    /// `tv-board`: the TV kept a board, and its socket plays an evening of the Daily Dish.
    static func demoBoard() -> TVServices {
        var services = TVServices.demo()
        services.boards = MemoryBoardKeep(.fresh(String(repeating: "D", count: 22), now: Date()))
        services.boardSocket = { _ in TVDemoBoardSocket() }
        services.dailyOn = { true }
        return services
    }

    /// `tv-over`: the TV kept a table, and that table's game has just ended.
    static func demoOver(seats: Int) -> TVServices {
        let code = "OVERB"
        return TVServices(
            createRoom: { _ in code },
            link: { TVDemoLink() },
            socket: { code in TVDemoSocket(room: TVDemo.finished(seats: seats, code: code), lobby: false) },
            keep: MemoryScreenKeep(ScreenKept(room: code)))
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
/// Tonight's board as a busy evening plays it: six people across the four games, the board growing
/// a result at a time (each with its `result`, then the fresh `board`), and the next person's
/// progress between. Each `Live.releaseDemo` offers Kid's Sniff run, then plays it to its end.
actor TVDemoBoardSocket: BoardSocketing {
    nonisolated let events: AsyncStream<BoardSocketEvent>
    private let feed: AsyncStream<BoardSocketEvent>.Continuation
    private var player: Task<Void, Never>?
    private let releases: AsyncStream<Void>
    private let token: Int32

    /// `POUNCE_DEMO_CAST` renames them in order (the App Store capture, `AppStore/capture-tv.sh`).
    private static let people: [(id: String, name: String, cat: Int)] = [
        ("me", "Mom", 3), ("pr_dad", "Dad", 1), ("pr_kid", "Kid", 5),
        ("pr_gpa", "Grandpa", 0), ("pr_nana", "Nana", 7), ("pr_bart", "Bartholomew Wiggles", 6),
    ].enumerated().map { i, who in (who.0, DemoFixtures.castName(i, who.1), who.2) }
    private static let games = ["sniff", "nine-lives", "cat-nap", "box-fort"]

    init() {
        (events, feed) = AsyncStream.makeStream(of: BoardSocketEvent.self)
        let release = TVDemoSignal.release.listen()
        releases = release.posts
        token = release.token
    }

    func start() {
        guard player == nil else { return }
        player = Task { await self.play() }
    }

    func stop() {
        player?.cancel()
        player = nil
        notify_cancel(token)
        feed.finish()
    }

    private func play() async {
        feed.yield(.online)
        var tick = 0
        feed.yield(.message(.board(Self.board(tick))))
        let offers = Task { await self.offers() }
        defer { offers.cancel() }
        while !Task.isCancelled {
            try? await Task.sleep(for: Pace.duration(.milliseconds(750)))
            guard !Task.isCancelled else { return }
            // The next person's progress, then (every other beat) their result and the new board.
            let (game, who) = Self.next(tick)
            feed.yield(.message(.progress(player: who.id, game: game, progress: 0.5)))
            try? await Task.sleep(for: Pace.duration(.milliseconds(750)))
            guard !Task.isCancelled else { return }
            tick += 1
            feed.yield(.message(.result(player: who.id, result: Self.result(game: game, who: Self.people.firstIndex { $0.id == who.id } ?? 0))))
            feed.yield(.message(.board(Self.board(tick))))
        }
    }

    /// Kid's Sniff run as the server's watch frames would carry it: SPICE in four.
    private static let sniffGuesses: [(String, [String])] = [
        ("large", ["none", "none", "none", "none", "spot"]),
        ("toils", ["none", "none", "spot", "none", "near"]),
        ("spine", ["spot", "spot", "spot", "none", "spot"]),
        ("spice", ["spot", "spot", "spot", "spot", "spot"]),
    ]

    private static func sniffFrame(_ guesses: Int) -> (puzzle: DailyJSON, state: DailyJSON) {
        let shown = sniffGuesses.prefix(guesses).map { word, marks in
            DailyJSON.object(["word": .string(word), "marks": .array(marks.map { .string($0) })])
        }
        return (.object(["letters": .int(5), "tries": .int(6)]), .object(["guesses": .array(shown)]))
    }

    /// Each go-ahead: Kid's Sniff run is offered, then plays out a guess every second and a half.
    private func offers() async {
        for await _ in releases {
            feed.yield(.message(.watchOffer(player: "pr_kid", name: Self.people[2].name, cat: 5, game: "sniff")))
            let first = Self.sniffFrame(0)
            feed.yield(.message(.watch(player: "pr_kid", game: "sniff", puzzle: first.puzzle, state: first.state)))
            // Long enough for the card to be read and Watch pressed, then the guesses watched.
            try? await Task.sleep(for: Pace.duration(.seconds(10)))
            for n in 1...Self.sniffGuesses.count {
                let frame = Self.sniffFrame(n)
                feed.yield(.message(.watch(player: "pr_kid", game: "sniff", puzzle: frame.puzzle, state: frame.state)))
                try? await Task.sleep(for: Pace.duration(.seconds(1.5)))
            }
            feed.yield(.message(.watchEnd(player: "pr_kid", game: "sniff", result: Self.result(game: "sniff", who: 2))))
        }
    }

    /// Who plays which game at beat `tick`: around the games, then around the people.
    private static func next(_ tick: Int) -> (String, (id: String, name: String, cat: Int)) {
        let game = games[tick % games.count]
        let shown = rowsFor(game: game, tick: tick)
        return (game, people[shown % people.count])
    }

    /// How many people have a result in `game` at beat `tick`: 4 to 6, round and round, so a
    /// family's board is mostly full, with someone still playing now and then.
    private static func rowsFor(game: String, tick: Int) -> Int {
        let g = games.firstIndex(of: game) ?? 0
        return people.count - (tick / games.count + g) % 3
    }

    private static func result(game: String, who: Int) -> DailyResult {
        let outcome: DailyOutcome = game == "box-fort" ? .done : (who == 4 ? .gaveUp : .solved)
        return DailyResult(
            game: game, date: "2026-11-23", number: 12, outcome: outcome, timeMs: 95_000 + who * 41_000 + (games.firstIndex(of: game) ?? 0) * (who + 1) * 13_000, hints: who == 3 ? 1 : 0,
            progress: outcome == .gaveUp ? 0.4 : 1, tooFast: false,
            guesses: game == "sniff" ? 3 + who % 4 : nil, points: game == "box-fort" ? 2_400 - who * 310 : nil)
    }

    static func board(_ tick: Int) -> DailyBoard {
        var dish: [String: (points: Int, crowns: [String], ended: Int)] = [:]
        let games = games.map { game -> DailyGameBoard in
            let n = rowsFor(game: game, tick: tick)
            var rows = (0..<n).map { i in
                let who = people[i]
                return DailyBoardRow(player: who.id, name: who.name, cat: who.cat, rank: i + 1, result: result(game: game, who: i), playing: nil)
            }
            for (i, row) in rows.enumerated() {
                var d = dish[row.player] ?? (0, [], 0)
                d.points += max(0, 3 - i) + 1
                d.ended += 1
                if i == 0, !d.crowns.contains(game) { d.crowns.append(game) }
                dish[row.player] = d
            }
            if n < people.count {
                let who = people[n]
                rows.append(DailyBoardRow(player: who.id, name: who.name, cat: who.cat, rank: nil, result: nil, playing: .init(progress: 0.25)))
            }
            return DailyGameBoard(game: game, number: 12, rows: rows)
        }
        let sorted = dish.sorted { $0.value.points > $1.value.points }
        let rows = sorted.enumerated().map { i, entry in
            let who = people.first { $0.id == entry.key }!
            return DailyDishRow(player: who.id, name: who.name, cat: who.cat, rank: i + 1, points: entry.value.points, crowns: entry.value.crowns, ended: entry.value.ended)
        }
        return DailyBoard(date: "2026-11-23", games: games, dish: DailyDish(rows: rows), tvs: 1)
    }
}
#endif
