import Foundation
import Testing
@testable import PounceKit

/// The APNs bodies play-api sends (PR 5, `apps/play-api/fixtures/push/payloads.json`).
@Suite struct PushPayloadTests {
    private func payload(_ name: String) throws -> PushPayload {
        let entry = try #require(try Fixtures.pushPayloads().first { $0.name == name }, "no fixture \(name)")
        return try #require(PushPayload(userInfo: entry.body), "\(name) didn't decode")
    }

    @Test func everyFixtureDecodesWithItsKindAndCategory() throws {
        let all = try Fixtures.pushPayloads()
        #expect(all.count >= 15)
        for entry in all {
            let p = try #require(PushPayload(userInfo: entry.body), "\(entry.name) didn't decode")
            let kind = String(entry.name.split(separator: "-").first ?? "")
            #expect(p.kind.rawValue == kind, "\(entry.name)")
            let aps = try #require(entry.body["aps"] as? [String: Any])
            #expect(p.category?.rawValue == aps["category"] as? String, "\(entry.name)")
            #expect(p.threadId == aps["thread-id"] as? String, "\(entry.name)")
            #expect(p.title != nil && p.body != nil, "\(entry.name)")
        }
    }

    @Test func yourMoveCarriesCodeFromAndStreak() throws {
        let p = try payload("your_move")
        #expect(p.kind == .yourMove)
        #expect(p.category == .yourMove)
        #expect(p.code == "GH2VD")
        #expect(p.title == "JD")
        #expect(p.body == "Mia played. Your move at Couch Cats.")
        #expect(p.from == PushFace(name: "Mia", cat: 2))
        let streak = try #require(p.streak)
        #expect(streak.count == 12)
        #expect(streak.pair == "pr_3f9cAAAAAAAAAAAAAAAAAA")
        #expect(streak.me == false && streak.them == true && streak.naps == 1)
        #expect(streak.myMove == ["GH2VD"] && streak.theirMove.isEmpty)
    }

    @Test func pounceTargetsDecode() throws {
        #expect(try payload("pounce-table").pounce == .init(id: "pc_7QkAAAAAAAAAAAAAAAAAAA", target: .table("GH2VD")))
        #expect(try payload("pounce-new").pounce?.target == .new)
        #expect(try payload("pounce-pick-quiet").pounce?.target == .pick)
        #expect(try payload("pounce-pick-quiet").category == .pounce)
    }

    @Test func pounceAnswersDecode() throws {
        let later = try payload("pounce_answered-later")
        #expect(later.kind == .pounceAnswered)
        #expect(later.pounce?.answer == .later)
        #expect(later.from == PushFace(name: "JD", cat: 1))
        #expect(try payload("pounce_answered-play").code == "NWCDF")
        #expect(try payload("pounce_answered-no").pounce?.answer == PounceAnswer.no)
    }

    @Test func statusPushesCarryThePair() throws {
        #expect(try payload("nap").pair == "pr_3f9cAAAAAAAAAAAAAAAAAA")
        #expect(try payload("milestone").category == .status)
        #expect(try payload("play_again").kind == .playAgain)
    }

    @Test func testUnknownKindIsUnknown() {
        let p = PushPayload(userInfo: ["kind": "space_cats", "aps": ["category": "LASERS"]])
        #expect(p?.kind == .unknown)
        #expect(p?.category == nil)
    }

    @Test func testMissingFieldsDecode() {
        let p = PushPayload(userInfo: ["kind": "pounce", "pounce": ["target": "new"], "streak": ["count": 3, "extra": true]])
        #expect(p?.kind == .pounce)
        #expect(p?.pounce == nil)
        #expect(p?.streak == nil)
        #expect(p?.from == nil)
        // The legacy payload: only `title`, `body` and `code`.
        let legacy = PushPayload(userInfo: ["code": "GH2VD", "aps": ["alert": ["title": "JD", "body": "Your turn at Couch Cats"]]])
        #expect(legacy?.kind == .unknown)
        #expect(legacy?.code == "GH2VD")
        #expect(legacy?.title == "JD")
    }

    /// Review fix: a target that isn't JSON (never from APNs, but userInfo can hold anything)
    /// is left out instead of raising.
    @Test func aNonJSONTargetIsDropped() {
        let p = PushPayload(userInfo: ["kind": "pounce", "pounce": ["id": "pc_1", "target": Date()]])
        #expect(p?.pounce == .init(id: "pc_1", target: nil))
    }

    @Test func aBadRoomCodeIsDropped() {
        let p = PushPayload(userInfo: ["kind": "your_move", "code": "nope!"])
        #expect(p?.code == nil)
    }

    @Test func targetsRoundTrip() throws {
        for target in [PounceTarget.table("GH2VD"), .new, .pick] {
            let data = try JSONEncoder().encode(target)
            #expect(try JSONDecoder().decode(PounceTarget.self, from: data) == target)
        }
        #expect(String(decoding: try JSONEncoder().encode(PounceTarget.table("GH2VD")), as: UTF8.self) == #"{"table":"GH2VD"}"#)
        #expect(String(decoding: try JSONEncoder().encode(PounceTarget.new), as: UTF8.self) == #""new""#)
    }
}

@Suite struct NotifyActionsTests {
    private func payload(_ name: String) throws -> PushPayload {
        let entry = try #require(try Fixtures.pushPayloads().first { $0.name == name })
        return try #require(PushPayload(userInfo: entry.body))
    }

