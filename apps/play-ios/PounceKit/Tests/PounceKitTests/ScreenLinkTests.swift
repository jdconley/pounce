import Foundation
import Synchronization
import Testing
@testable import PounceKit

// MARK: - fakes

/// Sleeps that end only when the test moves time on, like the web tests' `Clock`.
final class ManualClock: Sendable {
    private struct Waiter {
        let id: Int
        let at: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now: Duration = .zero
        var waiters: [Waiter] = []
        var cancelled: Set<Int> = []
        var nextID = 0
    }

    private let state = Mutex(State())

    /// How long each pending sleep has left, soonest first.
    var pending: [Duration] { state.withLock { s in s.waiters.map { $0.at - s.now }.sorted() } }

    func sleep(_ duration: Duration) async throws {
        let id = state.withLock { s in
            s.nextID += 1
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let now: Result<Void, any Error>? = state.withLock { s in
                    if s.cancelled.remove(id) != nil { return .failure(CancellationError()) }
                    if duration <= .zero { return .success(()) }
                    s.waiters.append(Waiter(id: id, at: s.now + duration, continuation: continuation))
                    return nil
                }
                if let now { continuation.resume(with: now) }
            }
        } onCancel: {
            let continuation = state.withLock { s -> CheckedContinuation<Void, any Error>? in
                if let i = s.waiters.firstIndex(where: { $0.id == id }) { return s.waiters.remove(at: i).continuation }
                s.cancelled.insert(id)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Moves time on and wakes every sleep that is now due, in the order they fall due.
    func advance(_ by: Duration) {
        let due = state.withLock { s -> [Waiter] in
            s.now += by
            let due = s.waiters.filter { $0.at <= s.now }.sorted { $0.at < $1.at }
            s.waiters.removeAll { $0.at <= s.now }
            return due
        }
        for waiter in due { waiter.continuation.resume() }
    }

    /// Waits until a sleep with exactly `due` left is pending (the timer under test has started),
    /// then moves time on by `by`. False, without moving time, when no such sleep appears.
    func advance(by: Duration, afterPending due: Duration) async -> Bool {
        guard await eventually({ pending.contains(due) }) else { return false }
        advance(by)
        return true
    }

    /// Moves time on by exactly the pending `due`.
    func advance(afterPending due: Duration) async -> Bool {
        await advance(by: due, afterPending: due)
    }
}

/// `POST /v1/screens`, scripted: each answer is a new token, `tok1`, `tok2`, ….
final class FakeScreens: Sendable {
    private struct State {
        var asked: [String?] = []
        var calls = 0
        var made = 0
        var fail = false
        var hold = false
    }

    let expiresIn: Int
    private let state = Mutex(State())
    private let gate = Mailbox<Void>()

    init(expiresIn: Int) { self.expiresIn = expiresIn }

    /// Calls begun, and calls answered.
    var calls: Int { state.withLock { $0.calls } }
    var made: Int { state.withLock { $0.made } }
    var asked: [String?] { state.withLock { $0.asked } }

    func failing(_ on: Bool) { state.withLock { $0.fail = on } }
    /// Calls wait for `release()` while this holds.
    func holding(_ on: Bool) { state.withLock { $0.hold = on } }
    func release() { gate.put(()) }

    func call(_ showing: String?) async throws -> ScreenLinkOffer {
        let (fail, hold) = state.withLock { s in
            s.calls += 1
            return (s.fail, s.hold)
        }
        if fail { throw APIError.transport("offline") }
        if hold { try await gate.take() }
        let n = state.withLock { s in
            s.asked.append(showing)
            s.made += 1
            return s.made
        }
        return ScreenLinkOffer(token: "tok\(n)", code: "CODE\(n)", url: URL(string: "https://x/tv/tok\(n)")!, expiresIn: expiresIn)
    }
}

/// One TV link socket the test drives: push frames, drop it. It answers `{"t":"ping"}` with a pong
/// when `pongs`, as the server does.
final class LinkConnection: WebSocketConnection {
    let url: URL
    private let pongs: Mutex<Bool>
    private let frames = Mailbox<String>()
    private let sentLog = Mutex<[String]>([])

    init(url: URL, pongs: Bool) {
        self.url = url
        self.pongs = Mutex(pongs)
    }

    func push(_ frame: String) { frames.put(frame) }
    /// From now on pings go unanswered, as on a socket that died without a close.
    func silence() { pongs.withLock { $0 = false } }
    func drop() { frames.close(Dropped()) }

    var sent: [String] { sentLog.withLock { $0 } }
    var isClosed: Bool { frames.isClosed }

    func send(_ text: String) async throws {
        if frames.isClosed { throw Dropped() }
        sentLog.withLock { $0.append(text) }
        if pongs.withLock({ $0 }), text == #"{"t":"ping"}"# { frames.put(#"{"t":"pong"}"#) }
    }

    func receive() async throws -> String { try await frames.take() }
    func sendPing() async throws {}
    func close() async { frames.close(Dropped()) }
}

/// Opens a new `LinkConnection` per call, unless a failure is queued; while held, a connect waits
/// for `release()` (the upgrade hasn't gone through yet).
final class LinkConnector: WebSocketConnector {
    private struct State {
        var calls: [(url: URL, token: String)] = []
        var made: [LinkConnection] = []
        var failures: [SocketConnectError] = []
        var hold = false
    }

    private let pongs: Bool
    private let state = Mutex(State())
    private let gate = Mailbox<Void>()

    init(pongs: Bool = true) { self.pongs = pongs }

    var calls: [(url: URL, token: String)] { state.withLock { $0.calls } }
    var made: [LinkConnection] { state.withLock { $0.made } }

    func fail(_ errors: SocketConnectError...) { state.withLock { $0.failures += errors } }
    func holding(_ on: Bool) { state.withLock { $0.hold = on } }
    func release() { gate.put(()) }

    func connect(url: URL, token: String) async throws -> any WebSocketConnection {
        let (failure, hold) = state.withLock { s -> (SocketConnectError?, Bool) in
            s.calls.append((url, token))
            return (s.failures.isEmpty ? nil : s.failures.removeFirst(), s.hold)
        }
        if let failure { throw failure }
        if hold { try await gate.take() }
        let connection = LinkConnection(url: url, pongs: pongs)
        state.withLock { $0.made.append(connection) }
        return connection
    }
}

/// Everything the link emits, in order, and whether its stream has finished.
final class LinkEvents: Sendable {
    private let log = Mutex<(events: [ScreenLinkEvent], finished: Bool)>(([], false))

    init(_ stream: AsyncStream<ScreenLinkEvent>) {
        Task { [self] in
            for await event in stream { log.withLock { $0.events.append(event) } }
            log.withLock { $0.finished = true }
        }
    }

    var all: [ScreenLinkEvent] { log.withLock { $0.events } }
    var finished: Bool { log.withLock { $0.finished } }
    var tokens: [String] {
        all.compactMap { if case .code(let token, _, _) = $0 { token } else { nil } }
    }
    var offline: Int { all.filter { $0 == .offline }.count }
}

/// Lets in-flight work run, for checks that something did not happen.
func settle() async {
    for _ in 0..<50 {
        await Task.yield()
        try? await Task.sleep(for: .microseconds(200))
    }
}

// MARK: - tests

@Suite(.timeLimit(.minutes(1))) struct ScreenLinkTests {
    struct Rig {
        let link: ScreenLink
        let screens: FakeScreens
        let connector: LinkConnector
        let clock: ManualClock
        let events: LinkEvents
    }

    private static let config = APIConfig(baseURL: URL(string: "http://localhost:8787")!)

    /// `expiresIn` is milliseconds, as the server sends it.
    private func rig(expiresIn: Int = 100_000, heartbeat: Duration? = nil, pongs: Bool = true) -> Rig {
        let screens = FakeScreens(expiresIn: expiresIn)
        let connector = LinkConnector(pongs: pongs)
        let clock = ManualClock()
        let link = ScreenLink(
            config: Self.config,
            screens: { try await screens.call($0) },
            credential: { DeviceCredential(deviceId: "tv", token: "tvtok") },
            connector: connector,
            backoff: [.milliseconds(250), .milliseconds(500), .seconds(1)],
            heartbeat: heartbeat,
            sleep: { try await clock.sleep($0) })
        return Rig(link: link, screens: screens, connector: connector, clock: clock, events: LinkEvents(link.events))
    }

    /// Started, with its first socket open.
    private func started(_ r: Rig, showing: String? = nil) async throws -> LinkConnection {
        await r.link.start(showing: showing)
        #expect(await eventually { r.connector.made.count == 1 })
        return try #require(r.connector.made.first)
    }

    private func linked(_ room: String) -> String { #"{"t":"linked","room":"\#(room)"}"# }
    private let expired = #"{"t":"expired"}"#

    @Test func emitsTheCodeAndListensOnTheTokensSocketAsTheDevice() async throws {
        let r = rig()
        _ = try await started(r)
        #expect(r.events.all == [.code(token: "tok1", code: "CODE1", url: URL(string: "https://x/tv/tok1")!)])
        #expect(r.connector.calls.map(\.url.absoluteString) == ["ws://localhost:8787/v1/screens/tok1/ws"])
        #expect(r.connector.calls.map(\.token) == ["tvtok"])
        #expect(r.screens.asked == [nil])
        await r.link.stop()
    }

    @Test func asksToShowATableWhenGivenOne() async throws {
        let r = rig()
        _ = try await started(r, showing: "BCDFG")
        #expect(r.screens.asked == ["BCDFG"])
        await r.link.stop()
    }

    @Test func aTenMinuteLinkRenewsAt480Seconds() async throws {
        let r = rig(expiresIn: 600_000)
        let first = try await started(r)
        #expect(await r.clock.advance(by: .milliseconds(479_999), afterPending: .milliseconds(480_000)))
        await settle()
        #expect(r.screens.calls == 1)
        #expect(await r.clock.advance(afterPending: .milliseconds(1)))
        #expect(await eventually { r.connector.made.count == 2 })
        #expect(r.events.tokens == ["tok1", "tok2"])
        #expect(r.connector.calls.map(\.url.path) == ["/v1/screens/tok1/ws", "/v1/screens/tok2/ws"])
        // The new socket opened, so the old one is closed.
        #expect(await eventually { first.isClosed })
        #expect(!r.connector.made[1].isClosed)
        #expect(r.events.offline == 0)
        await r.link.stop()
    }

    @Test func aCodeLinkedWhileItsRenewalIsStillAskingIsNotLost() async throws {
        let r = rig()
        let first = try await started(r)
        r.screens.holding(true)
        #expect(await r.clock.advance(afterPending: .seconds(80)))
        #expect(await eventually { r.screens.calls == 2 })
        #expect(!first.isClosed)
        first.push(linked("BCDFG"))
        #expect(await eventually { r.events.finished })
        #expect(r.events.all.last == .linked(room: "BCDFG"))
        r.screens.release()
        await settle()
        #expect(r.events.tokens == ["tok1"])
        #expect(r.connector.calls.count == 1)
        #expect(first.isClosed)
    }

    @Test func aRenewalThatFailsLeavesTheOldSocketOpen() async throws {
        let r = rig()
        let first = try await started(r)
        r.screens.failing(true)
        #expect(await r.clock.advance(afterPending: .seconds(80)))
        #expect(await eventually { r.screens.calls == 2 })
        await settle()
        #expect(!first.isClosed)
        #expect(r.events.offline == 0)
        // It asks again, quietly, after the backoff.
        #expect(await r.clock.advance(afterPending: .milliseconds(250)))
        #expect(await eventually { r.screens.calls == 3 })
        await settle()
        #expect(r.events.offline == 0)
        first.push(linked("BCDFG"))
        #expect(await eventually { r.events.finished })
        #expect(r.events.all.last == .linked(room: "BCDFG"))
    }

    @Test func theOldSocketKeepsListeningUntilTheNewOneOpensAndALinkOnItWins() async throws {
        let r = rig()
        let first = try await started(r)
        r.connector.holding(true)
        #expect(await r.clock.advance(afterPending: .seconds(80)))
        #expect(await eventually { r.connector.calls.count == 2 })
        #expect(r.events.tokens == ["tok1", "tok2"])
        await settle()
        #expect(!first.isClosed)
        first.push(linked("BCDFG"))
        #expect(await eventually { r.events.finished })
        #expect(r.events.all.last == .linked(room: "BCDFG"))
        #expect(await eventually { first.isClosed })
        // The upgrade that went through too late is closed at once.
        r.connector.release()
        #expect(await eventually { r.connector.made.count == 2 })
        #expect(await eventually { r.connector.made[1].isClosed })
    }

    @Test func theOldSocketClosesWhenTheNewOneOpens() async throws {
        let r = rig()
        let first = try await started(r)
        r.connector.holding(true)
        #expect(await r.clock.advance(afterPending: .seconds(80)))
        #expect(await eventually { r.connector.calls.count == 2 })
        await settle()
        #expect(!first.isClosed)
        r.connector.release()
        #expect(await eventually { first.isClosed })
        let second = try #require(r.connector.made.last)
        #expect(!second.isClosed)
        second.push(linked("BCDFG"))
        #expect(await eventually { r.events.finished })
        #expect(r.events.all.last == .linked(room: "BCDFG"))
    }

    @Test func theServersExpiredRenewsAtOnce() async throws {
        let r = rig()
        let first = try await started(r)
        first.push(expired)
        #expect(await eventually { r.connector.made.count == 2 })
        #expect(r.events.tokens == ["tok1", "tok2"])
        #expect(await eventually { first.isClosed })
        #expect(r.connector.made[1].url.path == "/v1/screens/tok2/ws")
        await r.link.stop()
    }

    /// The link being replaced expires while its successor's socket is still opening: expected, so
    /// no new link is asked for and nothing is offline.
    @Test func theReplacedLinkExpiringChangesNothing() async throws {
        let r = rig()
        let first = try await started(r)
        r.connector.holding(true)
        #expect(await r.clock.advance(afterPending: .seconds(80)))
        #expect(await eventually { r.connector.calls.count == 2 })
        first.push(expired)
        first.drop()
        await settle()
        #expect(r.screens.calls == 2)
        #expect(r.events.tokens == ["tok1", "tok2"])
        #expect(r.events.offline == 0)
        r.connector.release()
        #expect(await eventually { r.connector.made.count == 2 })
        await settle()
        #expect(!r.connector.made[1].isClosed)
        #expect(r.connector.calls.count == 2)
        await r.link.stop()
    }

    /// The renewal's socket can't connect (the network, not a refused link): the old socket keeps
    /// listening, quietly, until the new one opens.
    @Test func aRenewalWhoseSocketFailsKeepsTheOldSocket() async throws {
        let r = rig()
        let first = try await started(r)
        r.connector.fail(.failed("down"))
        #expect(await r.clock.advance(afterPending: .seconds(80)))
        #expect(await eventually { r.connector.calls.count == 2 })
        await settle()
        #expect(!first.isClosed)
        #expect(r.events.offline == 0)
        #expect(await r.clock.advance(afterPending: .milliseconds(250)))
        #expect(await eventually { r.connector.made.count == 2 })
        #expect(r.connector.made[1].url.path == "/v1/screens/tok2/ws")
        #expect(await eventually { first.isClosed })
        #expect(r.events.offline == 0)
        await r.link.stop()
    }

    @Test func aLinkOnTheOldSocketWinsWhileTheRenewalsSocketRetries() async throws {
        let r = rig()
        let first = try await started(r)
        r.connector.fail(.failed("down"))
        #expect(await r.clock.advance(afterPending: .seconds(80)))
        #expect(await eventually { r.clock.pending.contains(.milliseconds(250)) })
        first.push(linked("BCDFG"))
        #expect(await eventually { r.events.finished })
        #expect(r.events.all.last == .linked(room: "BCDFG"))
        #expect(await eventually { first.isClosed })
        #expect(await eventually { r.clock.pending.isEmpty })
        #expect(r.connector.calls.count == 2)
    }

    /// The old socket goes silent while the renewal's socket is still opening: it is closed, and
    /// quietly, since the new link is the one shown.
    @Test func aSilentOldSocketIsClosed() async throws {
        let r = rig(heartbeat: .seconds(25))
        let first = try await started(r)
        #expect(await r.clock.advance(afterPending: .seconds(25)))
        #expect(await eventually { first.sent.count == 1 })
        #expect(await r.clock.advance(afterPending: .seconds(25)))
        #expect(await eventually { first.sent.count == 2 })
        // 50 s in. Silence it, then a ping goes out at 75 s that nothing answers.
        first.silence()
        r.connector.holding(true)
        #expect(await r.clock.advance(afterPending: .seconds(25)))
        #expect(await eventually { first.sent.count == 3 })
        // 80 s: the renewal; its socket waits on the upgrade.
        #expect(await r.clock.advance(afterPending: .seconds(5)))
        #expect(await eventually { r.connector.calls.count == 2 })
        #expect(!first.isClosed)
        // 100 s: the old socket's next beat finds it silent.
        #expect(await r.clock.advance(afterPending: .seconds(20)))
        #expect(await eventually { first.isClosed })
        await settle()
        #expect(r.events.offline == 0)
        r.connector.release()
        #expect(await eventually { r.connector.made.count == 2 })
        #expect(!r.connector.made[1].isClosed)
        await r.link.stop()
    }

    @Test func expiredAfterLinkedIsIgnored() async throws {
        let r = rig()
        let first = try await started(r)
        first.push(linked("BCDFG"))
        first.push(expired)
        #expect(await eventually { r.events.finished })
        await settle()
        #expect(r.events.all == [.code(token: "tok1", code: "CODE1", url: URL(string: "https://x/tv/tok1")!), .linked(room: "BCDFG")])
        #expect(r.screens.calls == 1)
        #expect(r.connector.calls.count == 1)
        // Linked stops renewals too: no timer is left to fire.
        #expect(await eventually { r.clock.pending.isEmpty })
        r.clock.advance(.seconds(200))
        await settle()
        #expect(r.screens.calls == 1)
    }

    /// A token the server no longer knows (404, a browser's 4404) or a device token it refused
    /// (401, 4401) is replaced with a new link, not retried.
    @Test(arguments: [SocketConnectError.notFound, .unauthorized])
    func aRefusedTokenRenews(_ error: SocketConnectError) async throws {
        let r = rig()
        r.connector.fail(error)
        await r.link.start(showing: nil)
        #expect(await eventually { r.connector.calls.count == 1 })
        #expect(await r.clock.advance(afterPending: .milliseconds(250)))
        #expect(await eventually { r.connector.made.count == 1 })
        #expect(r.events.tokens == ["tok1", "tok2"])
        #expect(r.connector.calls.map(\.url.path) == ["/v1/screens/tok1/ws", "/v1/screens/tok2/ws"])
        await r.link.stop()
    }

    @Test func aDroppedSocketReconnectsToTheSameTokenWithBackoff() async throws {
        let r = rig()
        let first = try await started(r)
        first.drop()
        #expect(await eventually { r.events.all.last == .offline })
        await settle()
        #expect(r.connector.calls.count == 1)
        #expect(await r.clock.advance(afterPending: .milliseconds(250)))
        #expect(await eventually { r.connector.made.count == 2 })
        #expect(r.connector.made[1].url.path == "/v1/screens/tok1/ws")
        // Opening resets the backoff.
        r.connector.made[1].drop()
        #expect(await eventually { r.events.offline == 2 })
        #expect(await r.clock.advance(by: .milliseconds(249), afterPending: .milliseconds(250)))
        await settle()
        #expect(r.connector.calls.count == 2)
        #expect(await r.clock.advance(afterPending: .milliseconds(1)))
        #expect(await eventually { r.connector.made.count == 3 })
        #expect(r.screens.calls == 1)
        await r.link.stop()
    }

    @Test func aFailedConnectClimbsTheBackoff() async throws {
        let r = rig()
        r.connector.fail(.failed("down"), .failed("down"))
        await r.link.start(showing: nil)
        #expect(await eventually { r.events.offline == 1 })
        #expect(await r.clock.advance(afterPending: .milliseconds(250)))
        #expect(await eventually { r.connector.calls.count == 2 })
        #expect(await r.clock.advance(by: .milliseconds(499), afterPending: .milliseconds(500)))
        await settle()
        #expect(r.connector.calls.count == 2)
        #expect(await r.clock.advance(afterPending: .milliseconds(1)))
        #expect(await eventually { r.connector.made.count == 1 })
        await r.link.stop()
    }

    @Test func noAnswerFromTheServerIsOfflineAndAsksAgain() async throws {
        let r = rig()
        r.screens.failing(true)
        await r.link.start(showing: nil)
        #expect(await eventually { r.events.all == [.offline] })
        r.screens.failing(false)
        #expect(await r.clock.advance(afterPending: .milliseconds(250)))
        #expect(await eventually { r.connector.made.count == 1 })
        #expect(r.events.tokens == ["tok1"])
        await r.link.stop()
    }

    @Test func answersAPingWithAPong() async throws {
        let r = rig()
        let first = try await started(r)
        first.push(#"{"t":"ping"}"#)
        #expect(await eventually { first.sent.contains(#"{"t":"pong"}"#) })
        await r.link.stop()
    }

    @Test func heartbeatsKeepALiveSocketAndDropASilentOne() async throws {
        let live = rig(heartbeat: .seconds(25))
        let a = try await started(live)
        for n in 1...3 {
            #expect(await live.clock.advance(afterPending: .seconds(25)))
            #expect(await eventually { a.sent.filter { $0 == #"{"t":"ping"}"# }.count == n })
        }
        await settle()
        #expect(!a.isClosed)
        #expect(live.events.offline == 0)
        await live.link.stop()

        let silent = rig(heartbeat: .seconds(25), pongs: false)
        let b = try await started(silent)
        #expect(await silent.clock.advance(afterPending: .seconds(25)))
        #expect(await eventually { b.sent == [#"{"t":"ping"}"#] })
        #expect(await silent.clock.advance(afterPending: .seconds(25)))
        #expect(await eventually { b.isClosed })
        #expect(await eventually { silent.events.all.last == .offline })
        #expect(await silent.clock.advance(afterPending: .milliseconds(250)))
        #expect(await eventually { silent.connector.made.count == 2 })
        await silent.link.stop()
    }

    @Test func stopClosesTheSocketAndEndsRenewals() async throws {
        let r = rig()
        let first = try await started(r)
        await r.link.stop()
        #expect(first.isClosed)
        #expect(await eventually { r.events.finished })
        #expect(await eventually { r.clock.pending.isEmpty })
        r.clock.advance(.seconds(200))
        await settle()
        #expect(r.screens.calls == 1)
        #expect(r.connector.calls.count == 1)
    }

    /// Whoever reads the events went away: the link stops itself.
    @Test func cancellingTheReaderStops() async throws {
        let screens = FakeScreens(expiresIn: 100_000)
        let connector = LinkConnector()
        let clock = ManualClock()
        let link = ScreenLink(
            config: Self.config, screens: { try await screens.call($0) },
            credential: { DeviceCredential(deviceId: "tv", token: "tvtok") }, connector: connector,
            heartbeat: nil, sleep: { try await clock.sleep($0) })
        let reader = Task { for await _ in link.events {} }
        await link.start(showing: nil)
        #expect(await eventually { connector.made.count == 1 })
        #expect(clock.pending == [.seconds(80)])
        reader.cancel()
        #expect(await eventually { connector.made[0].isClosed })
        #expect(await eventually { clock.pending.isEmpty })
        await link.start(showing: nil)
        await settle()
        #expect(screens.calls == 1)
    }

    @Test func stopWhileAskingEmitsNothingMore() async throws {
        let r = rig()
        r.screens.holding(true)
        await r.link.start(showing: nil)
        #expect(await eventually { r.screens.calls == 1 })
        await r.link.stop()
        r.screens.release()
        await settle()
        #expect(r.events.all.isEmpty)
        #expect(r.events.finished)
        #expect(r.connector.calls.isEmpty)
    }

    @Test func stopWhileConnectingClosesTheLateSocket() async throws {
        let r = rig()
        r.connector.holding(true)
        await r.link.start(showing: nil)
        #expect(await eventually { r.connector.calls.count == 1 })
        await r.link.stop()
        r.connector.release()
        #expect(await eventually { r.connector.made.count == 1 })
        #expect(await eventually { r.connector.made[0].isClosed })
    }

    @Test func startsOnce() async throws {
        let r = rig()
        _ = try await started(r)
        await r.link.start(showing: "BCDFG")
        await settle()
        #expect(r.screens.calls == 1)
        await r.link.stop()
        await r.link.start(showing: nil)
        await settle()
        #expect(r.screens.calls == 1)
    }
}

@Suite struct ScreenLinkWireTests {
    @Test func roomSocketURLCarriesTheRole() {
        let prod = APIConfig(baseURL: URL(string: "https://play.conleychaos.com")!)
        #expect(prod.socketURL(code: "BCDFG", role: .screen).absoluteString == "wss://play.conleychaos.com/v1/rooms/BCDFG/ws?role=screen")
        #expect(prod.socketURL(code: "BCDFG", role: nil).absoluteString == "wss://play.conleychaos.com/v1/rooms/BCDFG/ws")
        #expect(prod.socketURL(code: "BCDFG").absoluteString == "wss://play.conleychaos.com/v1/rooms/BCDFG/ws")
        let local = APIConfig(baseURL: URL(string: "http://localhost:8787/?x=1")!)
        #expect(local.socketURL(code: "BCDFG", role: .screen).absoluteString == "ws://localhost:8787/v1/rooms/BCDFG/ws?role=screen")
    }

    @Test func screenSocketURLIsTheTokensPath() {
        let prod = APIConfig(baseURL: URL(string: "https://play.conleychaos.com")!)
        #expect(prod.screenSocketURL(token: "abc_DEF-123").absoluteString == "wss://play.conleychaos.com/v1/screens/abc_DEF-123/ws")
    }

    @Test func theOfferDecodesTheServersAnswer() throws {
        let json = #"{"token":"t","code":"ABCDFG","url":"https://play.conleychaos.com/tv/t","expiresIn":600000}"#
        let offer = try JSONDecoder().decode(ScreenLinkOffer.self, from: Data(json.utf8))
        #expect(offer == ScreenLinkOffer(token: "t", code: "ABCDFG", url: URL(string: "https://play.conleychaos.com/tv/t")!, expiresIn: 600_000))
        #expect(offer.renewAfter == .milliseconds(480_000))
    }

    @Test func theAppSaysWhichPlatformItIs() {
        #if os(tvOS)
        #expect(AppIdentity.hostPlatform == "tvos")
        #elseif os(iOS)
        #expect(AppIdentity.hostPlatform == "ios")
        #else
        #expect(AppIdentity.hostPlatform == nil)
        #endif
        #expect(AppIdentity(platform: "tvos", version: "1.2", build: "7").headerValue == "platform=tvos; version=1.2; build=7; protocol=1")
    }
}
