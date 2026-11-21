import Foundation
import Testing

@testable import PounceKit

/// The test game's move and reveal (docs/daily-protocol.md: "count to 3 + level").
private struct Step: Codable, Sendable, Equatable {
    var k = "step"
    let n: Int
}

private struct Count: Codable, Sendable, Equatable { let n: Int }

/// A daily server in memory: it records each call and answers from a script.
actor FakeDaily: DailyService {
    enum Call: Equatable {
        case start, moves(from: Int, count: Int), hint, giveUp, tv(Bool), board, stats, link, unlink
    }

    var calls: [Call] = []
    var bodies: [DailyMovesBody] = []
    /// Answers for the moves route, in order; when empty, it accepts.
    var movesScript: [Result<DailyMovesAnswer, any Error>] = []
    var startAnswer: DailyStart
    var seq = 0
    var hintReveal: DailyJSON = .object(["n": .int(3)])

    init(start: DailyStart = FakeDaily.sample()) { startAnswer = start }

    static func sample(seq: Int = 0, state: Int = 0, result: DailyResult? = nil) -> DailyStart {
        DailyStart(
            run: "run1", game: "test", date: "2026-11-23", number: 1, level: 1, startedAt: 1_000_000, now: 1_000_000,
            puzzle: .object(["target": .int(4)]), state: .object(["n": .int(state)]), seq: seq, hints: 0, result: result,
            closesAt: 2_000_000)
    }

    func script(_ answers: [Result<DailyMovesAnswer, any Error>]) { movesScript = answers }
    func setStart(_ start: DailyStart) { startAnswer = start }

    func start(game: String, person: String?) async throws -> DailyStart {
        calls.append(.start)
        return startAnswer
    }

    func moves(run: String, body: DailyMovesBody, person: String?) async throws -> DailyMovesAnswer {
        calls.append(.moves(from: body.from, count: body.moves.count))
        bodies.append(body)
        if !movesScript.isEmpty { return try movesScript.removeFirst().get() }
        seq = body.from + body.moves.count
        return .accepted(seq: seq, reveals: [], progress: Double(seq) / 4, result: nil)
    }

    func hint(run: String, person: String?) async throws -> DailyMovesAnswer {
        calls.append(.hint)
        return .accepted(seq: seq, reveals: [hintReveal], progress: 0.75, result: nil)
    }

    func giveUp(run: String, person: String?) async throws -> DailyMovesAnswer {
        calls.append(.giveUp)
        let result = DailyResult(game: "test", date: "2026-11-23", number: 1, outcome: .gaveUp, timeMs: 5000, progress: 0.25)
        return .accepted(seq: seq, reveals: [], progress: 0.25, result: result)
    }

    func showOnTV(run: String, on: Bool, person: String?) async throws { calls.append(.tv(on)) }
    func board(date: String?, person: String?) async throws -> DailyBoard {
        calls.append(.board)
        return DailyBoard(date: "2026-11-23", games: [], dish: DailyDish(rows: []))
    }
    func stats(person: String?) async throws -> DailyStatsList {
        calls.append(.stats)
        return DailyStatsList(games: [:])
    }
    func linkBoard(_ key: ScreenKey, person: String?) async throws { calls.append(.link) }
    func unlinkBoard(person: String?) async throws { calls.append(.unlink) }
}

@Suite struct DailyRunSessionTests {
    private func session(_ fake: FakeDaily, window: Duration = .milliseconds(80)) async -> DailyRunSession {
        DailyRunSession(start: await fake.startAnswer, service: fake, person: "p1", window: window, retry: .milliseconds(10))
    }

    @Test func movesWaitForTheWindowAndGoInOneBatch() async {
        let fake = FakeDaily()
        let s = await session(fake)
        await s.send(move: Step(n: 1))
        await s.send(move: Step(n: 2))
        #expect(await fake.calls.isEmpty)
        await s.flush()
        #expect(await fake.calls == [.moves(from: 0, count: 2)])
        #expect(await s.seq == 2)
    }

    @Test func aBatchGoesOnItsOwnAfterTheWindow() async throws {
        let fake = FakeDaily()
        let s = await session(fake, window: .milliseconds(30))
        await s.send(move: Step(n: 1))
        try await Task.sleep(for: .milliseconds(300))
        #expect(await fake.calls == [.moves(from: 0, count: 1)])
    }

