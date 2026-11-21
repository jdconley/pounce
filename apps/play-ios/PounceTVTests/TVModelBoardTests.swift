import Foundation
import PounceKit
import Synchronization
import Testing
@testable import PounceTV

/// One board socket a test drives, recorded in the server's log as "board start <token>#n" and
/// "board stop <token>#n".
final class FakeBoardSocket: BoardSocketing {
    let token: String
    let n: Int
    let events: AsyncStream<BoardSocketEvent>
    private let feed: AsyncStream<BoardSocketEvent>.Continuation
    private let log: Log
    private let stopped = Mutex(false)

    init(token: String, n: Int, log: Log) {
        self.token = token
        self.n = n
        self.log = log
        (events, feed) = AsyncStream.makeStream(of: BoardSocketEvent.self)
    }

    var isStopped: Bool { stopped.withLock { $0 } }
    func start() async { log.add("board start \(token)#\(n)") }
    func stop() async {
        stopped.withLock { $0 = true }
        log.add("board stop \(token)#\(n)")
        feed.finish()
    }
    func emit(_ e: BoardSocketEvent) { feed.yield(e) }
}

/// A clock the test moves.
final class TestClock: Sendable {
    private let at = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { at.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { at.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

/// The fake server's services, with Tonight's board on.
final class BoardRig: Sendable {
    let server = FakeServer()
    let clock = TestClock()
    let boards: MemoryBoardKeep
    private let sockets = Mutex<[FakeBoardSocket]>([])

    init(kept: KeptBoard? = nil) { boards = MemoryBoardKeep(kept) }

    var boardSockets: [FakeBoardSocket] { sockets.withLock { $0 } }

    @MainActor
    func model(keep: ScreenKept = ScreenKept(), dishOn: Bool = true, unsure: Int = 0) -> TVModel {
        var services = server.services(keep: MemoryScreenKeep(keep))
        services.boardSocket = { token in
            self.sockets.withLock { s in
                let socket = FakeBoardSocket(token: token, n: s.filter { $0.token == token }.count + 1, log: self.server.log)
                s.append(socket)
                return socket
            }
        }
        services.boards = boards
        // The first `unsure` probes can't tell (offline, a busy server); then the answer.
        let asked = Mutex(0)
        services.dailyOn = { asked.withLock { $0 += 1; return $0 } <= unsure ? nil : dishOn }
        services.retryDelay = { _ in .milliseconds(1) }
        services.now = { self.clock.now }
        return TVModel(services: services)
    }
}

@MainActor
@Suite("Tonight's board in the TV's model")
struct TVModelBoardTests {
    let token = String(repeating: "B", count: 22)

    private func soon(_ done: () -> Bool) async -> Bool {
        for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(10)) }
        return done()
    }

    @Test func aKeptBoardOpensAtLaunch() async {
        let rig = BoardRig(kept: .fresh(token, now: Date(timeIntervalSince1970: 1_800_000_000)))
        let model = rig.model()
        await model.start()
        #expect(model.phase == .board)
        #expect(await soon { rig.server.log.all.contains("board start \(token)#1") })
        #expect(rig.server.links.isEmpty, "a TV going back to its board shows no link")
    }

    @Test func aKeptTableWinsOverAKeptBoard() async {
        let rig = BoardRig(kept: .fresh(token, now: Date(timeIntervalSince1970: 1_800_000_000)))
        let model = rig.model(keep: ScreenKept(room: "BCDFG"))
        await model.start()
        #expect(model.phase == .lobby)
    }

    @Test func aBoardPastItsThirtyDaysIsForgottenAtLaunch() async {
        let rig = BoardRig(kept: .fresh(token, now: Date(timeIntervalSince1970: 1_800_000_000 - 31 * 86_400)))
        let model = rig.model()
        await model.start()
        #expect(model.phase == .home)
        await model.settle()
        #expect(await rig.boards.load() == nil)
    }

    @Test func homesLinkBringsABoardKeptForThirtyDays() async {
        let rig = BoardRig()
        let model = rig.model()
        await model.start()
        #expect(await soon { rig.server.links.first?.started == true })
        #expect(await soon { model.dishOn })
        rig.server.links[0].emit(.board(token: token))
        #expect(await soon { model.phase == .board })
        await model.settle()
        #expect(await rig.boards.load() == .fresh(token, now: rig.clock.now))
        #expect(await soon { rig.server.log.all.contains("board start \(token)#1") })
    }

    @Test func theBoardsPosterOpensItsLinkUntilABoardIsKept() async {
        let rig = BoardRig()
        let model = rig.model()
        await model.start()
        model.pressBoard()
        #expect(model.boardLinkShown)
        #expect(model.takesBack)
        model.back()
        #expect(!model.boardLinkShown)
    }

    @Test func aBoardLinkedOverATableLetsTheTableGoFirst() async {
        let rig = BoardRig()
        let model = rig.model(keep: ScreenKept(room: "BCDFG"))
        await model.start()
        #expect(await soon { rig.server.sockets("BCDFG").count == 1 })
        model.openMenu()
        model.showLink()
        #expect(await soon { rig.server.links.first?.started == true })
        rig.server.links[0].emit(.board(token: token))
        #expect(await soon { model.phase == .board })
        #expect(model.table == nil)
        #expect(await soon { rig.server.log.all.contains("board start \(token)#1") })
        let log = rig.server.log
        #expect((log.index(of: "stop BCDFG#1") ?? .max) < (log.index(of: "board start \(token)#1") ?? -1))
        await model.settle()
        // A relaunch opens the board: the table is forgotten.
        let again = rig.model()
        await again.start()
        #expect(again.phase == .board)
    }

    @Test func aGoneBoardIsForgottenAndTheTVGoesHome() async {
        let rig = BoardRig(kept: .fresh(token, now: Date(timeIntervalSince1970: 1_800_000_000)))
        let model = rig.model()
        await model.start()
        #expect(await soon { rig.boardSockets.count == 1 })
        rig.boardSockets[0].emit(.gone)
        #expect(await soon { model.phase == .home })
        await model.settle()
        #expect(await rig.boards.load() == nil)
    }

    @Test func unlinkForgetsAndPlayAGameKeeps() async {
        let rig = BoardRig(kept: .fresh(token, now: Date(timeIntervalSince1970: 1_800_000_000)))
        let model = rig.model()
        await model.start()
        model.openMenu()
        #expect(model.menu == .items)
        model.playAGame()
        #expect(model.phase == .home)
        await model.settle()
        #expect(await rig.boards.load() != nil)
        model.pressBoard()
        #expect(model.phase == .board)
        model.unlink()
        #expect(model.phase == .home)
        await model.settle()
        #expect(await rig.boards.load() == nil)
        #expect(await soon { rig.boardSockets.allSatisfy(\.isStopped) })
    }

    @Test func aProbeThatCantTellIsAskedAgain() async {
        let rig = BoardRig()
        let model = rig.model(unsure: 2)
        await model.start()
        #expect(await soon { model.dishOn })
    }

    @Test func thePosterHidesWhileTheDishIsOff() async {
        let rig = BoardRig()
        let model = rig.model(dishOn: false)
        await model.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!model.dishOn)
    }

