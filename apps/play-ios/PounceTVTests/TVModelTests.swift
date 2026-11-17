import Foundation
import PounceKit
import Synchronization
import Testing
@testable import PounceTV

// MARK: - fakes

/// What the fakes did, in order, across every socket and link: "start BCDFG#1", "stop BCDFG#1",
/// "link", "link BCDFG", "unlink", "create tiles".
final class Log: Sendable {
    private let lines = Mutex<[String]>([])
    func add(_ line: String) { lines.withLock { $0.append(line) } }
    var all: [String] { lines.withLock { $0 } }
    func index(of line: String) -> Int? { all.firstIndex(of: line) }
}

/// One connection of a TV to a room (`SuspendableSocket` makes a fresh one per connection).
final class FakeTableSocket: RoomSocketing {
    let code: String
    let n: Int
    let events: AsyncStream<SocketEvent>
    private let feed: AsyncStream<SocketEvent>.Continuation
    private let log: Log
    private let stopped = Mutex(false)

    init(code: String, n: Int, log: Log) {
        self.code = code
        self.n = n
        self.log = log
        (events, feed) = AsyncStream.makeStream(of: SocketEvent.self)
    }

    var name: String { "\(code)#\(n)" }
    var isStopped: Bool { stopped.withLock { $0 } }

    func start() async { log.add("start \(name)") }
    func send(_ m: ClientMessage) async throws { log.add("send \(name)") }
    func reconnectNow() async {}
    func stop() async {
        stopped.withLock { $0 = true }
        log.add("stop \(name)")
        feed.finish()
    }

    func emit(_ event: SocketEvent) { feed.yield(event) }

    /// The socket's first frames: connected, then the room.
    func arrive(_ room: RoomView, seq: Int = 1) {
        emit(.connected)
        emit(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: seq, room: room)))
    }
}

/// A TV link that a test drives: it records being started and stopped and yields what it's told.
final class FakeLink: ScreenLinking {
    let events: AsyncStream<ScreenLinkEvent>
    private let feed: AsyncStream<ScreenLinkEvent>.Continuation
    private let log: Log
    private let state = Mutex<(started: Bool, showing: String?, stopped: Bool)>((false, nil, false))

    init(log: Log) {
        self.log = log
        (events, feed) = AsyncStream.makeStream(of: ScreenLinkEvent.self)
    }

    var started: Bool { state.withLock { $0.started } }
    var showing: String? { state.withLock { $0.showing } }
    var stopped: Bool { state.withLock { $0.stopped } }

    func start(showing: String?) async {
        state.withLock { $0.started = true; $0.showing = showing }
        log.add(showing.map { "link \($0)" } ?? "link")
    }

    func stop() async {
        state.withLock { $0.stopped = true }
        log.add("unlink")
        feed.finish()
    }

    func emit(_ event: ScreenLinkEvent) { feed.yield(event) }
}

/// The server, for a TV under test: tables it makes, links and sockets, all recorded.
final class FakeServer: Sendable {
    let log = Log()
    private let state = Mutex<(sockets: [FakeTableSocket], links: [FakeLink], codes: [String], fails: Bool)>(([], [], ["NEWTB", "NEXTT", "THIRD"], false))

    var sockets: [FakeTableSocket] { state.withLock { $0.sockets } }
    var links: [FakeLink] { state.withLock { $0.links } }
    func sockets(_ code: String) -> [FakeTableSocket] { sockets.filter { $0.code == code } }
    func failCreates() { state.withLock { $0.fails = true } }

    func services(keep: any ScreenKeeping, sound: @escaping @MainActor (Bool) -> Void = { _ in }) -> TVServices {
        TVServices(
            createRoom: { game in
                self.log.add("create \(game)")
                let (fails, code): (Bool, String?) = self.state.withLock { s in
                    (s.fails, s.codes.isEmpty ? nil : s.codes.removeFirst())
                }
                if fails { throw APIError.unauthorized }
                return code ?? "ZZZZZ"
            },
            link: {
                let link = FakeLink(log: self.log)
                self.state.withLock { $0.links.append(link) }
                return link
            },
            socket: { code in
                self.state.withLock { s in
                    let socket = FakeTableSocket(code: code, n: s.sockets.filter { $0.code == code }.count + 1, log: self.log)
                    s.sockets.append(socket)
                    return socket
                }
            },
            keep: keep,
            applySound: sound)
    }
}

// MARK: - rooms

private enum Rooms {
    /// A table's lobby with nobody sitting yet.
    static func emptyLobby(_ code: String, game: String = GameCatalog.catTower.id) -> RoomView {
        RoomView(
            code: code, status: .lobby, youAreHost: false,
            seats: [SeatView(kind: .open), SeatView(kind: .open), SeatView(kind: .closed), SeatView(kind: .closed)],
            gameId: game, screen: true)
    }

