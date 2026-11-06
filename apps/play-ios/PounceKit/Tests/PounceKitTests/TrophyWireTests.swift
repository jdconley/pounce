import Foundation
import Testing
@testable import PounceKit

/// The trophy room's wire (play-api `src/streaks/personal.ts`, `trophies.ts`, `tests/trophy.test.ts`).
@Suite struct TrophyWireTests {
    private static let own = #"{"count":12,"best":20,"kept":true,"naps":1,"winback":null,"lifetimeKept":40,"perfectWeeks":2,"week":[{"day":"2026-11-05","state":"nap"},{"day":"2026-11-06","state":"kept"}]}"#

    @Test func streakListCarriesOwnWhenTheServerHasIt() throws {
        let json = #"{"own":\#(Self.own),"pairs":[],"left":[]}"#
        let list = try JSONDecoder().decode(StreakList.self, from: Data(json.utf8))
        let own = try #require(list.own)
        #expect(own.count == 12 && own.best == 20 && own.kept && own.naps == 1 && own.winback == nil)
        #expect(own.lifetimeKept == 40 && own.perfectWeeks == 2)
        #expect(own.week.map(\.state) == [.nap, .kept])
    }

    @Test func streakListWithoutOwnIsTrophyOff() throws {
        let list = try JSONDecoder().decode(StreakList.self, from: Data(#"{"pairs":[]}"#.utf8))
        #expect(list.own == nil)
    }

    @Test func ownDecodesMissingOptionals() throws {
        let own = try JSONDecoder().decode(OwnStreak.self, from: Data(#"{"count":3}"#.utf8))
        #expect(own == OwnStreak(count: 3, best: 3))
        let back = try JSONDecoder().decode(OwnStreak.self, from: Data(#"{"count":3,"winback":{"kept":1}}"#.utf8))
        #expect(back.winback == StreakView.Winback(kept: 1))
    }

    @Test func trophiesDecode() throws {
        let json = """
        {"own":\(Self.own),
         "records":{"current":12,"best":20,"longestPair":128,"totalDays":40,"perfectWeeks":2},
         "earned":{"toys":["toy-mouse"],"backs":["back-crown"],"rugs":[],"condoStage":4},
         "catalog":[{"id":"condo-1","kind":"condo","at":1,"progress":1},{"id":"rug-night-sky","kind":"rug","at":30,"progress":0.4},
                    {"id":"toy-new-thing","kind":"sticker","at":2,"progress":0}],
         "connections":[{"pair":"pr_x","partner":{"name":"Mia","cat":2},"count":5}]}
        """
        let t = try JSONDecoder().decode(Trophies.self, from: Data(json.utf8))
        #expect(t.records == .init(current: 12, best: 20, longestPair: 128, totalDays: 40, perfectWeeks: 2))
        #expect(t.earned == .init(toys: ["toy-mouse"], backs: ["back-crown"], rugs: [], condoStage: 4))
        #expect(t.catalog.map(\.kind) == [.condo, .rug, .unknown])
        #expect(t.catalog[1].at == 30 && abs(t.catalog[1].progress - 0.4) < 0.0001)
        #expect(t.connections.map(\.partner.name) == ["Mia"])
    }

    @Test func trophiesRouteIsGetMeTrophies() async throws {
        let minted = #"{"deviceId":"dev1","token":"tok1"}"#
        let server = StubServer { req in
            req.path == "/v1/devices" ? Reply(200, minted)
                : Reply(200, #"{"own":{"count":0},"records":{"current":0,"best":0,"longestPair":0,"totalDays":0,"perfectWeeks":0},"earned":{"toys":[],"backs":[],"rugs":[],"condoStage":0},"catalog":[],"connections":[]}"#)
        }
        let api = APIClient(config: server.config(), credentials: MemoryCredentialStore(), session: server.session())
        let t = try await api.trophies(person: "me-1")
        #expect(t.records.current == 0)
        let get = try #require(server.seen.last)
        #expect(get.method == "GET" && get.path == "/v1/me/trophies" && get.query == "person=me-1")
    }
}
