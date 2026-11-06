import Foundation
import Synchronization
import Testing
@testable import PounceKit

/// Parent consent (consent design §2; plan decisions 22, 33–38), against play-api's
/// `/v1/kittens` routes (`apps/play-api/tests/consent.test.ts`).
@Suite struct KittenWireTests {
    @Test func decodesTheServersShapes() throws {
        let me = try JSONDecoder().decode(
            KittenStatus.self, from: Data(#"{"state":"consented","linked":true,"approved":["pr_a"]}"#.utf8))
        #expect(me == KittenStatus(state: .consented, linked: true, approved: ["pr_a"]))
        let list = try JSONDecoder().decode(ParentKitten.self, from: Data(#"""
            {"id":"k_x","name":"Mochi","cat":4,"state":"code","confirmed":false,"mode":"apple",
             "people":[{"pair":"pr_a","name":"Mia","cat":2,"approved":true,"parent":false}]}
            """#.utf8))
        #expect(list.state == .code)
        #expect(!list.confirmed)
        let on = try JSONDecoder().decode(ParentKitten.self, from: Data(#"""
            {"id":"k_x","name":"Mochi","cat":4,"state":"on","confirmed":true,"mode":"parent","people":[]}
            """#.utf8))
        #expect(on.state == .on && on.confirmed)
        // An older server without `confirmed`: not confirmed.
        let older = try JSONDecoder().decode(ParentKitten.self, from: Data(#"""
            {"id":"k_x","name":"Mochi","cat":4,"state":"on","mode":"parent","people":[]}
            """#.utf8))
        #expect(!older.confirmed)
        let waiting = try JSONDecoder().decode(KittenStatus.self, from: Data(#"{"state":"code","linked":true,"approved":[]}"#.utf8))
        #expect(waiting.state == .code)
        #expect(list.mode == .apple)
        #expect(list.people.first?.name == "Mia")
        let code = try JSONDecoder().decode(LinkCode.self, from: Data(#"{"code":"012345","expiresAt":1800000000000}"#.utf8))
        #expect(code.code == "012345")
        #expect(code.fresh(at: Date(timeIntervalSince1970: 1_799_999_999)))
        #expect(!code.fresh(at: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    @Test func padlocksOnlyOnceLinked() {
        #expect(!KittenStatus.unlinked.locks(pair: "pr_a"))
        let linked = KittenStatus(state: .pending, linked: true, approved: ["pr_a"])
        #expect(!linked.locks(pair: "pr_a"))
        #expect(linked.locks(pair: "pr_b"))
    }

    @Test func togglesKeepParentsAndApplesListAlone() {
        let k = ParentKitten(id: "k", name: "Mochi", cat: 4, state: .on, mode: .parent, people: [
            KittenPerson(pair: "pr_mom", name: "Mom", cat: 1, approved: true, parent: true),
            KittenPerson(pair: "pr_mia", name: "Mia", cat: 2, approved: false, parent: false),
            KittenPerson(pair: "pr_leo", name: "Leo", cat: 3, approved: true, parent: false),
        ])
        #expect(k.approvals(toggling: "pr_mia") == ["pr_mia", "pr_leo"])
        #expect(k.approvals(toggling: "pr_leo") == [])
        #expect(k.approvals(toggling: "pr_mom") == nil)
        #expect(k.approvals(toggling: "pr_nobody") == nil)
        var apple = k
        apple.mode = .apple
        #expect(apple.approvals(toggling: "pr_mia") == nil)
    }
}

@Suite struct KittenBellTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var fresh: LinkCode { LinkCode(code: "482913", expiresAt: (now.timeIntervalSince1970 + 300) * 1000) }
    private var stale: LinkCode { LinkCode(code: "482913", expiresAt: (now.timeIntervalSince1970 - 1) * 1000) }

    @Test func lockedShowsAFreshCodeOnly() {
        #expect(KittenBell.of(status: nil, held: false, code: fresh, now: now) == .locked(code: "482913"))
        #expect(KittenBell.of(status: .unlinked, held: false, code: stale, now: now) == .locked(code: nil))
        #expect(KittenBell.of(status: .unlinked, held: false, code: nil, now: now) == .locked(code: nil))
    }

    @Test func heldBeatsEverythingButConsent() {
        #expect(KittenBell.of(status: .unlinked, held: true, code: fresh, now: now) == .held)
        let pending = KittenStatus(state: .pending, linked: true, approved: [])
        #expect(KittenBell.of(status: pending, held: true, code: nil, now: now) == .held)
        let on = KittenStatus(state: .consented, linked: true, approved: [])
        #expect(KittenBell.of(status: on, held: true, code: nil, now: now) == .on)
    }

    @Test func linkedSleepsUntilConsent() {
        for state in [KittenStatus.State.pending, .code] {
            #expect(KittenBell.of(status: KittenStatus(state: state, linked: true, approved: []), held: false, code: fresh, now: now) == .asleep)
        }
        #expect(KittenBell.of(status: KittenStatus(state: .consented, linked: true, approved: []), held: false, code: nil, now: now) == .on)
    }
}

@Suite struct KittenEntryTests {
    @Test func linkCodeTakesSixDigits() {
        var e = LinkCodeEntry()
        for d in [4, 8, 2, 9, 1, 3, 7, 12, -1] { e.type(d) }
        #expect(e.digits == "482913")
        #expect(e.complete)
        e.delete()
        #expect(e.digits == "48291")
        #expect(!e.complete)
        e.clear()
        e.delete()
        #expect(e.digits == "")
    }

    @Test func phoneKeepsDigitsAndPunctuation() {
        #expect(PhoneEntry.clean("(555) 123-4567") == "(555) 123-4567")
        #expect(PhoneEntry.clean("+1 555.123.4567x99") == "+1 555.123.456799")
        #expect(PhoneEntry.clean("5+5") == "55")
        #expect(PhoneEntry.clean("abc٣") == "")
        #expect(PhoneEntry.clean(String(repeating: "1", count: 40)).count == PhoneEntry.maxLength)
    }

    @Test func plausiblePhones() {
        #expect(PhoneEntry.plausible("(555) 123-4567"))
        #expect(PhoneEntry.plausible("1 555 123 4567"))
        #expect(PhoneEntry.plausible("+44 20 7946 0958"))
        #expect(!PhoneEntry.plausible("2 555 123 4567"))
        #expect(!PhoneEntry.plausible("12345"))
        #expect(!PhoneEntry.plausible("+12"))
    }
}

/// The parent's code entry (Twilio Verify, consent design D6): the number, then six numerals.
@Suite struct ConsentCodeStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func startsWhereTheKittenIs() {
        #expect(ConsentCodeState(state: .pending).phase == .phone)
        #expect(ConsentCodeState(state: .code).phase == .code)
        #expect(ConsentCodeState(state: .on).phase == .done)
    }

    @Test func aSentCodeOpensTheKeypadAndAResendWaits30Seconds() {
        var s = ConsentCodeState(state: .pending)
        #expect(!s.canResend(now: now), "nothing to resend before a number")
        s.sent(at: now)
        #expect(s.phase == .code)
        #expect(!s.canResend(now: now.addingTimeInterval(29)))
        #expect(s.canResend(now: now.addingTimeInterval(30)))
        // Opened later, in the code state, with no send time: the server decides.
        #expect(ConsentCodeState(state: .code).canResend(now: now))
    }

    @Test func checkResultsMoveTheState() {
        var s = ConsentCodeState(state: .code)
        for d in [1, 2, 3, 4, 5, 6] { s.entry.type(d) }
        s.checked(.wrong, at: now)
        #expect(s.entry.digits.isEmpty)
        #expect(s.phase == .code && !s.expired && !s.resting(now: now))
        s.checked(.expired, at: now)
        #expect(s.expired)
        s.resent(.sent, at: now)
        #expect(!s.expired)
        #expect(s.sentAt == now)
        s.checked(.failed, at: now)
        #expect(s.phase == .code)
        s.checked(.notWaiting, at: now)
        #expect(s.phase == .phone)
        s.sent(at: now)
        s.checked(.on, at: now)
        #expect(s.phase == .done)
    }

    /// Five wrong codes rest the keypad for the server's 10 minutes, no longer (review I2).
    @Test func tooManyWrongCodesRestTheKeypadFor10Minutes() {
        var s = ConsentCodeState(state: .code)
        s.checked(.tooMany, at: now)
        #expect(s.resting(now: now))
        #expect(s.resting(now: now.addingTimeInterval(599)))
        #expect(!s.resting(now: now.addingTimeInterval(600)))
    }

    /// A refused resend (too soon, or the day's codes used up) only dims the loop arrow: a parent
    /// holding a good code can still type it (review I2).
    @Test func aRefusedResendLeavesTheKeypadAlone() {
        var s = ConsentCodeState(state: .code)
        #expect(s.canResend(now: now))
        s.resent(.tooMany, at: now)
        #expect(!s.resting(now: now))
        #expect(!s.canResend(now: now.addingTimeInterval(29)))
        #expect(s.canResend(now: now.addingTimeInterval(30)))
        s.resent(.failed, at: now)
        #expect(!s.resting(now: now))
    }

    @Test func aNewNumberGoesBackToThePhone() {
        var s = ConsentCodeState(state: .code)
        s.entry.type(4)
        s.checked(.expired, at: now)
        s.checked(.tooMany, at: now)
        s.changeNumber()
        #expect(s.phase == .phone)
        #expect(s.entry.digits.isEmpty)
        #expect(!s.expired && !s.resting(now: now))
    }
}

@Suite struct KittenApprovalsTests {
    @Test func asksNewPartnersOnceAndMirrorsTheKnownSet() {
        let first = KittenApprovals.plan(limits: true, partners: ["pr_b", "pr_a", "pr_c"], known: ["pr_a"], asked: [], last: nil)
        #expect(first.ask == ["pr_b", "pr_c"])
        #expect(first.send == .init(apple: ["pr_a"]))
        let again = KittenApprovals.plan(limits: true, partners: ["pr_b", "pr_a", "pr_c"], known: ["pr_a"], asked: ["pr_b", "pr_c"], last: first.send)
        #expect(again == .init(ask: [], send: nil))
        let approved = KittenApprovals.plan(limits: true, partners: ["pr_b", "pr_a"], known: ["pr_b", "pr_a", "pr_x"], asked: ["pr_b"], last: first.send)
        #expect(approved.send == .init(apple: ["pr_a", "pr_b"]))
    }

    @Test func withoutLimitsSendsNullOnceAndAsksNobody() {
        #expect(KittenApprovals.plan(limits: false, partners: ["pr_a"], known: [], asked: [], last: nil) == .init(ask: [], send: nil))
        let off = KittenApprovals.plan(limits: false, partners: ["pr_a"], known: [], asked: [], last: .init(apple: ["pr_a"]))
        #expect(off.send == .init(apple: nil))
        #expect(KittenApprovals.plan(limits: false, partners: [], known: [], asked: [], last: .init(apple: nil)).send == nil)
    }

    @Test func theMirrorEncodesNullExplicitly() throws {
        let off = String(decoding: try JSONEncoder().encode(KittenApprovals.Mirror(apple: nil)), as: UTF8.self)
        #expect(off == #"{"apple":null}"#)
        let on = String(decoding: try JSONEncoder().encode(KittenApprovals.Mirror(apple: ["pr_a"])), as: UTF8.self)
        #expect(on == #"{"apple":["pr_a"]}"#)
    }
}

@Suite struct KittenPushPolicyTests {
    @Test func aKittenRegistersOnlyWithConsent() {
        #expect(!PushPolicy.registersRemote(band: .kitten, kittenConsented: false))
        #expect(PushPolicy.registersRemote(band: .kitten, kittenConsented: true))
        #expect(PushPolicy.registersRemote(band: .adult, kittenConsented: false))
        #expect(PushPolicy.registersRemote(band: .teen, kittenConsented: false))
        // Unknown counts as a kitten without consent, whatever the cache says.
        #expect(!PushPolicy.registersRemote(band: nil, kittenConsented: true))
    }

    @Test func consentDoesntCoverTheWidgetToken() {
        #expect(!WidgetPushToken.uploads(band: .kitten))
    }
}

/// A recording fake of the server.
final class FakeKittens: KittenService, Sendable {
    let calls = Mutex<[String]>([])
    let status = Mutex(KittenStatus.unlinked)
    let fail = Mutex<APIError?>(nil)
    let list = Mutex<[ParentKitten]>(DemoKittenService.parentKittens())

    private func record(_ s: String) throws {
        calls.withLock { $0.append(s) }
        if let e = fail.withLock({ $0 }) { throw e }
    }

    func kittenStatus(person: String) async throws -> KittenStatus {
        try record("status \(person)")
        return status.withLock { $0 }
    }

    func linkCode(person: String, appTransactionId: String?) async throws -> LinkCode {
        try record("code \(appTransactionId ?? "-")")
        return LinkCode(code: "000111", expiresAt: (Date.now.timeIntervalSince1970 + 600) * 1000)
    }

    func mirrorApple(person: String, mirror: KittenApprovals.Mirror) async throws {
        try record("mirror \(mirror.apple?.joined(separator: ",") ?? "null")")
    }

    func kittens() async throws -> [ParentKitten] {
        try record("list")
        return list.withLock { $0 }
    }

    func link(code: String) async throws -> ParentKitten {
        try record("link \(code)")
        return ParentKitten(id: "k_new", name: "Pickle", cat: 3, state: .pending, mode: .parent, people: [])
    }

    func setApproved(kitten: String, pairs: [String]) async throws { try record("approve \(kitten) \(pairs.joined(separator: ","))") }
    func startConsent(kitten: String, phone: String) async throws { try record("text \(kitten) \(phone)") }
    func resendConsent(kitten: String) async throws { try record("resend \(kitten)") }
    func checkConsent(kitten: String, code: String) async throws { try record("check \(kitten) \(code)") }
    func revokeConsent(kitten: String) async throws { try record("revoke \(kitten)") }
    func unlink(kitten: String) async throws { try record("unlink \(kitten)") }
}

@MainActor @Suite struct KittenRevokeQueueTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kitten-\(UUID().uuidString).json")
    }

    /// A revoke (the panel's, or the notification's in the background) is kept on disk until the
    /// server has it, and tried again on the next launch or foreground (review I1).
    @Test func aFailedRevokeIsKeptAndTriedAgain() async {
        let fake = FakeKittens()
        let url = file()
        let store = KittenStore(service: fake, file: url)
        await store.refreshKittens()
        fake.fail.withLock { $0 = .transport("offline") }
        #expect(await store.revoke(kitten: DemoKittenService.biscuit) == false)
        #expect(store.pendingRevokes == [DemoKittenService.biscuit])
        #expect(store.kittens[1].state == .on)
        let next = KittenStore(service: fake, file: url)
        #expect(next.pendingRevokes == [DemoKittenService.biscuit])
        await next.drainRevokes()
        #expect(next.pendingRevokes == [DemoKittenService.biscuit], "still offline")
        fake.fail.withLock { $0 = nil }
        await next.drainRevokes()
        #expect(next.pendingRevokes.isEmpty)
        #expect(KittenStore(service: fake, file: url).pendingRevokes.isEmpty)
        #expect(fake.calls.withLock { $0 }.filter { $0.hasPrefix("revoke") }.count == 3)
    }

    @Test func aKittenTheServerNoLongerKnowsLeavesTheQueue() async {
        let fake = FakeKittens()
        let store = KittenStore(service: fake, file: nil)
        fake.fail.withLock { $0 = .notFound }
        #expect(await store.revoke(kitten: "k_gone") == true)
        #expect(store.pendingRevokes.isEmpty)
    }
}

@MainActor @Suite struct KittenStoreTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kitten-\(UUID().uuidString).json")
    }

    @Test func remembersConsentAcrossLaunches() async {
        let fake = FakeKittens()
        let url = file()
        let store = KittenStore(service: fake, file: url)
        #expect(!store.consented)
        store.person = "me"
        fake.status.withLock { $0 = KittenStatus(state: .consented, linked: true, approved: []) }
        await store.refreshStatus()
        #expect(store.consented)
        store.noteRegistered(true)
        let next = KittenStore(service: fake, file: url)
        #expect(next.consented)
        #expect(next.registeredAsKitten)
        fake.status.withLock { $0 = KittenStatus(state: .pending, linked: true, approved: []) }
        next.person = "me"
        await next.refreshStatus()
        #expect(!next.consented)
        #expect(!KittenStore(service: fake, file: url).consented)
    }

    @Test func offlineKeepsWhatItKnew() async {
        let fake = FakeKittens()
        let store = KittenStore(service: fake, file: nil)
        await store.refreshStatus()
        #expect(fake.calls.withLock { $0 }.isEmpty, "no person, no call")
        store.person = "me"
        fake.fail.withLock { $0 = .transport("offline") }
        await store.refreshStatus()
        #expect(store.status == nil)
        #expect(!store.locks(pair: "pr_a"))
    }

    @Test func aCodeIsReusedWhileFresh() async {
        let fake = FakeKittens()
        let store = KittenStore(service: fake, file: nil)
        store.person = "me"
        await store.requestCode(appTransactionId: "tx1")
        await store.requestCode(appTransactionId: "tx1")
        #expect(store.code?.code == "000111")
        #expect(fake.calls.withLock { $0 } == ["code tx1"])
        await store.requestCode(appTransactionId: nil, now: .now.addingTimeInterval(590))
        #expect(fake.calls.withLock { $0 }.count == 2)
    }

    @Test func mirrorsOnceAndRemembersWhoWasAsked() async {
        let fake = FakeKittens()
        let url = file()
        let store = KittenStore(service: fake, file: url)
        store.person = "me"
        let ask = await store.mirror(limits: true, partners: ["pr_a", "pr_b"], known: ["pr_a"])
        #expect(ask == ["pr_b"])
        store.noteAsked(ask)
        #expect(await store.mirror(limits: true, partners: ["pr_a", "pr_b"], known: ["pr_a"]) == [])
        #expect(fake.calls.withLock { $0 }.filter { $0.hasPrefix("mirror") } == ["mirror pr_a"])
        // The kitten taps a padlocked person: asked again.
        let reopened = KittenStore(service: fake, file: url)
        reopened.person = "me"
        reopened.forgetAsked("pr_b")
        #expect(await reopened.mirror(limits: true, partners: ["pr_a", "pr_b"], known: ["pr_a"]) == ["pr_b"])
        // Limits off: null, once.
        _ = await reopened.mirror(limits: false, partners: ["pr_a"], known: [])
        _ = await reopened.mirror(limits: false, partners: ["pr_a"], known: [])
        #expect(fake.calls.withLock { $0 }.filter { $0.hasPrefix("mirror") } == ["mirror pr_a", "mirror null"])
    }

    @Test func aFailedMirrorIsTriedAgain() async {
        let fake = FakeKittens()
        let store = KittenStore(service: fake, file: nil)
        store.person = "me"
        fake.fail.withLock { $0 = .server(500) }
        _ = await store.mirror(limits: true, partners: ["pr_a"], known: ["pr_a"])
        fake.fail.withLock { $0 = nil }
        _ = await store.mirror(limits: true, partners: ["pr_a"], known: ["pr_a"])
        #expect(fake.calls.withLock { $0 }.filter { $0.hasPrefix("mirror") }.count == 2)
    }

    @Test func parentFlows() async {
        let fake = FakeKittens()
        let store = KittenStore(service: fake, file: nil)
        await store.refreshKittens()
        #expect(store.kittensLoaded)
        #expect(store.kittens.map(\.name) == ["Mochi", "Biscuit"])
        #expect(await store.link(code: "123456") == .linked(ParentKitten(id: "k_new", name: "Pickle", cat: 3, state: .pending, mode: .parent, people: [])))
        #expect(store.kittens.count == 3)
        await store.toggle(kitten: DemoKittenService.mochi, pair: "pr_demoKikiAAAAAAAAAAAAAA")
        #expect(store.kittens[0].people[2].approved)
        #expect(fake.calls.withLock { $0 }.last == "approve \(DemoKittenService.mochi) pr_demoMiaAAAAAAAAAAAAAAA,pr_demoKikiAAAAAAAAAAAAAA")
        // Apple mode: nothing to send.
        let before = fake.calls.withLock { $0 }.count
        await store.toggle(kitten: DemoKittenService.biscuit, pair: "pr_demoLeoAAAAAAAAAAAAAAA")
        #expect(fake.calls.withLock { $0 }.count == before)
        #expect(await store.sendPhone(kitten: DemoKittenService.mochi, phone: "555 123 4567") == .sent)
        #expect(store.kittens[0].state == .code)
        #expect(await store.resend(kitten: DemoKittenService.mochi) == .sent)
        #expect(await store.check(kitten: DemoKittenService.mochi, code: "135790") == .on)
        #expect(store.kittens[0].state == .on)
        #expect(!store.kittens[0].confirmed)
        #expect(fake.calls.withLock { $0 }.suffix(3) == [
            "text \(DemoKittenService.mochi) 555 123 4567", "resend \(DemoKittenService.mochi)", "check \(DemoKittenService.mochi) 135790",
        ])
        await store.revoke(kitten: DemoKittenService.biscuit)
        #expect(store.kittens[1].state == .pending)
        await store.unlink(kitten: "k_new")
        #expect(store.kittens.count == 2)
    }

    @Test func parentFailures() async {
        let fake = FakeKittens()
        let store = KittenStore(service: fake, file: nil)
        await store.refreshKittens()
        fake.fail.withLock { $0 = .notFound }
        #expect(await store.link(code: "000000") == .wrong)
        fake.fail.withLock { $0 = .rateLimited }
        #expect(await store.link(code: "000000") == .tooMany)
        fake.fail.withLock { $0 = .server(500) }
        #expect(await store.link(code: "000000") == .failed)
        // A refused toggle goes back.
        await store.toggle(kitten: DemoKittenService.mochi, pair: "pr_demoKikiAAAAAAAAAAAAAA")
        #expect(!store.kittens[0].people[2].approved)
        fake.fail.withLock { $0 = .notConfigured }
        #expect(await store.sendPhone(kitten: DemoKittenService.mochi, phone: "555 123 4567") == .notConfigured)
        #expect(store.kittens[0].state == .pending)
        fake.fail.withLock { $0 = .server(502) }
        #expect(await store.sendPhone(kitten: DemoKittenService.mochi, phone: "555 123 4567") == .failed)
        fake.fail.withLock { $0 = .rateLimited }
        #expect(await store.sendPhone(kitten: DemoKittenService.mochi, phone: "555 123 4567") == .tooMany)
        #expect(await store.resend(kitten: DemoKittenService.mochi) == .tooMany)
        fake.fail.withLock { $0 = .notConfigured }
        #expect(await store.resend(kitten: DemoKittenService.mochi) == .notConfigured)
        fake.fail.withLock { $0 = .transport("offline") }
        #expect(await store.resend(kitten: DemoKittenService.mochi) == .failed)
        // The code: wrong, expired, too many tries, not waiting any more, or the server failing.
        let outcomes: [(APIError, KittenStore.CheckResult)] = [
            (.server(422), .wrong), (.server(410), .expired), (.rateLimited, .tooMany), (.conflict("not_waiting"), .notWaiting),
            (.notConfigured, .failed), (.server(502), .failed), (.transport("offline"), .failed),
        ]
        for (error, result) in outcomes {
            fake.fail.withLock { $0 = error }
            #expect(await store.check(kitten: DemoKittenService.mochi, code: "000000") == result, "\(error)")
        }
        #expect(store.kittens[0].state == .pending)
        await store.revoke(kitten: DemoKittenService.biscuit)
        #expect(store.kittens[1].state == .on)
        await store.unlink(kitten: DemoKittenService.biscuit)
        #expect(store.kittens.count == 2)
    }
}

/// The routes, through `APIClient`.
@Suite struct KittenAPITests {
    private static let minted = #"{"deviceId":"dev1","token":"tok1"}"#

    private func client(_ reply: @escaping @Sendable (Seen) -> Reply) -> (APIClient, StubServer) {
        let server = StubServer { req in req.path == "/v1/devices" ? Reply(200, Self.minted) : reply(req) }
        return (APIClient(config: server.config(), credentials: MemoryCredentialStore(), session: server.session()), server)
    }

    @Test func eachCallHitsItsRoute() async throws {
        let (api, server) = client { req in
            switch req.path {
            case "/v1/kittens/me": return Reply(200, #"{"state":"pending","linked":true,"approved":[]}"#)
            case "/v1/kittens/me/link-code": return Reply(201, #"{"code":"123456","expiresAt":1}"#)
            case "/v1/kittens": return Reply(200, #"{"kittens":[]}"#)
            case "/v1/kittens/link":
                return Reply(201, #"{"kitten":{"id":"k_x","name":"M","cat":1,"state":"pending","mode":"parent","people":[]}}"#)
            default: return Reply(204, "")
            }
        }
        _ = try await api.kittenStatus(person: "p1")
        _ = try await api.linkCode(person: "p1", appTransactionId: "704")
        try await api.mirrorApple(person: "p1", mirror: .init(apple: nil))
        _ = try await api.kittens()
        _ = try await api.link(code: "123456")
        try await api.setApproved(kitten: "k_x", pairs: ["pr_a"])
        try await api.startConsent(kitten: "k_x", phone: "555")
        try await api.resendConsent(kitten: "k_x")
        try await api.checkConsent(kitten: "k_x", code: "012345")
        try await api.revokeConsent(kitten: "k_x")
        try await api.unlink(kitten: "k_x")
        let calls = server.seen.filter { $0.path != "/v1/devices" }
        #expect(calls.map { "\($0.method) \($0.path)" } == [
            "GET /v1/kittens/me", "POST /v1/kittens/me/link-code", "PUT /v1/kittens/me/approved", "GET /v1/kittens",
            "POST /v1/kittens/link", "PUT /v1/kittens/k_x/approved", "POST /v1/kittens/k_x/consent",
            "POST /v1/kittens/k_x/consent/resend", "POST /v1/kittens/k_x/consent/check",
            "DELETE /v1/kittens/k_x/consent", "DELETE /v1/kittens/k_x",
        ])
        #expect(String(decoding: calls[8].body, as: UTF8.self) == #"{"code":"012345"}"#)
        #expect(calls.prefix(3).allSatisfy { $0.query == "person=p1" })
        #expect(String(decoding: calls[1].body, as: UTF8.self) == #"{"appTransactionId":"704"}"#)
        #expect(String(decoding: calls[2].body, as: UTF8.self) == #"{"apple":null}"#)
    }

    @Test func noTextProviderIsNotConfigured() async throws {
        let (api, _) = client { _ in Reply(503, #"{"error":"not_configured"}"#) }
        await #expect(throws: APIError.notConfigured) { try await api.startConsent(kitten: "k_x", phone: "555") }
    }
}