    /// The lobby with one phone sat down.
    static func seatedLobby(_ code: String) -> RoomView {
        var room = emptyLobby(code)
        room.seats[0] = SeatView(kind: .human, person: Person(id: "p0", name: "Mia", cat: 0), presence: .awake)
        return room
    }

    /// Cat Tower mid-game, as a screen sees it: nobody's hand.
    static func playing(_ code: String) -> RoomView {
        var room = DemoFixtures.hitTable()
        room.code = code
        room.seats = room.seats.map { var s = $0; s.yours = false; return s }
        room.game!.hands = [:]
        room.youAreHost = false
        room.screen = true
        return room
    }

    static func over(_ code: String) -> RoomView {
        var room = playing(code)
        room.status = .over
        room.game!.status = .gameOver
        room.game!.winners = [1]
        return room
    }
}

// MARK: - tests

@MainActor
@Suite("The TV's model")
struct TVModelTests {
    /// Waits up to two seconds for `done`: socket events and links arrive on other tasks.
    private func soon(_ done: () -> Bool) async -> Bool {
        for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(10)) }
        return done()
    }

    private func started(_ server: FakeServer, kept: ScreenKept = ScreenKept()) async -> (TVModel, MemoryScreenKeep) {
        let keep = MemoryScreenKeep(kept)
        let model = TVModel(services: server.services(keep: keep))
        await model.start()
        return (model, keep)
    }

    /// The TV at table `code`, its first socket in, showing `room`.
    private func atTable(_ server: FakeServer, _ code: String, _ room: RoomView) async -> (TVModel, MemoryScreenKeep) {
        let (model, keep) = await started(server, kept: ScreenKept(room: code))
        #expect(await soon { server.sockets(code).count == 1 })
        server.sockets(code)[0].arrive(room)
        #expect(await soon { model.table?.store.room != nil })
        return (model, keep)
    }

    // MARK: home and links

    @Test func aNewTVShowsItsLinkAndAPhoneLinksItToATable() async {
        let server = FakeServer()
        let (model, keep) = await started(server)
        #expect(model.phase == .home)
        #expect(await soon { server.links.first?.started == true })
        let link = server.links[0]
        #expect(link.showing == nil)

        link.emit(.code(token: "tok", code: "QRSTVW", url: URL(string: "https://play.conleychaos.com/tv/tok")!))
        #expect(await soon { model.homeLink?.code == "QRSTVW" })
        #expect(model.homeLink?.url.absoluteString == "https://play.conleychaos.com/tv/tok")

        link.emit(.offline)
        #expect(await soon { model.homeOffline })

        link.emit(.linked(room: "BCDFG"))
        #expect(await soon { model.phase == .lobby })
        #expect(model.table?.code == "BCDFG")
        #expect(model.table?.store.isScreen == true)
        #expect(await soon { server.sockets("BCDFG").count == 1 })
        #expect(await soon { link.stopped })
        await model.settle()
        #expect(await keep.load().room == "BCDFG")
        #expect(model.homeLink == nil)
    }

    @Test func aKeptTableIsRejoinedAtLaunch() async {
        let server = FakeServer()
        let (model, _) = await started(server, kept: ScreenKept(room: "BCDFG"))
        #expect(model.phase == .lobby)
        #expect(model.table?.code == "BCDFG")
        #expect(await soon { server.log.all.contains("start BCDFG#1") })
        #expect(server.links.isEmpty, "a TV going back to its table shows no link")
    }

    @Test func aPosterMakesATableWithThisTVAsItsScreen() async {
        let server = FakeServer()
        let (model, keep) = await started(server)
        await model.make(game: GameCatalog.tiles.id)
        #expect(server.log.all.contains("create tiles"))
        #expect(model.phase == .lobby)
        #expect(model.table?.code == "NEWTB")
        await model.settle()
        #expect(await keep.load().room == "NEWTB")
        #expect(await soon { server.links.first?.stopped == true }, "home's link stops once a table is shown")
    }

    @Test func aTableThatCannotBeMadeLeavesTheTVHomeAndSaysNo() async {
        let server = FakeServer()
        server.failCreates()
        let (model, _) = await started(server)
        await model.make(game: GameCatalog.catTower.id)
        #expect(model.phase == .home)
        #expect(model.table == nil)
        #expect(model.refused == 1)
    }

    // MARK: the table's own news

    @Test func theTableItsPhasesAndGameOver() async {
        let server = FakeServer()
        let (model, _) = await atTable(server, "BCDFG", Rooms.emptyLobby("BCDFG"))
        #expect(model.phase == .lobby)
        let socket = server.sockets("BCDFG")[0]
        socket.emit(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 2, room: Rooms.playing("BCDFG"))))
        #expect(await soon { model.phase == .table })
        #expect(model.table?.scene != nil)
        socket.emit(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 3, room: Rooms.over("BCDFG"))))
        #expect(await soon { model.table?.store.phase == .over })
        // The table cheers first; game over comes up when the scene says it's done.
        #expect(model.phase == .table)
        model.table?.gameOver([1])
        #expect(model.phase == .over)
        #expect(model.winners == [1])
    }

    @Test func notScreenOrAMissingTableSendsTheTVHome() async {
        let server = FakeServer()
        let (model, keep) = await atTable(server, "BCDFG", Rooms.emptyLobby("BCDFG"))
        server.sockets("BCDFG")[0].emit(.notFound)
        #expect(await soon { model.phase == .home })
        #expect(model.table == nil)
        await model.settle()
        #expect(await keep.load().room == nil)
        #expect(await soon { server.links.first?.started == true }, "home shows a link again")
    }

    @Test func playAgainTakesTheTVToTheNewTableAfterLettingTheOldOneGo() async {
        let server = FakeServer()
        let (model, keep) = await atTable(server, "BCDFG", Rooms.over("BCDFG"))
        server.sockets("BCDFG")[0].emit(.message(.rematch(code: "NEXTT")))
        #expect(await soon { model.table?.code == "NEXTT" })
        #expect(model.phase == .lobby)
        #expect(await soon { server.log.all.contains("start NEXTT#1") })
        let stop = server.log.index(of: "stop BCDFG#1")
        let start = server.log.index(of: "start NEXTT#1")
        #expect(stop != nil && start != nil && stop! < start!, "the old table's socket closes before the new one opens: \(server.log.all)")
        await model.settle()
        #expect(await keep.load().room == "NEXTT")
    }

    // MARK: the menu

    @Test func theMenuButtonOpensTheMenuAndGoesBack() async {
        let server = FakeServer()
        let (model, _) = await atTable(server, "BCDFG", Rooms.playing("BCDFG"))
        #expect(model.menu == .closed)
        model.back()
        #expect(model.menu == .items)
        model.showLink()
        #expect(model.menu == .link)
        model.back()
        #expect(model.menu == .items)
        model.back()
        #expect(model.menu == .closed)
    }

    @Test func atHomeThereIsNoMenuSoMenuLeavesTheApp() async {
        let server = FakeServer()
        let (model, _) = await started(server)
        model.back()
        model.openMenu()
        #expect(model.menu == .closed)
        #expect(model.table == nil, "the root view hands Menu to tvOS only while no table is shown")
    }

    @Test func linkAnotherTableMovesTheTVClosingTheOldScreenSocketFirst() async {
        let server = FakeServer()
        let (model, keep) = await atTable(server, "BCDFG", Rooms.playing("BCDFG"))
        model.back()
        model.showLink()
        #expect(await soon { server.links.first?.started == true })
        let link = server.links[0]
        #expect(link.showing == "BCDFG", "the link says which table the TV shows")
        link.emit(.code(token: "tok", code: "QRSTVW", url: URL(string: "https://play.conleychaos.com/tv/tok")!))
        #expect(await soon { model.menuLink?.code == "QRSTVW" })

        link.emit(.linked(room: "MNPQR"))
        #expect(await soon { model.table?.code == "MNPQR" })
        #expect(model.menu == .closed)
        #expect(model.phase == .lobby)
        #expect(await soon { server.log.all.contains("start MNPQR#1") })
        let stop = server.log.index(of: "stop BCDFG#1")
        let start = server.log.index(of: "start MNPQR#1")
        #expect(stop != nil && start != nil && stop! < start!, "the old table's socket closes before the new one opens: \(server.log.all)")
        await model.settle()
        #expect(await keep.load().room == "MNPQR")
    }

    @Test func backFromTheLinkStopsIt() async {
        let server = FakeServer()
        let (model, _) = await atTable(server, "BCDFG", Rooms.playing("BCDFG"))
        model.back()
        model.showLink()
        #expect(await soon { server.links.first?.started == true })
        model.back()
        #expect(await soon { server.links[0].stopped })
        #expect(model.menuLink == nil)
    }

    @Test func leaveTableGoesHomeAndForgetsTheTable() async {
        let server = FakeServer()
        let (model, keep) = await atTable(server, "BCDFG", Rooms.playing("BCDFG"))
        model.back()
        model.leave()
        #expect(model.phase == .home)
        #expect(model.menu == .closed)
        #expect(model.table == nil)
        #expect(await soon { server.sockets("BCDFG")[0].isStopped })
        await model.settle()
        #expect(await keep.load().room == nil)
        #expect(await soon { server.links.first?.started == true })
    }

    @Test func soundIsTheTVsOwnAndKept() async {
        let server = FakeServer()
        let keep = MemoryScreenKeep(ScreenKept(room: nil, soundOn: false))
        var applied: [Bool] = []
        let model = TVModel(services: server.services(keep: keep, sound: { applied.append($0) }))
        await model.start()
        #expect(model.soundOn == false)
        #expect(applied == [false])
        model.toggleSound()
        #expect(model.soundOn)
        #expect(applied == [false, true])
        await model.settle()
        await model.settle()
        #expect(await keep.load().soundOn == true)
    }

    // MARK: Change game

    @Test func changeGameIsOfferedOnlyWhileNobodySits() async {
        let server = FakeServer()
        let (model, keep) = await atTable(server, "BCDFG", Rooms.emptyLobby("BCDFG"))
        #expect(model.canChangeGame)
        server.sockets("BCDFG")[0].emit(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 2, room: Rooms.seatedLobby("BCDFG"))))
        #expect(await soon { !model.canChangeGame })
        await model.changeGame()
        #expect(!server.log.all.contains { $0.hasPrefix("create") }, "nothing is made once someone sits")
        #expect(model.table?.code == "BCDFG")

        server.sockets("BCDFG")[0].emit(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 3, room: Rooms.emptyLobby("BCDFG"))))
        #expect(await soon { model.canChangeGame })
        await model.changeGame()
        #expect(server.log.all.contains("create tiles"), "Cat Tower's table changes to Tuna Tiles")
        #expect(model.table?.code == "NEWTB")
        #expect(await soon { server.log.all.contains("start NEWTB#1") })
        #expect(server.log.index(of: "stop BCDFG#1")! < server.log.index(of: "start NEWTB#1")!)
        await model.settle()
        #expect(await keep.load().room == "NEWTB")
    }

    @Test func changeGameIsNotOfferedAtTheTable() async {
        let server = FakeServer()
        let (model, _) = await atTable(server, "BCDFG", Rooms.playing("BCDFG"))
        #expect(await soon { model.phase == .table })
        #expect(!model.canChangeGame)
    }

    // MARK: sleeping and waking

    @Test func theTVLetsGoOfItsTableInTheBackgroundAndRejoinsOnReturn() async {
        let server = FakeServer()
        let (model, _) = await atTable(server, "BCDFG", Rooms.playing("BCDFG"))
        #expect(await soon { model.phase == .table })
        let store = model.table?.store
        await model.background()
        #expect(server.sockets("BCDFG")[0].isStopped)
        #expect(server.sockets("BCDFG").count == 1)
        await model.active()
        #expect(await soon { server.log.all.contains("start BCDFG#2") }, "it connects again as the table's screen")
        #expect(model.table?.store === store, "the same table: the scene keeps its place")
        server.sockets("BCDFG")[1].arrive(Rooms.playing("BCDFG"), seq: 5)
        #expect(await soon { model.table?.store.connected == true })
        #expect(model.phase == .table)
    }

    @Test func homesLinkStopsInTheBackgroundAndANewOneShowsOnReturn() async {
        let server = FakeServer()
        let (model, _) = await started(server)
        #expect(await soon { server.links.first?.started == true })
        await model.background()
        #expect(await soon { server.links[0].stopped })
        await model.active()
        #expect(await soon { server.links.count == 2 && server.links[1].started })
    }
}

