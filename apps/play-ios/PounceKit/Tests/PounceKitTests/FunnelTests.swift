import Foundation
import Synchronization
import Testing
@testable import PounceKit

/// A scripted funnel endpoint: records each report and answers with the next scripted result.
final class FakeFunnelSender: FunnelSending, Sendable {
    let reports = Mutex<[FunnelReport]>([])
    let failures = Mutex<[APIError]>([])

    func sendFunnel(_ report: FunnelReport) async throws {
        reports.withLock { $0.append(report) }
        if let failure = failures.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { throw failure }
    }

    var sent: [FunnelReport] { reports.withLock { $0 } }
}

/// A clock the test moves.
final class TestClock: Sendable {
    let date = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    func advance(_ seconds: TimeInterval) { date.withLock { $0 += seconds } }
    var now: @Sendable () -> Date { { [self] in self.date.withLock { $0 } } }
}

@MainActor @Suite struct FunnelTests {
    let sender = FakeFunnelSender()
    let clock = TestClock()

    private func funnel(file: URL? = nil) -> Funnel {
        Funnel(sender: sender, file: file, now: clock.now, locale: "en-US")
    }

    @Test func nothingGoesOutBeforeTheAgeCheck() async {
        let f = funnel()
        f.came(from: .joinLink)
        f.reach(.linkOpened)
        await f.settle()
        #expect(sender.sent.isEmpty)
        clock.advance(30)
        f.reach(.ageDone)
        f.allow()
        await f.settle()
        #expect(sender.sent == [FunnelReport(reached: ["link_opened": 30, "age_done": 0], source: .joinLink, locale: "en-US")])
    }

    @Test func eachStepGoesOnceWithItsFirstTime() async {
        let f = funnel()
        f.allow()
        f.reach(.ageDone)
        await f.settle()
        clock.advance(10)
        f.reach(.ageDone)
        f.reach(.named)
        await f.settle()
        #expect(sender.sent.map(\.reached) == [["age_done": 0], ["named": 0]])
        #expect(sender.sent.allSatisfy { $0.source == .organic })
    }

    @Test func aStepReachedWhileSendingGoesNext() async {
        let f = funnel()
        f.allow()
        f.reach(.ageDone)
        f.reach(.named)
        f.reach(.homeSeen)
        await f.settle()
        #expect(sender.sent.map(\.reached) == [["age_done": 0], ["named": 0, "home_seen": 0]])
    }

    @Test func aFailedSendIsKeptAndRetriedWithTheOriginalTime() async {
        sender.failures.withLock { $0 = [.transport("offline")] }
        let f = funnel()
        f.allow()
        f.reach(.named)
        f.reach(.homeSeen)
        await f.settle()
        #expect(sender.sent.count == 1)
        clock.advance(120)
        f.flush()
        await f.settle()
        #expect(sender.sent.last?.reached == ["named": 120, "home_seen": 120])
        f.flush()
        await f.settle()
        #expect(sender.sent.count == 2)
    }

    @Test func aRefusedReportIsDroppedNotRetried() async {
        sender.failures.withLock { $0 = [.badRequest] }
        let f = funnel()
        f.allow()
        f.reach(.named)
        await f.settle()
        f.flush()
        await f.settle()
        #expect(sender.sent.count == 1)
    }

    @Test func theSourceIsOrganicUntilAnInviteAndKeptOnceATableOpens() async {
        let f = funnel()
        #expect(f.source == .organic)
        f.came(from: .paste)
        #expect(f.source == .paste)
        f.tableOpened()
        f.came(from: .joinLink)
        #expect(f.source == .paste)

        let plain = Funnel(sender: sender, file: nil, now: clock.now, locale: nil)
        plain.tableOpened()
        plain.came(from: .pounceLink)
        #expect(plain.source == .organic)
        #expect(plain.saved.source == .organic)
    }

