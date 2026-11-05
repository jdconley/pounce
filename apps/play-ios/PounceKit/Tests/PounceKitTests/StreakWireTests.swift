import Foundation
import Testing
@testable import PounceKit

@Suite struct StreakWireTests {
    private func server(_ name: String) throws -> String {
        guard let found = try Fixtures.streakServerMessages().first(where: { $0.name == name }) else {
            throw Fixtures.FixtureError.malformed("no streak fixture \(name)")
        }
        return found.json
    }

    private func jsonEqual(_ a: String, _ b: String) throws -> Bool {
        let x = try JSONSerialization.jsonObject(with: Data(a.utf8)) as! NSObject
        let y = try JSONSerialization.jsonObject(with: Data(b.utf8)) as! NSObject
        return x.isEqual(y)
    }

    @Test func decodesEveryStreakServerSample() throws {
        let samples = try Fixtures.streakServerMessages()
        #expect(samples.count == 7)
        for (name, json) in samples {
            #expect(throws: Never.self, "\(name)") { _ = try Codec.decode(json) }
        }
    }

    @Test func streakMessageCarriesTheView() throws {
        guard case .streak(let pair, let person, let view) = try Codec.decode(server("streak")) else {
            Issue.record("not a streak message"); return
        }
        #expect(pair == "pair_3f9cAAAAAAAAAAAAAAAAAA")
        #expect(person == "11111111-1111-4111-8111-111111111111")
        #expect(view.partner == StreakView.Partner(name: "Bob", cat: 3))
        #expect(view.count == 1 && view.me && view.them && view.kept)
        #expect(view.week.count == 7)
        #expect(view.week.last == WeekDot(day: "2026-11-04", state: .kept))
        #expect(view.week.first?.state == WeekState.none)
        #expect(view.todayToy == "toy-golden-fish")
        #expect(view.toys == ["toy-golden-fish"])
        #expect(view.unlocked == StreakView.Unlocks(backs: ["back-violet-paw"], rugs: ["rug-classic"]))
        #expect(view.myMove == ["BCDFG"] && view.theirMove.isEmpty)
        #expect(view.next == 3 && view.condoStage == 1 && view.winback == nil && view.pausedUntil == nil)
        #expect(view.pinned == false)
    }

    @Test func rematchAndLookEvent() throws {
        #expect(try Codec.decode(server("rematch")) == .rematch(code: "NWCDF"))
        #expect(try Codec.decode(server("event-look"))
            == .event(seq: 9, event: .look(seat: 1, look: Look(rug: "rug-night-sky", back: "back-crown"))))
    }

    @Test func snapshotCarriesLook() throws {
        guard case .snapshot(_, _, let room) = try Codec.decode(server("snapshot-lobby-with-look")) else {
            Issue.record("not a snapshot"); return
        }
        #expect(room.look == .standard)
        #expect(room.rematch == nil)
    }

    @Test func snapshotWithoutLookHasNone() throws {
        let json = #"{"t":"snapshot","protocol":1,"seq":1,"room":{"code":"BCDFG","name":"X","status":"over","youAreHost":true,"seats":[],"game":null,"look":{"rug":"rug-classic","back":"back-crown"},"rematch":"NWCDF"}}"#
        guard case .snapshot(_, _, let room) = try Codec.decode(json) else { Issue.record("no"); return }
        #expect(room.rematch == "NWCDF")
        #expect(room.look?.back == "back-crown")
    }

    @Test func newErrorCodes() throws {
        #expect(try Codec.decode(server("error-not_unlocked")) == .error(.notUnlocked))
        #expect(try Codec.decode(server("error-too_soon")) == .error(.tooSoon))
        #expect(try Codec.decode(server("error-not_over")) == .error(.notOver))
    }

    @Test func encodesEveryStreakClientSample() throws {
        let samples = try Fixtures.streakClientMessages()
        #expect(samples.count == 4)
        let expected: [String: ClientMessage] = [
            "rematch": .rematch,
            "setLook-rug": .setLook(rug: "rug-night-sky", back: nil),
            "setLook-back": .setLook(rug: nil, back: "back-crown"),
            "setLook-both": .setLook(rug: "rug-classic", back: "back-violet-paw"),
        ]
        for (name, json) in samples {
            let message = try #require(expected[name], "\(name)")
            #expect(try jsonEqual(Codec.encode(message), json), "\(name)")
        }
    }

    @Test func unknownWeekStateIsNone() throws {
        let dot = try JSONDecoder().decode(WeekDot.self, from: Data(#"{"day":"2026-11-04","state":"sparkly"}"#.utf8))
        #expect(dot.state == WeekState.none)
    }

    @Test func missingOptionalsDecode() throws {
        let json = #"""
        {"pair":"pr_x","partner":{"name":"Mia","cat":2},"count":4,"me":false,"them":true,"naps":1,
         "winback":{"kept":1},"pausedUntil":"2026-11-08","best":9,"lifetimeKept":12,"perfectWeeks":0,
         "week":[],"next":7,"condoStage":3,"toys":[],"todayToy":null,
         "unlocked":{"backs":[],"rugs":[]},"gifts":[{"id":"g1","milestone":3,"item":"toy-mouse"}],
         "myMove":[],"theirMove":["ABCDE"]}
        """#
        let view = try JSONDecoder().decode(StreakView.self, from: Data(json.utf8))
        #expect(view.kept == false && view.pinned == false)
        #expect(view.winback == StreakView.Winback(kept: 1))
        #expect(view.pausedUntil == "2026-11-08")
        #expect(view.gifts == [StreakView.Gift(id: "g1", milestone: 3, item: "toy-mouse")])
    }

    @Test func listDecodesWithAndWithoutLeft() throws {
        let with = try JSONDecoder().decode(StreakList.self, from: Data(
            #"{"pairs":[],"left":[{"pair":"pr_old","partner":{"name":"Leo","cat":1}}]}"#.utf8))
        #expect(with.left == [LeftPair(pair: "pr_old", partner: .init(name: "Leo", cat: 1))])
        let without = try JSONDecoder().decode(StreakList.self, from: Data(#"{"pairs":[]}"#.utf8))
        #expect(without.left.isEmpty && without.pairs.isEmpty)
    }

    @Test func tableEntryCarriesNext() throws {
        let entry = try JSONDecoder().decode(TableEntry.self, from: Data(
            #"{"code":"BCDFG","name":"X","status":"over","yourTurn":false,"updatedAt":1,"next":"NWCDF"}"#.utf8))
        #expect(entry.next == "NWCDF")
    }

    @Test func viewRoundTrips() throws {
        guard case .streak(_, _, let view) = try Codec.decode(server("streak")) else { return }
        #expect(try JSONDecoder().decode(StreakView.self, from: JSONEncoder().encode(view)) == view)
    }
}
