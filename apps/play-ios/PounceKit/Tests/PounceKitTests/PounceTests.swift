import Foundation
import Synchronization
import Testing
@testable import PounceKit

/// Pounce (spec §12.4) against play-api PR 5's routes (`src/pounce/*`, `tests/pounce.test.ts`).
@Suite struct PounceWireTests {
    private func view(_ pounce: String?) throws -> StreakView {
        let extra = pounce.map { #","pounce":\#($0)"# } ?? ""
        let json = #"{"pair":"pr_x","partner":{"name":"Mia","cat":2},"count":5\#(extra)}"#
        return try JSONDecoder().decode(StreakView.self, from: Data(json.utf8))
    }

    @Test func theStubAndAMissingPounceDecode() throws {
        #expect(try view(nil).pounce == .none)
        #expect(try view(#"{"sent":false,"resting":true}"#).pounce == PounceState(resting: true))
    }

    @Test func theFullViewDecodes() throws {
        let p = try view(#"{"sent":true,"resting":false,"quiet":true,"answer":"later","code":null,"waiting":{"id":"pc_1","target":{"table":"GH2VD"}}}"#).pounce
        #expect(p.sent && p.quiet && !p.resting)
        #expect(p.answer == .later)
        #expect(p.code == nil)
        #expect(p.waiting == .init(id: "pc_1", target: .table("GH2VD")))
        #expect(try view(#"{"sent":false,"resting":false,"waiting":{"id":"pc_2","target":"pick"}}"#).pounce.waiting?.target == .pick)
    }

    @Test func theStreakFixtureStillDecodes() throws {
        let streak = try #require(try Fixtures.streakServerMessages().first { $0.name == "streak" })
        guard case .streak(_, _, let v) = try Codec.decode(streak.json) else {
            Issue.record("not a streak message")
            return
        }
        #expect(v.pounce == .none)
    }
}

@Suite struct PounceAPITests {
    private static let minted = #"{"deviceId":"dev1","token":"tok1"}"#
    private let me = "6f1c0e0e-0000-4000-8000-000000000001"
    private let pair = "pr_AAAAAAAAAAAAAAAAAAAAAA"

    private func client(_ reply: @escaping @Sendable (Seen) -> Reply) -> (APIClient, StubServer) {
        let server = StubServer { req in req.path == "/v1/devices" ? Reply(200, Self.minted) : reply(req) }
        return (APIClient(config: server.config(), credentials: MemoryCredentialStore(), session: server.session()), server)
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func sendToAPair() async throws {
        let (api, server) = client { _ in Reply(201, #"{"id":"pc_1"}"#) }
        let sent = try await api.send(to: pair, target: .table("GH2VD"), person: me)
        #expect(sent == PounceSent(id: "pc_1", link: nil))
        let post = try #require(server.seen.last)
        #expect(post.method == "POST" && post.path == "/v1/pounces" && post.query == "person=\(me)")
        let body = try json(post.body)
        #expect(body["to"] as? String == pair)
        #expect((body["target"] as? [String: Any])?["table"] as? String == "GH2VD")
    }

    @Test func aLinkHasNoToAndComesBackWithItsURL() async throws {
        let (api, server) = client { _ in Reply(201, #"{"id":"pc_1","link":"https://play.conleychaos.com/p/AAAAAAAAAAAAAAAAAAAAAA"}"#) }
        let sent = try await api.send(to: nil, target: .new, person: me)
        #expect(sent.link?.absoluteString == "https://play.conleychaos.com/p/AAAAAAAAAAAAAAAAAAAAAA")
        let body = try json(try #require(server.seen.last).body)
        #expect(body["to"] == nil)
        #expect(body["target"] as? String == "new")
    }

    @Test func restingIsRateLimited() async throws {
        let (api, _) = client { _ in Reply(429, #"{"error":"resting","until":1}"#) }
        await #expect(throws: APIError.rateLimited) { _ = try await api.send(to: pair, target: .new, person: me) }
    }

    @Test func answerSendsItsBodyAndReadsTheCode() async throws {
        let (api, server) = client { _ in Reply(200, #"{"code":"NWCDF"}"#) }
        let code = try await api.answer(id: "pc_1", answer: .play, choice: "new", link: "AAAAAAAAAAAAAAAAAAAAAA", person: me)
        #expect(code == "NWCDF")
        let post = try #require(server.seen.last)
        #expect(post.path == "/v1/pounces/pc_1/answer" && post.method == "POST")
        let body = try json(post.body)
        #expect(body["answer"] as? String == "play")
        #expect(body["choice"] as? String == "new")
        #expect(body["link"] as? String == "AAAAAAAAAAAAAAAAAAAAAA")
    }

    @Test func aPlainAnswerHasOnlyTheAnswer() async throws {
        let (api, server) = client { _ in Reply(200, "{}") }
        let code = try await api.answer(id: "pc_1", answer: .later, choice: nil, link: nil, person: me)
        #expect(code == nil)
        #expect(try json(try #require(server.seen.last).body).keys.sorted() == ["answer"])
    }

    @Test func theLinkPreview() async throws {
        let (api, server) = client { _ in Reply(200, #"{"id":"pc_1","from":{"name":"Mia","cat":2},"target":"pick"}"#) }
        let link = try await api.linkPounce(token: "AAAAAAAAAAAAAAAAAAAAAA")
        #expect(link == LinkPounce(id: "pc_1", from: PushFace(name: "Mia", cat: 2), target: .pick))
        #expect(server.seen.last?.path == "/v1/pounces/links/AAAAAAAAAAAAAAAAAAAAAA")
        #expect(server.seen.last?.method == "GET")
    }
}

/// A scripted `PounceService`.
final class FakePounces: PounceService, Sendable {
    let calls = Mutex<[String]>([])
    let answerResult: Mutex<Result<String?, APIError>>
    let sendResult: Mutex<Result<PounceSent, APIError>>

    init(answer: Result<String?, APIError> = .success(nil), send: Result<PounceSent, APIError> = .success(PounceSent(id: "pc_1", link: nil))) {
        answerResult = Mutex(answer)
        sendResult = Mutex(send)
    }

    func send(to pair: String?, target: PounceTarget, person: String?) async throws -> PounceSent {
        calls.withLock { $0.append("send \(pair ?? "link") \(target)") }
        try await Task.sleep(for: .milliseconds(20))
        return try sendResult.withLock { $0 }.get()
    }

    func answer(id: String, answer: PounceAnswer, choice: String?, link: String?, person: String?) async throws -> String? {
        calls.withLock { $0.append("answer \(id) \(answer.rawValue)") }
        try await Task.sleep(for: .milliseconds(20))
        return try answerResult.withLock { $0 }.get()
    }

    func linkPounce(token: String) async throws -> LinkPounce {
        calls.withLock { $0.append("link \(token)") }
        return LinkPounce(id: "pc_9", from: PushFace(name: "Mia", cat: 2), target: .new)
    }
}

@MainActor @Suite struct PounceStoreTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pounce-\(UUID().uuidString).json")
    }

    private func pending(_ answer: PounceAnswer, id: String = "pc_1") -> PendingAnswer {
        PendingAnswer(id: id, answer: answer, choice: nil, link: nil, person: "me")
    }

    @Test func anAnswerGoesOutAndIsDone() async {
        let fake = FakePounces(answer: .success("GH2VD"))
        let store = PounceStore(service: fake, file: file())
        #expect(await store.answer(pending(.play)) == .done(code: "GH2VD"))
        #expect(store.pending.isEmpty)
    }

    @Test func testFailedAnswerRetriesOnce() async {
        let url = file()
        let offline = FakePounces(answer: .failure(.transport("offline")))
        let first = PounceStore(service: offline, file: url)
        #expect(await first.answer(pending(.later)) == .queued)
        #expect(first.pending == [pending(.later)])
        // Next launch: a new store on the same file sends it once.
        let online = FakePounces(answer: .success(nil))
        let next = PounceStore(service: online, file: url)
        #expect(next.pending == [pending(.later)])
        await next.retryPending()
        await next.retryPending()
        #expect(next.pending.isEmpty)
        #expect(online.calls.withLock { $0 } == ["answer pc_1 later"])
    }

    @Test func aRefusedAnswerIsDropped() async {
        let store = PounceStore(service: FakePounces(answer: .failure(.server(410))), file: file())
        #expect(await store.answer(pending(.no)) == .failed)
        #expect(store.pending.isEmpty)
        let gone = PounceStore(service: FakePounces(answer: .failure(.notFound)), file: file())
        #expect(await gone.answer(pending(.no)) == .failed)
        #expect(gone.pending.isEmpty)
    }

    @Test func busyIsKeptForLater() async {
        let store = PounceStore(service: FakePounces(answer: .failure(.conflict("busy"))), file: file())
        #expect(await store.answer(pending(.play)) == .queued)
        #expect(store.pending.count == 1)
    }

    @Test func testPlayIsNeverDowngraded() async {
        let fake = FakePounces(answer: .failure(.transport("offline")))
        let store = PounceStore(service: fake, file: file())
        _ = await store.answer(pending(.play))
        _ = await store.answer(pending(.later))
        #expect(store.pending == [pending(.play)])
        #expect(fake.calls.withLock { $0 } == ["answer pc_1 play", "answer pc_1 play"])
    }

    @Test func aDoubleTapSendsOnce() async {
        let fake = FakePounces(answer: .success(nil))
        let store = PounceStore(service: fake, file: file())
        async let a = store.answer(pending(.no))
        async let b = store.answer(pending(.no))
        let results = await [a, b]
        #expect(results.contains(.done(code: nil)))
        #expect(fake.calls.withLock { $0 } == ["answer pc_1 no"])
    }

    /// Review fix: In a bit is in flight when Play replaces it; the reply to In a bit must not
    /// drop Play, which then goes out too.
    @Test func aNewerAnswerWhileInFlightIsKept() async {
        let fake = FakePounces(answer: .success(nil))
        let store = PounceStore(service: fake, file: file())
        async let first = store.answer(pending(.later))
        try? await Task.sleep(for: .milliseconds(5))
        let second = await store.answer(pending(.play))
        _ = await first
        #expect(second == .queued)
        #expect(fake.calls.withLock { $0 } == ["answer pc_1 later", "answer pc_1 play"])
        #expect(store.pending.isEmpty)
    }

    @Test func sendReportsResting() async {
        let store = PounceStore(service: FakePounces(send: .failure(.rateLimited)), file: file())
        #expect(await store.send(pair: "pr_x", target: .new, person: "me") == .resting)
        let ok = PounceStore(service: FakePounces(), file: file())
        #expect(await ok.send(pair: "pr_x", target: .new, person: "me") == .sent("pc_1"))
    }

    @Test func aDoubleSendSendsOnce() async {
        let fake = FakePounces()
        let store = PounceStore(service: fake, file: file())
        async let a = store.send(pair: "pr_x", target: .new, person: "me")
        async let b = store.send(pair: "pr_x", target: .new, person: "me")
        let results = await [a, b]
        #expect(results.contains(.busy))
        #expect(fake.calls.withLock { $0 }.count == 1)
    }

    @Test func shareReturnsTheLink() async {
        let url = URL(string: "https://play.conleychaos.com/p/AAAAAAAAAAAAAAAAAAAAAA")!
        let store = PounceStore(service: FakePounces(send: .success(PounceSent(id: "pc_2", link: url))), file: file())
        #expect(await store.share(target: .new, person: "me") == url)
    }
}

@Suite struct PounceSheetTests {
    private func view(myMove: [String] = [], theirMove: [String] = [], pounce: PounceState = .none) -> StreakView {
        var v = StreakView(pair: "pr_x", partner: .init(name: "Mia", cat: 2), count: 4, myMove: myMove, theirMove: theirMove)
        v.pounce = pounce
        return v
    }

    @Test func theirMoveTablesComeFirstThenMineThenNewAndPick() {
        let tiles = PounceSheet.tiles(view: view(myMove: ["K9PQR", "BCDFG"], theirMove: ["BBBBB", "BCDFG"]), names: ["BBBBB": "Couch Cats"])
        #expect(tiles == [
            .table(code: "BBBBB", name: "Couch Cats", theirMove: true),
            .table(code: "BCDFG", name: TableName.fallback(code: "BCDFG"), theirMove: true),
            .table(code: "K9PQR", name: TableName.fallback(code: "K9PQR"), theirMove: false),
            .new, .pick,
        ])
    }

    @Test func noPartnerIsANewGameLinkOnly() {
        #expect(PounceSheet.tiles(view: nil, names: [:]) == [.new])
    }

    @Test func preselection() {
        let some = PounceSheet.tiles(view: view(myMove: ["K9PQR"], theirMove: ["BBBBB"]), names: [:])
        #expect(PounceSheet.preselect(some, preferNew: false) == some[0])
        #expect(PounceSheet.preselect(some, preferNew: true) == .new)
        let mine = PounceSheet.tiles(view: view(myMove: ["K9PQR"]), names: [:])
        #expect(PounceSheet.preselect(mine, preferNew: false) == .new)
        #expect(PounceSheet.preselect(PounceSheet.tiles(view: view(), names: [:]), preferNew: false) == .new)
    }

    @Test func targets() {
        let table = PounceTile.table(code: "BBBBB", name: "Couch Cats", theirMove: true)
        #expect(PounceSheet.target(table) == .table("BBBBB"))
        #expect(PounceSheet.target(.new) == .new)
        #expect(PounceSheet.target(.pick) == .pick)
        // A link can't name a table: it becomes "you pick".
        #expect(PounceSheet.shareTarget(table) == .pick)
        #expect(PounceSheet.shareTarget(.new) == .new)
        #expect(PounceSheet.shareTarget(.pick) == .pick)
    }

    @Test func bellStates() {
        #expect(BellState.make(.none) == .ready)
        #expect(BellState.make(PounceState(sent: true)) == .sent)
        #expect(BellState.make(PounceState(sent: true, quiet: true)) == .quiet)
        #expect(BellState.make(PounceState(resting: true)) == .resting)
        #expect(BellState.make(PounceState(resting: true, answer: .no)) == .answered(.no))
        #expect(BellState.make(PounceState(answer: .play, code: "GH2VD")) == .answered(.play))
        #expect(BellState.ready.name == "ready" && BellState.answered(.later).name == "later")
    }

    @Test func pickChoicesAreTheSharedTablesThenNew() {
        let tiles = PounceSheet.pickTiles(view: view(myMove: ["K9PQR"], theirMove: ["BBBBB"]), names: [:])
        #expect(tiles.map(PounceSheet.choice) == ["K9PQR", "BBBBB", "new"])
        #expect(PounceSheet.pickTiles(view: nil, names: [:]) == [.new])
    }
}

/// Review fix: on a shared phone a pounce for a household person (titled with their name, §12.2)
/// is answered as that person, not the owner.
@Suite struct PounceRecipientTests {
    private let owner = Person(id: "o", name: "JD", cat: 4)
    private let ella = Person(id: "e", name: "Ella", cat: 2)

    @Test func theTitleNamesTheRecipient() {
        #expect(PounceRecipient.person(title: "Ella", owner: owner, others: [ella]) == "e")
        #expect(PounceRecipient.person(title: "JD", owner: owner, others: [ella]) == "o")
    }

    @Test func anUnknownOrMissingTitleIsTheOwner() {
        #expect(PounceRecipient.person(title: "Zed", owner: owner, others: [ella]) == "o")
        #expect(PounceRecipient.person(title: nil, owner: owner, others: [ella]) == "o")
        #expect(PounceRecipient.person(title: "Ella", owner: nil, others: [ella]) == "e")
        #expect(PounceRecipient.person(title: nil, owner: nil, others: []) == nil)
    }

    /// A household person who shares the owner's name: the owner wins.
    @Test func theOwnerWinsATie() {
        #expect(PounceRecipient.person(title: "JD", owner: owner, others: [Person(id: "x", name: "JD", cat: 1)]) == "o")
    }
}

@Suite struct PounceLinkTests {
    private let token = "AbCdEfGhIjKlMnOpQrSt_-"

    @Test func universalLinksParse() {
        #expect(DeepLink.parse(URL(string: "https://play.conleychaos.com/p/\(token)")!) == .pounce(token: token))
        #expect(DeepLink.pounceURL(token: token).absoluteString == "https://play.conleychaos.com/p/\(token)")
    }

    @Test func theDevSchemeOnlyInDebug() {
        let dev = URL(string: "pounce-dev://p/\(token)")!
        #expect(DeepLink.parse(dev, allowDevScheme: true) == .pounce(token: token))
        #expect(DeepLink.parse(dev) == nil)
    }

    @Test func badTokensAndHostsAreRejected() {
        for bad in [
            "https://play.conleychaos.com/p/\(token.dropLast())", "https://play.conleychaos.com/p/\(token)A",
            "https://play.conleychaos.com/p/\(token.dropLast())!", "https://evil.example/p/\(token)",
            "https://play.conleychaos.com/p/\(token)/x", "https://play.conleychaos.com/q/\(token)",
        ] {
            #expect(DeepLink.parse(URL(string: bad)!) == nil, "\(bad)")
        }
    }

    @Test func joinLinksStillParse() {
        #expect(DeepLink.parse(URL(string: "https://play.conleychaos.com/j/K7QM4")!) == .join(code: "K7QM4"))
    }
}