    private let tap = "com.apple.UNNotificationDefaultActionIdentifier"
    private let id = "pc_7QkAAAAAAAAAAAAAAAAAAA"

    @Test func categoriesHaveTheirActions() {
        #expect(NotifyActions.actions(for: .yourMove) == [.play, .inAnHour])
        #expect(NotifyActions.actions(for: .reminder) == [.play, .inAnHour])
        #expect(NotifyActions.actions(for: .pounce) == [.play, .later, .notNow])
        #expect(NotifyActions.actions(for: .status).isEmpty)
        #expect(NotifyAction.play.foreground)
        #expect(!NotifyAction.inAnHour.foreground && !NotifyAction.later.foreground && !NotifyAction.notNow.foreground)
    }

    @Test func tapsAndPlayOpenTheTable() throws {
        let move = try payload("your_move")
        #expect(NotifyActions.outcome(action: tap, payload: move) == .open("GH2VD"))
        #expect(NotifyActions.outcome(action: "PLAY", payload: move) == .open("GH2VD"))
        #expect(NotifyActions.outcome(action: "PLAY", payload: try payload("reminder")) == .open("GH2VD"))
        // A fresh start has no table: opening the app is all Play does.
        #expect(NotifyActions.outcome(action: "PLAY", payload: try payload("fresh_start")) == .none)
        #expect(NotifyActions.outcome(action: tap, payload: try payload("play_again")) == .open("NWCDF"))
    }

    @Test func inAnHourSnoozes() throws {
        #expect(NotifyActions.outcome(action: "IN_AN_HOUR", payload: try payload("your_move")) == .snooze(3600))
        #expect(NotifyActions.outcome(action: "IN_AN_HOUR", payload: try payload("last_chance")) == .snooze(3600))
    }

    @Test func pounceActionsAnswer() throws {
        let table = try payload("pounce-table")
        #expect(NotifyActions.outcome(action: "PLAY", payload: table) == .answer(id: id, .play, opensApp: true))
        #expect(NotifyActions.outcome(action: tap, payload: table) == .answer(id: id, .play, opensApp: true))
        #expect(NotifyActions.outcome(action: "LATER", payload: table) == .answer(id: id, .later, opensApp: false))
        #expect(NotifyActions.outcome(action: "NOT_NOW", payload: table) == .answer(id: id, .no, opensApp: false))
        #expect(NotifyActions.outcome(action: tap, payload: try payload("pounce-new")) == .answer(id: id, .play, opensApp: true))
    }

    @Test func youPickOpensThePickSheet() throws {
        let pick = try payload("pounce-pick-quiet")
        let mia = PushFace(name: "Mia", cat: 2)
        #expect(NotifyActions.outcome(action: tap, payload: pick) == .pick(id: id, target: .pick, from: mia))
        #expect(NotifyActions.outcome(action: "PLAY", payload: pick) == .pick(id: id, target: .pick, from: mia))
        #expect(NotifyActions.outcome(action: "LATER", payload: pick) == .answer(id: id, .later, opensApp: false))
    }

    @Test func statusTapsOpenWhatTheyNameOrNothing() throws {
        #expect(NotifyActions.outcome(action: tap, payload: try payload("nap")) == .none)
        #expect(NotifyActions.outcome(action: tap, payload: try payload("pounce_answered-play")) == .open("NWCDF"))
        #expect(NotifyActions.outcome(action: "com.apple.UNNotificationDismissActionIdentifier", payload: try payload("your_move")) == .none)
        #expect(NotifyActions.outcome(action: "SOMETHING", payload: try payload("your_move")) == .none)
    }
}

@Suite struct CommunicationPlanTests {
    private func payload(_ name: String) throws -> PushPayload {
        let entry = try #require(try Fixtures.pushPayloads().first { $0.name == name })
        return try #require(PushPayload(userInfo: entry.body))
    }

    @Test func pushesFromAPersonBecomeConversations() throws {
        let move = try #require(CommunicationPlan.make(try payload("your_move")))
        #expect(move == CommunicationPlan(sender: PushFace(name: "Mia", cat: 2), groupName: "JD", conversation: "GH2VD"))
        let pounce = try #require(CommunicationPlan.make(try payload("pounce-new")))
        #expect(pounce.sender.name == "Mia")
        #expect(pounce.conversation == "pounce:pr_3f9cAAAAAAAAAAAAAAAAAA")
        #expect(CommunicationPlan.make(try payload("play_again"))?.groupName == "Couch Cats")
        #expect(CommunicationPlan.make(try payload("pounce_answered-later"))?.sender == PushFace(name: "JD", cat: 1))
    }

    @Test func testNoFromIsNoPlan() throws {
        #expect(CommunicationPlan.make(try payload("reminder")) == nil)
        #expect(CommunicationPlan.make(try payload("nap")) == nil)
        // From someone, but a status push about the pair, not a message.
        #expect(CommunicationPlan.make(try payload("paused")) == nil)
        #expect(CommunicationPlan.make(PushPayload(userInfo: ["kind": "pounce"])!) == nil)
    }

    @Test func aCatOutOfRangeIsClamped() {
        let p = PushPayload(userInfo: ["kind": "pounce", "from": ["name": "Mia", "cat": 42], "aps": ["thread-id": "t"]])!
        #expect(CommunicationPlan.make(p)?.sender.cat == 0)
    }
}
