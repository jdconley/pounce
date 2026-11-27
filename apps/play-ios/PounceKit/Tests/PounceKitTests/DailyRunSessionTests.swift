import Foundation
import Synchronization
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
        case start, moves(from: Int, count: Int), hint(Int), giveUp, tv(Bool), board, stats, link, unlink
    }

    var calls: [Call] = []
    /// The `rules` each start asked for.
    var startRules: [String?] = []
    /// The `activeMs` each hint and give-up carried.
    var hintActive: [Int64?] = []
    var giveUpActive: [Int64?] = []
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
        try await start(game: game, person: person, rules: nil)
    }

    func start(game: String, person: String?, rules: String?) async throws -> DailyStart {
        calls.append(.start)
        startRules.append(rules)
        return startAnswer
    }

    func moves(run: String, body: DailyMovesBody, person: String?) async throws -> DailyMovesAnswer {
        calls.append(.moves(from: body.from, count: body.moves.count))
        bodies.append(body)
        if !movesScript.isEmpty { return try movesScript.removeFirst().get() }
        seq = body.from + body.moves.count
        return .accepted(seq: seq, reveals: [], progress: Double(seq) / 4, result: nil)
    }

    func hint(run: String, hints: Int, activeMs: Int64?, person: String?) async throws -> DailyMovesAnswer {
        hintActive.append(activeMs)
        return try await hint(run: run, hints: hints, person: person)
    }

    func giveUp(run: String, activeMs: Int64?, person: String?) async throws -> DailyMovesAnswer {
        giveUpActive.append(activeMs)
        return try await giveUp(run: run, person: person)
    }

    func hint(run: String, hints: Int, person: String?) async throws -> DailyMovesAnswer {
        calls.append(.hint(hints))
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

/// A timer the test moves by hand (`advance`): the session's batch window and retries open only
/// when the test says so, however slow the machine is. Nothing here sleeps or reads the wall clock.
final class ManualTimer: DailyTimer {
    private struct Sleeper {
        let id: Int
        let deadline: Duration
        let wake: CheckedContinuation<Void, Never>
    }
    private struct State {
        var now: Duration = .zero
        var nextID = 0
        var sleepers: [Sleeper] = []
        var cancelled: Set<Int> = []
        var watchers: [CheckedContinuation<Void, Never>] = []
    }
    private let state = Mutex(State())

    func now() -> Duration { state.withLock { $0.now } }

    func wait(until deadline: Duration) async {
        let id = state.withLock { s in
            s.nextID += 1
            return s.nextID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (wake: CheckedContinuation<Void, Never>) in
                let (now, watchers) = state.withLock { s -> (Bool, [CheckedContinuation<Void, Never>]) in
                    if deadline <= s.now || s.cancelled.remove(id) != nil { return (true, []) }
                    s.sleepers.append(Sleeper(id: id, deadline: deadline, wake: wake))
                    defer { s.watchers = [] }
                    return (false, s.watchers)
                }
                if now { wake.resume() }
                for w in watchers { w.resume() }
            }
        } onCancel: {
            let sleeper = state.withLock { s -> Sleeper? in
                guard let i = s.sleepers.firstIndex(where: { $0.id == id }) else {
                    s.cancelled.insert(id)
                    return nil
                }
                return s.sleepers.remove(at: i)
            }
            sleeper?.wake.resume()
        }
    }

    /// Moves time on, waking every sleeper whose deadline has come.
    func advance(by step: Duration) {
        let due = state.withLock { s -> [Sleeper] in
            s.now += step
            let due = s.sleepers.filter { $0.deadline <= s.now }
            s.sleepers.removeAll { $0.deadline <= s.now }
            return due
        }
        for sleeper in due { sleeper.wake.resume() }
    }

    /// Returns once something is asleep on this timer (the session waiting out its window or a retry).
    func sleeping() async {
        await withCheckedContinuation { (watch: CheckedContinuation<Void, Never>) in
            let asleep = state.withLock { s -> Bool in
                if !s.sleepers.isEmpty { return true }
                s.watchers.append(watch)
                return false
            }
            if asleep { watch.resume() }
        }
    }
}

@Suite struct DailyRunSessionTests {
    private static let window = Duration.seconds(1)
    private static let retry = Duration.milliseconds(500)

