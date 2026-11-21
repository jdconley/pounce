import PounceKit
import SpriteKit
import SwiftUI
import Testing
@testable import PounceTV

/// The TV's table, drawn by the iPhone's scenes in the TV's arrangement. Its one hard rule: a TV
/// never shows a hand or a rack. The server never sends a screen one; these feed the scenes rooms
/// that hold them anyway (a seat marked this device's, its hand or stash in the view) and check
/// that nothing of them is ever made, face up or face down (defence in depth).
@MainActor
@Suite("The TV's table")
struct TVTableTests {
    /// A screen's store, fed by hand: no socket, no server.
    private static func screenStore() -> RoomStore {
        let store = RoomStore(code: DemoFixtures.code, socket: QuietSocket(), role: .screen)
        store.handle(.connected)
        return store
    }

    /// Every node under `node`, depth first.
    private static func all(_ node: SKNode) -> [SKNode] {
        node.children.flatMap { [$0] + all($0) }
    }

    private static let tv = CGSize(width: 1920, height: 1080)

    /// Waits up to two seconds for `done` (the TV's pictures are drawn off the main thread).
    private static func soon(_ done: () -> Bool) async -> Bool {
        for _ in 0..<40 where !done() { try? await Task.sleep(for: .milliseconds(50)) }
        return done()
    }

    // MARK: Cat Tower