@Suite("Game over's words")
struct TVStandingsTests {
    @Test func winnersFirstThenLevelThenFewestPoints() {
        var room = DemoFixtures.hitTable()
        room.status = .over
        room.game!.status = .gameOver
        room.game!.winners = [2]
        room.game!.phase = [3, 5, 9, 5]
        room.game!.scores = [10, 80, 40, 20]
        room.game!.forfeited = [false, false, false, false]
        let rows = TVStandings.rows(room)
        #expect(rows.map(\.seat) == [2, 3, 1, 0])
        #expect(rows[0].won)
        #expect(rows[0].detail == "Level 10 · 40")
        #expect(TVStandings.title(room) == "\(SeatInfo.name(room, 2)) wins")
    }

    @Test func tilesShowPointsAndAForfeitSaysLeft() {
        var room = DemoFixtures.tilesOver()
        room.tiles!.winners = []
        room.tiles!.scores = [12, -5, 0, -7]
        room.tiles!.forfeited = [false, false, true, false]
        let rows = TVStandings.rows(room)
        #expect(rows.map(\.seat) == [0, 1, 3, 2])
        #expect(rows.map(\.detail) == ["+12", "-5", "-7", "Left"])
        #expect(rows.last?.out == true)
        #expect(TVStandings.title(room) == "Game over")
    }
}