    private func session(_ fake: FakeDaily, timer: ManualTimer = ManualTimer()) async -> DailyRunSession {
        DailyRunSession(start: await fake.startAnswer, service: fake, person: "p1", window: Self.window, retry: Self.retry, timer: timer)
    }

    @Test func movesWaitForTheWindowAndGoInOneBatch() async {
        let fake = FakeDaily()
        let timer = ManualTimer()
        let s = await session(fake, timer: timer)
        await s.send(move: Step(n: 1))
        await s.send(move: Step(n: 2))
        await timer.sleeping()
        timer.advance(by: Self.window - .milliseconds(1))
        #expect(await fake.calls.isEmpty)
        await s.flush()
        #expect(await fake.calls == [.moves(from: 0, count: 2)])
        #expect(await s.seq == 2)
    }

    @Test func aBatchGoesOnItsOwnAfterTheWindow() async {
        let fake = FakeDaily()
        let timer = ManualTimer()
        let s = await session(fake, timer: timer)
        await s.send(move: Step(n: 1))
        await timer.sleeping()
        #expect(await fake.calls.isEmpty)
        timer.advance(by: Self.window)
        await s.settled()
        #expect(await fake.calls == [.moves(from: 0, count: 1)])
    }

    @Test func anUrgentMoveGoesAtOnceWithWhatWaits() async throws {
        let fake = FakeDaily()
        let s = await session(fake)
        await s.send(move: Step(n: 1))
        await s.send(move: Step(n: 2), urgent: true)
        await s.settled()
        #expect(await fake.calls == [.moves(from: 0, count: 2)])
        let body = await fake.bodies.first
        #expect(body?.moves == [try DailyJSON(Step(n: 1)), try DailyJSON(Step(n: 2))])
    }