    @Test func anUrgentMoveGoesAtOnceWithWhatWaits() async throws {
        let fake = FakeDaily()
        let s = await session(fake, window: .seconds(30))
        await s.send(move: Step(n: 1))
        await s.send(move: Step(n: 2), urgent: true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(await fake.calls == [.moves(from: 0, count: 2)])
        let body = await fake.bodies.first
        #expect(body?.moves == [try DailyJSON(Step(n: 1)), try DailyJSON(Step(n: 2))])
    }

    @Test func aNetworkFailureResendsTheSameFrom() async {
        let fake = FakeDaily()
        await fake.script([.failure(APIError.transport("offline")), .failure(APIError.server(500))])
        let s = await session(fake)
        let events = await s.events()
        await s.send(move: Step(n: 1), urgent: true)
        await s.flush()
        #expect(await fake.calls == [.moves(from: 0, count: 1), .moves(from: 0, count: 1), .moves(from: 0, count: 1)])
        var links: [DailyLink] = []
        for await event in events {
            if case .link(let l) = event { links.append(l) }
            if case .accepted = event { break }
        }
        #expect(links == [.retrying, .ok])
    }

    @Test func anIllegalMoveResyncsFromAFreshStart() async {
        let fake = FakeDaily()
        await fake.script([.success(.refused(.illegal, at: 1, seq: 0))])
        let s = await session(fake)
        await fake.setStart(FakeDaily.sample(seq: 1, state: 1))
        let events = await s.events(reveal: Count.self, state: Count.self)
        await s.send(move: Step(n: 1))
        await s.send(move: Step(n: 5), urgent: true)
        await s.flush()
        let calls = await fake.calls
        #expect(calls == [.moves(from: 0, count: 2), .start])
        #expect(await s.seq == 1)
        for await event in events {
            if case .resync(let state, let seq, _) = event {
                #expect(state == Count(n: 1))
                #expect(seq == 1)
                break
            }
        }
    }

    @Test func tooSoonSendsTheMovesBeforeItFirst() async {
        let fake = FakeDaily()
        await fake.script([.success(.refused(.tooSoon, at: 1, seq: 0))])
        let s = await session(fake)
        await s.send(move: Step(n: 1))
        await s.send(move: Step(n: 2))
        await s.flush()
        #expect(await fake.calls == [.moves(from: 0, count: 2), .moves(from: 0, count: 1), .moves(from: 1, count: 1)])
        #expect(await s.seq == 2)
    }

    @Test func aResultEndsTheRun() async {
        let fake = FakeDaily()
        let result = DailyResult(game: "test", date: "2026-11-23", number: 1, outcome: .solved, timeMs: 9000, progress: 1)
        await fake.script([.success(.accepted(seq: 4, reveals: [], progress: 1, result: result))])
        let s = await session(fake)
        let events = await s.events()
        await s.send(move: Step(n: 4), urgent: true)
        await s.flush()
        #expect(await s.result == result)
        for await event in events {
            if case .ended(let r) = event {
                #expect(r == result)
                break
            }
        }
        // Moves after the end go nowhere.
        await s.send(move: Step(n: 5), urgent: true)
        await s.flush()
        #expect(await fake.calls.count == 1)
    }

    @Test func aHintFlushesFirstAndCounts() async {
        let fake = FakeDaily()
        let s = await session(fake, window: .seconds(30))
        await s.send(move: Step(n: 1))
        let reveal = await s.hint(as: Count.self)
        #expect(reveal == Count(n: 3))
        #expect(await fake.calls == [.moves(from: 0, count: 1), .hint])
        #expect(await s.hints == 1)
    }

    @Test func givingUpFlushesThenEnds() async {
        let fake = FakeDaily()
        let s = await session(fake, window: .seconds(30))
        await s.send(move: Step(n: 1))
        let result = await s.giveUp()
        #expect(result?.outcome == .gaveUp)
        #expect(await fake.calls == [.moves(from: 0, count: 1), .giveUp])
    }

    @Test func playWaitsForItsReveal() async {
        let fake = FakeDaily()
        await fake.script([.success(.accepted(seq: 1, reveals: [.object(["n": .int(9)])], progress: 0.25, result: nil))])
        let s = await session(fake, window: .seconds(30))
        let answer = await s.play(Step(n: 1), revealing: Count.self)
        guard case .accepted(let reveals) = answer else {
            Issue.record("refused")
            return
        }
        #expect(reveals == [Count(n: 9)])
    }

    @Test func aLostRunStops() async {
        let fake = FakeDaily()
        await fake.script([.failure(APIError.notFound)])
        let s = await session(fake)
        let answer = await s.play(Step(n: 1), revealing: Count.self)
        guard case .refused = answer else {
            Issue.record("accepted")
            return
        }
        #expect(await s.link == .lost)
    }

    @Test func anEndedRunTellsANewListenerAtOnce() async {
        let result = DailyResult(game: "test", date: "2026-11-23", number: 1, outcome: .solved, timeMs: 9000, progress: 1)
        let fake = FakeDaily(start: FakeDaily.sample(seq: 4, state: 4, result: result))
        let s = await session(fake)
        for await event in await s.events() {
            #expect(event == .ended(result))
            break
        }
    }

    @Test func theClockIsTheServers() {
        let start = FakeDaily.sample()
        // This device is 2 seconds behind the server.
        let received = Date(timeIntervalSince1970: 998)
        let clock = DailyClock(start: start, received: received)
        #expect(clock.skewMs == 2000)
        #expect(clock.elapsedMs(at: Date(timeIntervalSince1970: 1003), hints: 0) == 5000)
        #expect(clock.elapsedMs(at: Date(timeIntervalSince1970: 1003), hints: 1) == 35000)
        #expect(clock.elapsedMs(at: Date(timeIntervalSince1970: 900), hints: 0) == 0)
        #expect(DailyClock.format(ms: 247_000) == "4:07")
        #expect(DailyClock.format(ms: 3_729_000) == "1:02:09")
    }
}