    @Test func theWatchCardGoesAfterTwentySecondsAndWatchBackReturnsToTheBoard() async throws {
        let rig = BoardRig(kept: .fresh(token, now: Date(timeIntervalSince1970: 1_800_000_000)))
        let model = rig.model()
        await model.start()
        #expect(await soon { rig.boardSockets.count == 1 })
        rig.boardSockets[0].emit(.message(.watchOffer(player: "me", name: "Mom", cat: 3, game: "test")))
        #expect(await soon { model.board?.state.offer != nil })
        rig.clock.advance(20)
        model.board?.tick()
        #expect(model.board?.state.offer != nil)
        rig.clock.advance(0.01)
        model.board?.tick()
        #expect(model.board?.state.offer == nil)

        rig.boardSockets[0].emit(.message(.watchOffer(player: "me", name: "Mom", cat: 3, game: "test")))
        #expect(await soon { model.board?.state.offer != nil })
        model.board?.watch()
        #expect(model.board?.state.watching != nil)
        model.back()
        #expect(model.board?.state.watching == nil)
        #expect(model.menu == .closed)
    }

    @Test func theBoardsSocketClosesInTheBackgroundAndANewOneOpensOnReturn() async {
        let rig = BoardRig(kept: .fresh(token, now: Date(timeIntervalSince1970: 1_800_000_000)))
        let model = rig.model()
        await model.start()
        #expect(await soon { rig.boardSockets.count == 1 })
        await model.background()
        #expect(await soon { rig.boardSockets[0].isStopped })
        await model.active()
        #expect(await soon { rig.server.log.all.contains("board start \(token)#2") })
        #expect(model.phase == .board)
    }
}