    @Test func aNetworkFailureResendsTheSameFrom() async {
        let fake = FakeDaily()
        await fake.script([.failure(APIError.transport("offline")), .failure(APIError.server(500))])
        let timer = ManualTimer()
        let s = await session(fake, timer: timer)
        let events = await s.events()
        await s.send(move: Step(n: 1), urgent: true)
        // The first retry waits `retry`, the second twice that.
        await timer.sleeping()
        timer.advance(by: Self.retry)
        await timer.sleeping()
        timer.advance(by: Self.retry * 2)
        await s.settled()
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

    @Test func tooSoonResyncs() async {
        let fake = FakeDaily()
        await fake.script([.success(.refused(.tooSoon, at: 1, seq: 0))])
        let s = await session(fake)
        await fake.setStart(FakeDaily.sample(seq: 1, state: 1))
        await s.send(move: Step(n: 1))
        await s.send(move: Step(n: 2))
        await s.flush()
        let calls = await fake.calls
        #expect(calls == [.moves(from: 0, count: 2), .start])
        #expect(await s.seq == 1)
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
        let s = await session(fake)
        await s.send(move: Step(n: 1))
        let reveal = await s.hint(as: Count.self)
        #expect(reveal == Count(n: 3))
        #expect(await fake.calls == [.moves(from: 0, count: 1), .hint(0)])
        #expect(await s.hints == 1)
        _ = await s.hint(as: Count.self)
        #expect(await fake.calls.last == .hint(1))
    }

    @Test func givingUpFlushesThenEnds() async {
        let fake = FakeDaily()
        let s = await session(fake)
        await s.send(move: Step(n: 1))
        let result = await s.giveUp()
        #expect(result?.outcome == .gaveUp)
        #expect(await fake.calls == [.moves(from: 0, count: 1), .giveUp])
    }

    @Test func playWaitsForItsReveal() async {
        let fake = FakeDaily()
        await fake.script([.success(.accepted(seq: 1, reveals: [.object(["n": .int(9)])], progress: 0.25, result: nil))])
        let s = await session(fake)
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

    @Test func nineLivesAsksForLivesAtStartAndOnAResync() async {
        let fake = FakeDaily()
        await fake.script([.success(.refused(.illegal, at: 0, seq: 0))])
        let s = try? await DailyRunSession.begin(game: "nine-lives", service: fake, person: nil)
        #expect(s?.rules == "lives")
        await s?.send(move: Step(n: 1), urgent: true)
        await s?.flush()
        #expect(await fake.startRules == ["lives", "lives"])
        // A game with one set of rules sends no body.
        _ = try? await DailyRunSession.begin(game: "sniff", service: fake, person: nil)
        #expect(await fake.startRules.last == .some(nil))
    }

    @Test func aHintCostsTheStartsHintMs() {
        let free = DailyStart(
            run: "r", game: "nine-lives", date: "2026-11-23", number: 1, level: 1, startedAt: 1_000_000, now: 1_000_000,
            puzzle: .null, state: .null, seq: 0, hints: 0, result: nil, closesAt: 2_000_000, hintMs: 0, activeMs: 0)
        let clock = DailyClock(start: free, received: Date(timeIntervalSince1970: 1000))
        #expect(clock.shownMs(active: 3000, hints: 3) == 3000)
        #expect(DailyClock(start: FakeDaily.sample()).shownMs(active: 3000, hints: 1) == 33_000)
    }

    @Test func theClockStartsFromTheServersActiveTime() {
        let start = FakeDaily.sample()
        // This device is 2 seconds behind the server.
        let clock = DailyClock(start: start, received: Date(timeIntervalSince1970: 998))
        #expect(clock.skewMs == 2000)
        // No `activeMs` (a server before active time): its clock from the start.
        #expect(clock.activeMs == 0)
        let later = DailyStart(
            run: "r", game: "test", date: "d", number: 1, level: 1, startedAt: 1_000_000, now: 1_025_000, puzzle: .null,
            state: .null, seq: 0, hints: 0, result: nil, closesAt: 2_000_000)
        #expect(DailyClock(start: later).activeMs == 25_000)
        let resumed = DailyStart(
            run: "r", game: "test", date: "d", number: 1, level: 1, startedAt: 1_000_000, now: 9_000_000, puzzle: .null,
            state: .null, seq: 0, hints: 0, result: nil, closesAt: 2_000_000, activeMs: 18_250)
        #expect(DailyClock(start: resumed).activeMs == 18_250)
        #expect(DailyClock.format(ms: 247_000) == "4:07")
        #expect(DailyClock.format(ms: 3_729_000) == "1:02:09")
    }

    @Test func activeTimeCountsOnlyWhileRunning() {
        var t = DailyActiveTime(ms: 1000)
        #expect(t.ms(at: .seconds(50)) == 1000 && !t.running)
        t.resume(at: .seconds(10))
        #expect(t.ms(at: .milliseconds(12_500)) == 3500)
        t.resume(at: .seconds(11))
        #expect(t.ms(at: .seconds(12)) == 3000, "a second resume restarts nothing")
        t.pause(at: .seconds(14))
        #expect(t.ms(at: .seconds(100)) == 5000, "paused: the time away doesn't count")
        t.resume(at: .seconds(100))
        #expect(t.ms(at: .seconds(101)) == 6000)
        t.raise(to: 9000, at: .seconds(101))
        #expect(t.ms(at: .seconds(101)) == 9000)
        t.raise(to: 2000, at: .seconds(101))
        #expect(t.ms(at: .seconds(102)) == 10_000, "a lower count never wins")
    }

    @Test func everyCallCarriesTheActiveTimeAndAwayTimeDoesntCount() async {
        let fake = FakeDaily(start: DailyStart(
            run: "run1", game: "test", date: "2026-11-23", number: 1, level: 1, startedAt: 1_000_000, now: 1_000_000,
            puzzle: .object(["target": .int(4)]), state: .object(["n": .int(0)]), seq: 0, hints: 0, result: nil,
            closesAt: 2_000_000, activeMs: 2000))
        let timer = ManualTimer()
        let s = await session(fake, timer: timer)
        // Off screen until the host says so.
        timer.advance(by: .seconds(30))
        #expect(await s.activeMs == 2000)
        await s.setActive(true)
        timer.advance(by: .seconds(5))
        await s.send(move: Step(n: 1), urgent: true)
        await s.flush()
        #expect(await fake.bodies.last?.activeMs == 7000)
        // Away (Home, a sheet, the background): an hour that doesn't count.
        await s.setActive(false)
        timer.advance(by: .seconds(3600))
        await s.setActive(true)
        timer.advance(by: .seconds(1))
        _ = await s.hint()
        #expect(await fake.hintActive == [8000])
        timer.advance(by: .seconds(2))
        await s.giveUp()
        #expect(await fake.giveUpActive == [10_000])
        // Ended: it stops.
        timer.advance(by: .seconds(60))
        await s.setActive(true)
        #expect(await s.activeMs == 10_000)
    }
}
