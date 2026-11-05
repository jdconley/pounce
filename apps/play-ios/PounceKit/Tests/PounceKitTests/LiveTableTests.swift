import Foundation
import Testing
@testable import PounceKit

/// The live table's push bodies (play-api `fixtures/push/live-activity.json`): each one's
/// `content-state` and `attributes` must decode exactly as ActivityKit will decode them.
@Suite struct LiveTableFixtureTests {
    private func bodies() throws -> [(name: String, aps: [String: Any])] {
        let data = try Data(contentsOf: Fixtures.url("push/live-activity.json"))
        let list = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return try list.map { entry in
            let name = try #require(entry["name"] as? String)
            let body = try #require(entry["body"] as? [String: Any])
            return (name, try #require(body["aps"] as? [String: Any]))
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func everyContentStateDecodes() throws {
        let all = try bodies()
        #expect(all.map(\.name) == ["start-their-move", "start-my-move", "update-my-move", "update-their-move", "end"])
        for (name, aps) in all {
            let state = try decode(LiveTableState.self, try #require(aps["content-state"]))
            #expect(state.table == "Couch Cats", "\(name)")
            #expect(state.seats.count == 3)
            // Round trip: what the app encodes (a local demo, previews) decodes the same.
            let again = try JSONDecoder().decode(LiveTableState.self, from: JSONEncoder().encode(state))
            #expect(again == state)
        }
    }

    @Test func theFieldsMeanWhatTheServerMeans() throws {
        let all = Dictionary(uniqueKeysWithValues: try bodies().map { ($0.name, $0.aps) })
        let theirs = try decode(LiveTableState.self, try #require(all["start-their-move"]?["content-state"]))
        #expect(theirs.turn == 1 && !theirs.mine)
        #expect(theirs.seats[0] == .init(cat: 1, phase: 3, name: "JD", bot: false, me: true))
        #expect(theirs.seats[2] == .init(cat: 3, phase: 2, name: nil, bot: true, me: false))
        #expect(theirs.streak == .init(count: 12, me: false, them: true))
        let mine = try decode(LiveTableState.self, try #require(all["update-my-move"]?["content-state"]))
        #expect(mine.turn == 0 && mine.mine)
        let end = try decode(LiveTableState.self, try #require(all["end"]?["content-state"]))
        #expect(end.turn == nil && end.streak == nil)
    }

    @Test func theStartNamesTheAttributesType() throws {
        let start = try #require(try bodies().first { $0.name == "start-their-move" }?.aps)
        #expect(start["attributes-type"] as? String == LiveTableAttributes.typeName)
        #expect(LiveTableAttributes.typeName == String(describing: LiveTableAttributes.self))
        let attributes = try decode(LiveTableAttributes.self, try #require(start["attributes"]))
        #expect(attributes == LiveTableAttributes(code: "GH2VD"))
    }
}

@Suite struct LiveTableLookTests {
    private func state(turn: Int?, mine: Bool, streak: LiveTableState.Paws? = .init(count: 12, me: true, them: false)) -> LiveTableState {
        LiveTableState(
            table: "Couch Cats",
            seats: [
                .init(cat: 1, phase: 3, name: "JD", bot: false, me: true),
                .init(cat: 2, phase: 4, name: "Mia", bot: false, me: false),
                .init(cat: 3, phase: 2, name: nil, bot: true, me: false),
            ],
            turn: turn, mine: mine, streak: streak)
    }

    @Test func theRingIsOnWhoeverMovesAndTheBellOnlyWhenItsYours() {
        let theirs = LiveTableLook(state(turn: 1, mine: false))
        #expect(theirs.seats.map(\.glowing) == [false, true, false])
        #expect(!theirs.bell)
        #expect(theirs.trailing == .cat(2, bot: false))
        let mine = LiveTableLook(state(turn: 0, mine: true))
        #expect(mine.seats.map(\.glowing) == [true, false, false])
        #expect(mine.bell)
        #expect(mine.trailing == .bell)
        let bot = LiveTableLook(state(turn: 2, mine: false))
        #expect(bot.trailing == .cat(3, bot: true))
        let between = LiveTableLook(state(turn: nil, mine: false))
        #expect(between.seats.allSatisfy { !$0.glowing })
        #expect(between.trailing == .none)
    }

    @Test func yourCatLeads() {
        #expect(LiveTableLook(state(turn: 1, mine: false)).leadingCat == 1)
        var s = state(turn: 1, mine: false)
        s.seats = s.seats.map { var seat = $0; seat.me = false; return seat }
        #expect(LiveTableLook(s).leadingCat == 1, "no seat of yours: the first cat")
        s.seats = []
        #expect(LiveTableLook(s).leadingCat == 0)
    }

    @Test func pawsShowWhoIsInToday() {
        #expect(LiveTableLook(state(turn: 1, mine: false)).paws == .init(count: 12, me: true, them: false))
        #expect(LiveTableLook(state(turn: 1, mine: false, streak: .init(count: 3, me: true, them: true))).paws == .init(count: 3, me: true, them: true))
        #expect(LiveTableLook(state(turn: 1, mine: false, streak: .init(count: 4, me: false, them: true))).paws == .init(count: 4, me: false, them: true))
        #expect(LiveTableLook(state(turn: 1, mine: false, streak: nil)).paws == nil)
    }

    @Test func phasesAreNumeralsAndVoiceOverHearsNames() {
        let look = LiveTableLook(state(turn: 1, mine: false))
        #expect(look.seats.map(\.phase) == [3, 4, 2])
        #expect(look.spoken == "Couch Cats. Mia's move.")
        #expect(LiveTableLook(state(turn: 0, mine: true)).spoken == "Couch Cats. Your move.")
        #expect(LiveTableLook(state(turn: 2, mine: false)).spoken == "Couch Cats. House Cat's move.")
        #expect(LiveTableLook(state(turn: nil, mine: false)).spoken == "Couch Cats.")
    }
}

@Suite struct LiveTableTokenTests {
    private let token = String(repeating: "ab", count: 40)

    @Test func uploadsOnceForTeensAndAdults() {
        for band in [AgeBand.teen, .adult] {
            #expect(LiveTableToken.needsUpload(token: token, deviceId: "dev1", last: nil, band: band))
            let last = LiveTableToken.Uploaded(deviceId: "dev1", token: token)
            #expect(!LiveTableToken.needsUpload(token: token, deviceId: "dev1", last: last, band: band))
            #expect(LiveTableToken.needsUpload(token: token, deviceId: "dev2", last: last, band: band), "a new device")
            #expect(LiveTableToken.needsUpload(token: "cd" + token.dropFirst(2), deviceId: "dev1", last: last, band: band))
        }
        #expect(!LiveTableToken.needsUpload(token: nil, deviceId: "dev1", last: nil, band: .adult))
    }

    @Test func testKittenNeverUploads() {
        #expect(!LiveTableToken.uploads(band: .kitten))
        #expect(!LiveTableToken.needsUpload(token: token, deviceId: "dev1", last: nil, band: .kitten))
    }

    @Test func testUnknownBandNeverUploads() {
        #expect(!LiveTableToken.uploads(band: nil))
        #expect(!LiveTableToken.needsUpload(token: token, deviceId: "dev1", last: nil, band: nil))
    }
}

@Suite struct LiveTableSweepTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func item(_ id: String, _ code: String, staleIn minutes: Double?) -> LiveTableSweep.Item {
        .init(id: id, code: code, stale: minutes.map { now.addingTimeInterval($0 * 60) })
    }

    @Test func openingATableEndsItsLiveTable() {
        let items = [item("a", "GH2VD", staleIn: 20)]
        #expect(LiveTableSweep.toEnd(items, entering: "GH2VD", liveOn: true, now: now) == ["a"])
        #expect(LiveTableSweep.toEnd(items, entering: "BCDFG", liveOn: true, now: now) == [])
        #expect(LiveTableSweep.toEnd(items, entering: nil, liveOn: true, now: now) == [])
    }

    @Test func staleOnesGoAndOnlyTheNewestStays() {
        let items = [item("old", "BCDFG", staleIn: 10), item("stale", "HJKLM", staleIn: -1), item("new", "GH2VD", staleIn: 29)]
        #expect(Set(LiveTableSweep.toEnd(items, entering: nil, liveOn: true, now: now)) == ["old", "stale"])
        // A local demo has no stale date: it counts as the newest.
        let demo = [item("demo", "GH2VD", staleIn: nil), item("pushed", "BCDFG", staleIn: 25)]
        #expect(LiveTableSweep.toEnd(demo, entering: nil, liveOn: true, now: now) == ["pushed"])
    }

    @Test func theToggleOffEndsThemAll() {
        let items = [item("a", "GH2VD", staleIn: 20), item("b", "BCDFG", staleIn: 25)]
        #expect(Set(LiveTableSweep.toEnd(items, entering: nil, liveOn: false, now: now)) == ["a", "b"])
        #expect(LiveTableSweep.toEnd([], entering: nil, liveOn: true, now: now) == [])
    }
}

@Suite struct LiveTableClientTests {
    private func stored() -> MemoryCredentialStore {
        let s = MemoryCredentialStore()
        s.save(DeviceCredential(deviceId: "dev1", token: "tok1"))
        return s
    }

    @Test func pushToStartTokenGoesUp() async throws {
        let server = StubServer { _ in Reply(204, "") }
        let api = APIClient(config: server.config(), credentials: stored(), session: server.session())
        let hex = String(repeating: "ab", count: 40)
        #expect(try await api.setLivePushToStart(hex) == "dev1")
        let put = try #require(server.seen.last)
        #expect(put.method == "PUT" && put.path == "/v1/devices/me/live-activity")
        let json = try #require(try JSONSerialization.jsonObject(with: put.body) as? [String: String])
        #expect(json == ["pushToStart": hex])
    }

    @Test func anActivityTokenGoesUpAndNullClearsIt() async throws {
        let server = StubServer { _ in Reply(204, "") }
        let api = APIClient(config: server.config(), credentials: stored(), session: server.session())
        let hex = String(repeating: "cd", count: 40)
        try await api.setLiveActivityToken(code: "GH2VD", token: hex)
        try await api.setLiveActivityToken(code: "GH2VD", token: nil)
        let bodies = try server.seen.map { try #require(try JSONSerialization.jsonObject(with: $0.body) as? [String: Any]) }
        let first = try #require((bodies[0]["activities"] as? [[String: Any]])?.first)
        #expect(first["code"] as? String == "GH2VD" && first["token"] as? String == hex)
        let second = try #require((bodies[1]["activities"] as? [[String: Any]])?.first)
        #expect(second["token"] is NSNull, "an explicit null, not a missing key")
    }
}