    /// My play step at `hitTable`: seat 0 is "mine", with four cards in hand and two sets laid.
    @Test func catTowerNeverDrawsAHandEvenWhenTheRoomHasOne() async {
        let store = Self.screenStore()
        let room = DemoFixtures.hitTable()
        let hand = Set(room.game!.hands[0] ?? [])
        #expect(!hand.isEmpty && room.seats[0].yours)  // the room really does hold a hand

        let scene = TableScene(store: store)
        scene.size = Self.tv
        scene.safeInsets = UIEdgeInsets(top: 60, left: 80, bottom: 60, right: 80)
        #expect(scene.isScreen)
        // The shell's path, asking to show seat 0's hand.
        scene.reconcile(TableModel(room: room), revealed: 0, epoch: store.turnEpoch)
        // And the store's: a snapshot, then a draw from the deck that names the card.
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        await scene.play(.reconcile)
        await scene.play(.game(.drew(seat: 0, from: .deck, card: room.game!.hands[0]!.first), seq: 2))
        await scene.play(.reconcile)

        #expect(scene.layout?.arrangement == .tv)
        #expect(scene.bottomSeat == nil)
        #expect(scene.shownRevealed == nil)
        #expect(scene.revealed == nil)
        #expect(scene.hand.cards.isEmpty)
        #expect(scene.trays.isHidden)
        #expect(scene.layer(.hand).isHidden && scene.layer(.trays).isHidden)
        let cards = Self.all(scene).compactMap { $0 as? CardNode }
        #expect(!cards.contains { $0.isPrivate }, "a private card node exists")
        #expect(!cards.contains { $0.card.map(hand.contains) ?? false }, "a card of the hand is drawn face up")
        // Every seat sits around the table, seat 0 too.
        for seat in room.seats.indices { #expect(scene.opponents.node(for: seat) != nil, "seat \(seat) has no cat") }
    }

    /// The banner names whose turn it is, the tower stands open, and the acting player's aim glows.
    @Test func catTowerShowsTheTurnTheTowerAndTheAim() async {
        let store = Self.screenStore()
        var room = DemoFixtures.hitTable()
        room.game!.turn = 1
        room.seats = room.seats.map { var s = $0; s.yours = false; return s }
        room.game!.hands = [:]
        let scene = TableScene(store: store)
        scene.size = Self.tv
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        await scene.play(.reconcile)
        #expect(scene.banner.shown == .turn(seat: 1, name: SeatInfo.name(room, 1), cat: SeatInfo.catIndex(room.seats[1])))
        #expect(await Self.soon { !scene.banner.isHidden }, "the banner's picture never came")
        #expect(scene.tower.isOpen)

        store.handle(.message(.aim(seat: 1, aim: .target(seat: 1, group: 1))))
        scene.showAim()
        #expect(scene.laidZone.aim == HitTarget(seat: 1, group: 1))
        // Someone else's aim, or one at a group that isn't there, glows nothing.
        store.handle(.message(.aim(seat: 1, aim: .target(seat: 3, group: 0))))
        scene.showAim()
        #expect(scene.laidZone.aim == nil)
        store.handle(.message(.aim(seat: 2, aim: .target(seat: 1, group: 0))))
        scene.showAim()
        #expect(scene.laidZone.aim == nil)

        // Between rounds the banner goes.
        room.game!.status = .roundOver
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 2, room: room)))
        await scene.play(.reconcile)
        #expect(scene.banner.isHidden)
    }

    /// A phone's table is untouched by any of it: no banner, the phone's arrangement.
    @Test func aPhonesTableHasNoBanner() async {
        let store = RoomStore(code: DemoFixtures.code, socket: QuietSocket())
        store.handle(.connected)
        let scene = TableScene(store: store)
        scene.size = CGSize(width: 390, height: 844)
        let room = DemoFixtures.hitTable()
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        await scene.play(.reconcile)
        #expect(!scene.isScreen)
        #expect(scene.layout?.arrangement == .phone)
        #expect(scene.banner.isHidden)
        #expect(scene.bottomSeat == 0)
    }

    // MARK: pictures that land late

    /// A table can get its game before its view sizes it: it lays out once at the scene's first
    /// size, then again at the TV's, and asks for each seat's score and the banner at both sizes.
    /// The two pictures are drawn off the main thread and land in either order. Here the TV-size
    /// ones are drawn already and the first-size ones land last: each seat must still show the
    /// TV-size score under its name, and the banner the TV-size pill.
    @Test func aPictureForAnEarlierLayoutNeverReplacesTheCurrentOne() async throws {
        let store = Self.screenStore()
        var room = DemoFixtures.hitTable()
        room.seats = room.seats.map { var s = $0; s.yours = false; return s }
        room.game!.hands = [:]
        room.game!.turn = 1
        // Scores no other test draws, so nothing is cached for them.
        room.game!.scores = [901, 902, 903, 904]
        let seats = room.seats.count
        let tv = TableLayout(tv: Self.tv, insets: .zero, seats: seats)
        let words = TVSeatWords(.zero, unit: tv.tvUnit)
        let names = SeatInfo.names(room)
        let big = room.game!.scores.map(words.piece)
        let bigBanner = TVBanner.piece(name: names[1], seat: 1, banner: tv.banner, room: tv.bannerRoom, unit: tv.tvUnit)
        TVArt.shared.warm(big + [bigBanner])
        #expect(await Self.soon { (big + [bigBanner]).allSatisfy { TVArt.shared.ready($0) != nil } })

        let scene = TableScene(store: store)  // still its first size, 390 x 844
        let first = TableLayout(tv: scene.size, insets: .zero, seats: seats)
        let small = room.game!.scores.map(TVSeatWords(.zero, unit: first.tvUnit).piece)
        let smallBanner = TVBanner.piece(name: names[1], seat: 1, banner: first.banner, room: first.bannerRoom, unit: first.tvUnit)
        #expect(small.allSatisfy { TVArt.shared.ready($0) == nil })
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        await scene.play(.reconcile)  // lays out at the first size: asks for the small pictures
        scene.size = Self.tv  // sized: asks for the big ones, drawn already
        // The small ones land now, after the big ones.
        #expect(await Self.soon { (small + [smallBanner]).allSatisfy { TVArt.shared.ready($0) != nil } })
        try await Task.sleep(for: .milliseconds(100))

        for seat in 0..<seats {
            let node = try #require(scene.opponents.score(for: seat))
            let want = try #require(TVArt.shared.ready(big[seat]))
            #expect(!node.isHidden, "seat \(seat) shows no score")
            #expect(node.texture === want, "seat \(seat) shows a score picture from an earlier layout")
            #expect(node.size == want.size(), "seat \(seat)'s score is drawn at the wrong size")
            let tag = try #require(scene.opponents.tag(for: seat))
            #expect(abs(node.position.x - tag.position.x) < 0.5 && node.position.y < tag.position.y, "seat \(seat)'s score isn't under its name")
        }
        let pill = try #require(scene.banner.children.compactMap { $0 as? SKSpriteNode }.first)
        #expect(pill.texture === TVArt.shared.ready(bigBanner), "the banner shows a picture from an earlier layout")
    }

    // MARK: frame rate

    /// On the TV each game's table asks for the screen's top frame rate and, once nothing moves,
    /// rests (the director pauses its view) as the iPhone's tables do.
    @Test(arguments: [false, true])
    func eachTableRunsAtTheTopRateAndRestsWhenIdle(_ tiles: Bool) async throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = try #require(scenes.flatMap(\.windows).first)
        let store = Self.screenStore()
        let room = tiles ? DemoFixtures.tilesOther() : DemoFixtures.hitTable()
        let host: UIViewController
        let scene: SKScene
        if tiles {
            let s = TilesScene(store: store)
            scene = s
            host = UIHostingController(rootView: TilesTableView(scene: s).ignoresSafeArea())
        } else {
            let s = TableScene(store: store)
            scene = s
            host = UIHostingController(rootView: TableView(scene: s).ignoresSafeArea())
        }
        host.view.frame = window.bounds
        window.addSubview(host.view)
        defer { host.view.removeFromSuperview() }
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        if let s = scene as? TableScene { await s.play(.reconcile) } else { (scene as? TilesScene)?.reconcileFromStore() }

        var view: SKView?
        for _ in 0..<50 where view?.window == nil {
            try await Task.sleep(for: .milliseconds(50))
            view = scene.view
        }
        let shown = try #require(view)
        let top = try #require(window.windowScene?.screen.maximumFramesPerSecond)
        #expect(shown.preferredFramesPerSecond == top)
        #expect(scene.size.width > 1000)
        // Idle: the view pauses itself (`AnimationDirector`), so it draws nothing at all.
        for _ in 0..<60 where !shown.isPaused { try await Task.sleep(for: .milliseconds(50)) }
        #expect(shown.isPaused, "an idle TV table keeps drawing")
    }

    // MARK: Tuna Tiles

    /// `tilesMid`: seat 0 is "mine", with nine pieces in its stash.
    @Test func tilesNeverDrawsAStashEvenWhenTheRoomHasOne() async {
        let store = Self.screenStore()
        let room = DemoFixtures.tilesMid()
        let rack = Set(room.tiles!.racks[0] ?? [])
        #expect(!rack.isEmpty && room.seats[0].yours)

        let scene = TilesScene(store: store)
        scene.size = Self.tv
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        scene.reconcileFromStore()

        #expect(scene.isScreen)
        #expect(scene.layout?.arrangement == .tv)
        #expect(scene.shownSeat == nil)
        #expect(scene.draft == nil)
        #expect(scene.rackShown.isEmpty)
        #expect(!scene.pieces.values.contains { $0.isPrivate })
        #expect(rack.isDisjoint(with: scene.pieces.keys), "a stash piece is drawn")
        #expect(scene.turnPill.isHidden && scene.undoButton.isHidden && scene.sortNumberButton.isHidden)
        for seat in room.seats.indices { #expect(scene.opponents.node(for: seat) != nil, "seat \(seat) has no cat") }

        // A draw that names the piece (as only the drawing seat's phone should hear it).
        let drawn = DemoFixtures.tile(13, .bell, 1)
        var shownToShell: [TileID] = []
        scene.onDrew = { _, tile in shownToShell.append(tile) }
        scene.enqueue(.tiles(.drew(seat: 0, tile: drawn, poolCount: room.tiles!.poolCount - 1), seq: 2))
        await scene.playChain?.value
        var after = room
        after.tiles!.racks[0] = (after.tiles!.racks[0] ?? []) + [drawn]
        after.tiles!.rackCounts[0] += 1
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 2, room: after)))
        scene.reconcileFromStore()
        #expect(shownToShell.isEmpty, "the TV handed a drawn piece to its shell")
        #expect(scene.shownSeat == nil && scene.rackShown.isEmpty)
        #expect(!scene.pieces.values.contains { $0.isPrivate })
        #expect(scene.pieces[drawn] == nil, "the drawn piece is on the TV")
        #expect(rack.union([drawn]).isDisjoint(with: scene.pieces.keys), "a stash piece is drawn")
        // Nothing anywhere shows the drawn piece's face.
        let face = TilePieceFactory.shared.face(drawn, size: .large)
        let small = TilePieceFactory.shared.face(drawn, size: .small)
        let sprites = Self.all(scene).compactMap { $0 as? SKSpriteNode }
        #expect(!sprites.contains { $0.texture === face || $0.texture === small }, "the drawn piece shows face up")
    }

    /// The acting player's draft shows on the board as they make it, what it adds marked.
    @Test func tilesShowsTheActingPlayersDraft() {
        let store = Self.screenStore()
        var room = DemoFixtures.tilesOther()  // seat 2's move
        room.seats = room.seats.map { var s = $0; s.yours = false; return s }
        room.tiles!.racks = [:]
        let scene = TilesScene(store: store)
        scene.size = Self.tv
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        scene.reconcileFromStore()
        #expect(scene.shown.map(\.tiles) == room.tiles!.table)

        var draft = room.tiles!.table
        let added = [DemoFixtures.tile(11, .bell), DemoFixtures.tile(11, .feather), DemoFixtures.tile(11, .fish)]
        draft.append(added)
        store.handle(.message(.aim(seat: 2, aim: .table(draft))))
        scene.redraw()
        #expect(scene.shown.map(\.tiles) == draft)
        #expect(scene.aimAdded() == Set(added))
        // Their phone takes the draft back as it commits: the board keeps it until the play lands.
        store.handle(.message(.aim(seat: 2, aim: nil)))
        scene.redraw()
        #expect(scene.shown.map(\.tiles) == draft, "the draft left the board before the play")
        // Another seat's aim is not the table's.
        store.handle(.message(.aim(seat: 1, aim: .table([added]))))
        scene.redraw()
        #expect(scene.shown.map(\.tiles) == draft)
        // The turn moves on: the board is the room's again.
        var next = room
        next.tiles!.turn = 3
        next.tiles!.turns += 1
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 2, room: next)))
        scene.reconcileFromStore()
        #expect(scene.shown.map(\.tiles) == next.tiles!.table)
    }

    /// A draft its player takes back with no play following (a cancel: on the wire, the same clear
    /// as a commit) stays on the board only for the hold, then the board is the table as it is.
    @Test func aCancelledDraftLeavesTheBoardAfterTheHold() {
        let store = Self.screenStore()
        var room = DemoFixtures.tilesOther()  // seat 2's move
        room.seats = room.seats.map { var s = $0; s.yours = false; return s }
        room.tiles!.racks = [:]
        let scene = TilesScene(store: store)
        scene.size = Self.tv
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        scene.reconcileFromStore()
        var draft = room.tiles!.table
        draft.append([DemoFixtures.tile(11, .bell), DemoFixtures.tile(11, .feather), DemoFixtures.tile(11, .fish)])
        store.handle(.message(.aim(seat: 2, aim: .table(draft))))
        scene.redraw()
        scene.update(100)
        #expect(scene.shown.map(\.tiles) == draft)

        // The clear: the hold starts with the next frame.
        store.handle(.message(.aim(seat: 2, aim: nil)))
        scene.redraw()
        scene.update(100.1)
        #expect(scene.shown.map(\.tiles) == draft, "the draft left before its hold")
        scene.update(100.1 + TilesScene.draftHold * 0.8 / Double(scene.speed))
        #expect(scene.shown.map(\.tiles) == draft, "the draft left before its hold")
        // No play came: once the hold is over the board is the table as it really is.
        scene.update(100.1 + TilesScene.draftHold * 1.05 / Double(scene.speed))
        #expect(scene.shown.map(\.tiles) == room.tiles!.table, "a cancelled draft stays on the TV")
        scene.redraw()
        #expect(scene.shown.map(\.tiles) == room.tiles!.table)

        // A new draft in the same turn shows again.
        store.handle(.message(.aim(seat: 2, aim: .table(draft))))
        scene.redraw()
        #expect(scene.shown.map(\.tiles) == draft)
    }

    /// A turn that just started stays on the banner when the board redraws from the table as drawn.
    @Test func tilesBannerKeepsATurnThatJustStarted() {
        let store = Self.screenStore()
        var room = DemoFixtures.tilesOther()
        room.seats = room.seats.map { var s = $0; s.yours = false; return s }
        room.tiles!.racks = [:]
        let scene = TilesScene(store: store)
        scene.size = Self.tv
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        scene.reconcileFromStore()
        #expect(scene.banner.shown == .turn(seat: 2, name: SeatInfo.name(room, 2), cat: SeatInfo.catIndex(room.seats[2])))
        scene.showBanner(turn: 3)
        scene.redraw(animated: true)
        #expect(scene.banner.shown == .turn(seat: 3, name: SeatInfo.name(room, 3), cat: SeatInfo.catIndex(room.seats[3])))
    }

    // MARK: game over

    /// A game's end comes as an event, then the snapshot that ends the room. The store marks the
    /// game over on the event, so a table that redraws between the two (an earlier snapshot's
    /// reconcile played late) saw a finished game in a room still playing. It said so then, the
    /// TV (its room not over yet) let that go, and the table never said it again: the TV sat on
    /// the table for good. Game over is said once the room is over, never before.
    @Test func catTowerSaysGameOverOnlyOnceTheRoomIsOver() async {
        let store = Self.screenStore()
        var room = DemoFixtures.hitTable()
        room.seats = room.seats.map { var s = $0; s.yours = false; return s }
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        let scene = TableScene(store: store)
        scene.size = Self.tv
        var told: [[Seat]] = []
        scene.onGameOver = { told.append($0) }
        await scene.play(.reconcile)

        store.handle(.message(.event(seq: 2, event: .game(.gameOver(winners: [1])))))
        await scene.play(.reconcile)  // the turn's snapshot, played after the game-over event landed
        #expect(told.isEmpty, "game over was said while the room was still playing")

        var over = room
        over.status = .over
        over.game!.status = .gameOver
        over.game!.winners = [1]
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 2, room: over)))
        await scene.play(.reconcile)
        #expect(told == [[1]])
    }

    /// The same for the tile game: its store marks the game over on the event too.
    @Test func tilesSaysGameOverOnlyOnceTheRoomIsOver() async {
        let store = Self.screenStore()
        var room = DemoFixtures.tilesMid()
        room.seats = room.seats.map { var s = $0; s.yours = false; return s }
        room.tiles!.racks = [:]
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        let scene = TilesScene(store: store)
        scene.size = Self.tv
        var told: [[Seat]] = []
        scene.onGameOver = { told.append($0) }
        scene.reconcileFromStore()

        let scores = room.tiles!.rackCounts.map { _ in 0 }
        store.handle(.message(.event(seq: 2, event: .tiles(.gameOver(winners: [1], reason: .out, scores: scores, left: scores)))))
        scene.reconcileFromStore()
        #expect(told.isEmpty, "game over was said while the room was still playing")

        var over = room
        over.status = .over
        over.tiles!.status = .gameOver
        over.tiles!.winners = [1]
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 2, room: over)))
        scene.reconcileFromStore()
        #expect(told == [[1]])
    }
}

/// A socket that never connects: the tests hand the store its events.
private actor QuietSocket: RoomSocketing {
    nonisolated let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation

    init() { (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self) }

    func start() async {}
    func send(_ m: ClientMessage) async throws {}
    func reconnectNow() async {}
    func stop() async { continuation.finish() }
}