    @Test func theAppsOneLineCalls() async {
        let f = funnel()
        f.opened(.move(code: "ABCDE", moveCode: "123456"))
        #expect(f.saved.reached.isEmpty)
        f.pasted()
        f.opened(.join(code: "ABCDE"))
        f.answeredPush(allowed: false)
        #expect(f.source == .paste)
        #expect(Set(f.saved.reached.keys) == ["invite_pasted", "link_opened", "push_answered"])
        f.answeredPush(allowed: true)
        f.ageChecked()
        await f.settle()
        #expect(Set(sender.sent.flatMap(\.reached.keys)) == ["invite_pasted", "link_opened", "push_answered", "push_allowed", "age_done"])

        let linked = funnel()
        linked.opened(.pounce(token: "AAAAAAAAAAAAAAAAAAAAAA"))
        #expect(linked.source == .pounceLink)
    }

    @Test func itAllSurvivesARelaunch() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("funnel-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        sender.failures.withLock { $0 = [.transport("offline")] }
        let first = funnel(file: file)
        first.came(from: .joinLink)
        first.reach(.linkOpened)
        first.allow()
        await first.settle()
        clock.advance(60)
        let second = funnel(file: file)
        #expect(second.saved == first.saved)
        second.flush()
        await second.settle()
        #expect(sender.sent.last == FunnelReport(reached: ["link_opened": 60], source: .joinLink, locale: "en-US"))
        // Allowing again changes nothing.
        second.allow()
        await second.settle()
        #expect(sender.sent.count == 2)
    }

    @Test func theLocaleIsALanguageAndARegionOnly() {
        #expect(Funnel.locale(Locale(identifier: "en_US")) == "en-US")
        #expect(Funnel.locale(Locale(identifier: "pt-BR")) == "pt-BR")
        #expect(Funnel.locale(Locale(identifier: "fr")) == "fr")
        #expect(Funnel.locale(Locale(identifier: "es_419")) == "es")
        #expect(Funnel.locale(Locale(identifier: "")) == nil)
    }

    /// The app's steps are the server's `APP_MILESTONES`, spelled the same.
    @Test func theStepsAreTheServers() throws {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { dir.deleteLastPathComponent() }
        let source = try String(
            contentsOf: dir.appendingPathComponent("play-api/src/funnel/milestones.ts"), encoding: .utf8)
        let block = try #require(source.range(of: "APP_MILESTONES = [").map { source[$0.upperBound...] })
        let list = block[..<(try #require(block.range(of: "] as const")).lowerBound)]
        let names = list.split(separator: "\n").compactMap { line -> String? in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("\""), let end = t.dropFirst().firstIndex(of: "\"") else { return nil }
            return String(t[t.index(after: t.startIndex)..<end])
        }
        #expect(names == FunnelMilestone.allCases.map(\.rawValue))
        let sources = try #require(source.range(of: "SOURCES = [").map { source[$0.upperBound...] })
        #expect(sources.hasPrefix(#""organic", "join_link", "pounce_link", "paste"]"#))
    }
}

@Suite struct FunnelAPITests {
    @Test func theReportGoesToTheFunnelRoute() async throws {
        let server = StubServer { req in
            req.path == "/v1/devices" ? Reply(200, #"{"deviceId":"dev1","token":"tok1"}"#) : Reply(204, "")
        }
        let api = APIClient(config: server.config(), credentials: MemoryCredentialStore(), session: server.session())
        try await api.sendFunnel(FunnelReport(reached: ["named": 3], source: .organic, locale: nil))
        let post = try #require(server.seen.last)
        #expect(post.method == "POST" && post.path == "/v1/funnel")
        let body = try #require(try JSONSerialization.jsonObject(with: post.body) as? [String: Any])
        #expect(body["reached"] as? [String: Int] == ["named": 3])
        #expect(body["source"] as? String == "organic")
        #expect(body["locale"] == nil)
    }
}
