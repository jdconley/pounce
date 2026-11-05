import Foundation
import Testing
@testable import PounceKit

let widgetOwner = WidgetSnapshot.Owner(person: "6f1c0e0e-0000-4000-8000-000000000001", name: "JD", cat: 4)

func widgetSnapshot(
    _ pairs: [StreakView], now: Date = at(2026, 11, 5, 12), band: AgeBand? = .adult,
    names: [String: String] = [:], quiet: ClockTime = ClockTime(h: 22, m: 0), server: String? = "https://play.conleychaos.com"
) -> WidgetSnapshot {
    WidgetSnapshot.make(
        owner: widgetOwner, band: band, server: server, pairs: pairs, names: names, quietStart: quiet,
        previous: nil, now: now, calendar: widgetCalendar())
}

@Suite struct WidgetSnapshotTests {
    let la = widgetCalendar()

    @Test func makeKeepsOnlyThePairsTableNames() {
        let s = widgetSnapshot(
            [streakView(myMove: ["GH2VD"], theirMove: ["K9PQR"])],
            names: ["GH2VD": "Couch Cats", "K9PQR": "Kitchen", "ZZZZZ": "Elsewhere"])
        #expect(s.tableNames == ["GH2VD": "Couch Cats", "K9PQR": "Kitchen"])
        #expect(s.day == "2026-11-05")
        #expect(s.owner == widgetOwner)
        #expect(s.pair(nil)?.pair == "pr_mia", "no partner chosen is the top pair")
        #expect(s.pair("pr_gone")?.pair == "pr_mia", "a pair that's gone falls back to the top one")
        #expect(s.pair("pr_mia")?.pair == "pr_mia")
    }

    @Test func roundTripsThroughTheStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)")
        let store = WidgetSnapshotStore(directory: dir)
        #expect(store.load() == nil)
        let s = widgetSnapshot([streakView(count: 9, me: true)])
        store.save(s)
        #expect(store.load() == s)
        store.update { var n = $0; n.band = .teen; return n }
        #expect(store.load()?.band == .teen)
    }

    @Test func testVisibleChange() {
        let a = widgetSnapshot([streakView(count: 9)], now: at(2026, 11, 5, 12))
        var b = widgetSnapshot([streakView(count: 9)], now: at(2026, 11, 5, 12, 30))
        #expect(!b.visiblyDiffers(from: a), "only the save time changed")
        #expect(b.visiblyDiffers(from: nil))
        b.pairs[0].me = true
        #expect(b.visiblyDiffers(from: a), "a paw lit")
        let c = widgetSnapshot([streakView(count: 9)], now: at(2026, 11, 6, 12))
        #expect(c.visiblyDiffers(from: a), "a new day greys today")
    }

    @Test func aPushUpdatesItsPair() throws {
        let push = try #require(Self.payload("your_move"))
        let s = widgetSnapshot([
            streakView("pr_3f9cAAAAAAAAAAAAAAAAAA", count: 11, me: false, them: false),
            streakView("pr_other", count: 3),
        ])
        let next = s.applying(push, now: at(2026, 11, 5, 13), calendar: la)
        let mia = try #require(next.pairs.first)
        #expect(mia.count == 12 && mia.them && !mia.me && !mia.kept)
        #expect(mia.myMove == ["GH2VD"] && mia.theirMove.isEmpty && mia.naps == 1)
        #expect(next.pairs[1] == s.pairs[1])
        #expect(next.savedAt == at(2026, 11, 5, 13))
    }

    @Test func aPushOnANewDayGreysTheOtherPairs() throws {
        let push = try #require(Self.payload("your_move"))
        let s = widgetSnapshot([
            streakView("pr_3f9cAAAAAAAAAAAAAAAAAA", count: 11),
            streakView("pr_other", count: 3, me: true, them: true, kept: true),
        ], now: at(2026, 11, 5, 12))
        let next = s.applying(push, now: at(2026, 11, 6, 9), calendar: la)
        #expect(next.day == "2026-11-06")
        #expect(next.pairs[1].kept == false && next.pairs[1].me == false && next.pairs[1].count == 3)
        #expect(next.pairs[0].them == true, "the pushed pair is today's")
    }

    @Test func testUnknownPairPushIgnored() throws {
        let push = try #require(Self.payload("your_move"))
        let s = widgetSnapshot([streakView("pr_other", count: 3)])
        #expect(s.applying(push, now: at(2026, 11, 5, 13), calendar: la).pairs == s.pairs)
    }

    @Test func testPushWithoutStreakLeavesSnapshot() throws {
        let push = try #require(Self.payload("going_quiet"))
        let s = widgetSnapshot([streakView("pr_3f9cAAAAAAAAAAAAAAAAAA", count: 3)])
        #expect(s.applying(push, now: at(2026, 11, 5, 13), calendar: la).pairs == s.pairs)
    }

    @Test func anAnswerLandsOnThePairItCameFrom() throws {
        let push = try #require(Self.payload("pounce_answered-later"))
        var jd = streakView("pr_jd", count: 7, partner: .init(name: "JD", cat: 1))
        jd.pounce = PounceState(sent: true)
        let s = widgetSnapshot([streakView(count: 2), jd])
        let next = s.applying(push, now: at(2026, 11, 5, 13), calendar: la)
        #expect(next.pairs[1].pounce.answer == .later)
        #expect(next.pairs[1].pounce.sent == false)
        #expect(next.pounced["pr_jd"] == at(2026, 11, 5, 13))
        #expect(next.pairs[0] == s.pairs[0])
    }

    @Test func freshListKeepsNamesAndNotesPounceChanges() {
        let s = widgetSnapshot([streakView(count: 2, myMove: ["GH2VD"])], names: ["GH2VD": "Couch Cats"])
        var fetched = streakView(count: 3, myMove: ["GH2VD"])
        fetched.pounce = PounceState(sent: true)
        let next = s.withPairs([fetched], now: at(2026, 11, 5, 14), calendar: la)
        #expect(next.pairs == [fetched])
        #expect(next.tableNames == ["GH2VD": "Couch Cats"])
        #expect(next.pounced["pr_mia"] == at(2026, 11, 5, 14), "the bell changed: its hour starts now")
        let again = next.withPairs([fetched], now: at(2026, 11, 5, 14, 20), calendar: la)
        #expect(again.pounced["pr_mia"] == at(2026, 11, 5, 14), "unchanged keeps the first time")
    }

    @Test func makeCarriesPounceTimesFromThePrevious() {
        var sent = streakView(count: 2)
        sent.pounce = PounceState(sent: true)
        var first = widgetSnapshot([sent], now: at(2026, 11, 5, 12))
        first.pounced["pr_mia"] = at(2026, 11, 5, 11, 50)
        let next = WidgetSnapshot.make(
            owner: widgetOwner, band: .adult, server: nil, pairs: [sent], names: [:], quietStart: ClockTime(h: 22, m: 0),
            previous: first, now: at(2026, 11, 5, 12, 10), calendar: la)
        #expect(next.pounced["pr_mia"] == at(2026, 11, 5, 11, 50))
        let ready = WidgetSnapshot.make(
            owner: widgetOwner, band: .adult, server: nil, pairs: [streakView(count: 2)], names: [:],
            quietStart: ClockTime(h: 22, m: 0), previous: first, now: at(2026, 11, 5, 12, 10), calendar: la)
        #expect(ready.pounced["pr_mia"] == nil, "a ready bell has no hour")
    }

    @Test func unknownPairsKeepTheStoredOnesProjected() {
        // The app launched offline: its streak list never loaded, so the widgets keep theirs.
        let stored = widgetSnapshot([streakView(count: 9, me: true, them: true, kept: true)], now: at(2026, 11, 5, 12))
        let next = WidgetSnapshot.make(
            owner: widgetOwner, band: .adult, server: nil, pairs: nil, names: [:], quietStart: ClockTime(h: 22, m: 0),
            previous: stored, now: at(2026, 11, 6, 9), calendar: la)
        #expect(next.pairs.map(\.count) == [9])
        #expect(next.pairs[0].kept == false, "yesterday's kept day doesn't carry into today")
        #expect(next.day == "2026-11-06")
        // Someone else's stored pairs are never kept.
        let other = WidgetSnapshot.make(
            owner: .init(person: "someone-else", name: "Ella", cat: 2), band: .adult, server: nil, pairs: nil, names: [:],
            quietStart: ClockTime(h: 22, m: 0), previous: stored, now: at(2026, 11, 6, 9), calendar: la)
        #expect(other.pairs.isEmpty)
    }

    @Test func aListFetchedYesterdayIsGreyToday() {
        // Review: the app resumed offline the next morning with last night's kept day.
        let list = [streakView(count: 9, me: true, them: true, kept: true)]
        let next = WidgetSnapshot.make(
            owner: widgetOwner, band: .adult, server: nil, pairs: list, pairsAt: at(2026, 11, 5, 22), names: [:],
            quietStart: ClockTime(h: 22, m: 0), previous: nil, now: at(2026, 11, 6, 9), calendar: la)
        #expect(next.day == "2026-11-06")
        #expect(!next.pairs[0].kept && !next.pairs[0].me && next.pairs[0].count == 9)
        #expect(next.pairsAt == at(2026, 11, 5, 22))
    }

    @Test func anOlderListNeverOverwritesNewerNews() {
        // A push (or the Pounce button) landed after the app's last fetch: the app's list waits.
        var stored = widgetSnapshot([streakView(count: 9)], now: at(2026, 11, 5, 12))
        stored = stored.applying(try! #require(Self.payloadFor("pr_mia")), now: at(2026, 11, 5, 13), calendar: la)
        #expect(stored.pairsAt == at(2026, 11, 5, 13))
        let older = WidgetSnapshot.make(
            owner: widgetOwner, band: .teen, server: nil, pairs: [streakView(count: 9)], pairsAt: at(2026, 11, 5, 12, 30),
            names: [:], quietStart: ClockTime(h: 22, m: 0), previous: stored, now: at(2026, 11, 5, 14), calendar: la)
        #expect(older.pairs == stored.pairs, "the pushed paws stay")
        #expect(older.band == .teen, "everything else is the app's")
        let newer = WidgetSnapshot.make(
            owner: widgetOwner, band: .teen, server: nil, pairs: [streakView(count: 10)], pairsAt: at(2026, 11, 5, 13, 30),
            names: [:], quietStart: ClockTime(h: 22, m: 0), previous: stored, now: at(2026, 11, 5, 14), calendar: la)
        #expect(newer.pairs.map(\.count) == [10])
    }

    @Test func aSocketViewReplacesItsPair() {
        let s = widgetSnapshot([streakView(count: 9), streakView("pr_kiki", count: 2)], now: at(2026, 11, 5, 12))
        var view = streakView(count: 10, me: true, them: true, kept: true)
        view.pounce = PounceState(sent: true)
        let next = s.replacing(view, now: at(2026, 11, 5, 15), calendar: la)
        #expect(next.pairs[0].count == 10 && next.pairs[0].kept)
        #expect(next.pairs[1] == s.pairs[1])
        #expect(next.pairsAt == at(2026, 11, 5, 15))
        #expect(next.pounced["pr_mia"] == at(2026, 11, 5, 15))
        let added = s.replacing(streakView("pr_new", count: 1), now: at(2026, 11, 5, 15), calendar: la)
        #expect(added.pairs.map(\.pair) == ["pr_mia", "pr_kiki", "pr_new"], "a brand-new pair joins at the end")
    }

    @Test func fetchesAtMostOnceAMinute() {
        let s = widgetSnapshot([streakView()], now: at(2026, 11, 5, 12))
        #expect(!s.needsFetch(now: at(2026, 11, 5, 12, 0)), "the app just wrote it")
        #expect(s.needsFetch(now: at(2026, 11, 5, 12, 1)))
        let demo = widgetSnapshot([streakView()], now: at(2026, 11, 5, 12), server: nil)
        #expect(!demo.needsFetch(now: at(2026, 11, 5, 13)), "no server, no fetch")
    }

    @Test func pushReloadsAtOnceOnlyForWhatMatters() throws {
        let la = la
        let old = widgetSnapshot([streakView("pr_3f9cAAAAAAAAAAAAAAAAAA", count: 12, them: true, myMove: ["AAAAA"])])
        let push = try #require(Self.payload("your_move"))
        // Only the move lists changed (the paws were already lit): at most every 15 minutes.
        let moves = old.applying(push, now: at(2026, 11, 5, 13), calendar: la)
        #expect(WidgetSnapshot.reloadsAfterPush(old: old, new: moves, now: at(2026, 11, 5, 13)))
        var reloaded = moves
        reloaded.pushReloadAt = at(2026, 11, 5, 13)
        var again = reloaded
        again.pairs[0].myMove = ["BBBBB"]
        #expect(!WidgetSnapshot.reloadsAfterPush(old: reloaded, new: again, now: at(2026, 11, 5, 13, 10)))
        #expect(WidgetSnapshot.reloadsAfterPush(old: reloaded, new: again, now: at(2026, 11, 5, 13, 15)))
        // A paw lit: at once, whenever.
        var paw = reloaded
        paw.pairs[0].me = true
        #expect(WidgetSnapshot.reloadsAfterPush(old: reloaded, new: paw, now: at(2026, 11, 5, 13, 1)))
        #expect(!WidgetSnapshot.reloadsAfterPush(old: old, new: old, now: at(2026, 11, 5, 13)))
    }

    @Test func bandSurvivesEveryWriter() throws {
        let s = widgetSnapshot([streakView("pr_3f9cAAAAAAAAAAAAAAAAAA")], band: .kitten)
        #expect(s.withPairs([], now: at(2026, 11, 5, 13), calendar: la).band == .kitten)
        #expect(s.applying(try #require(Self.payload("your_move")), now: at(2026, 11, 5, 13), calendar: la).band == .kitten)
        #expect(s.replacing(streakView(), now: at(2026, 11, 5, 13), calendar: la).band == .kitten)
        #expect(s.mergingPounce("pr_3f9cAAAAAAAAAAAAAAAAAA", from: s, now: at(2026, 11, 5, 13)).band == .kitten)
    }

    @Test func storeUpdatesUnderALockAndCreates() {
        let store = WidgetSnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID().uuidString)"))
        #expect(!store.update { $0 }, "nothing to update yet")
        let s = widgetSnapshot([streakView()])
        #expect(store.write { old in old == nil ? s : nil })
        #expect(store.load() == s)
        #expect(!store.write { _ in nil }, "nil writes nothing")
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            store.update { var n = $0; n.pairs[0].count += 1; return n }
        }
        #expect(store.load()?.pairs[0].count == s.pairs[0].count + 20, "no lost updates")
    }

    static func payloadFor(_ pair: String) -> PushPayload? {
        PushPayload(userInfo: [
            "kind": "your_move", "streak": ["pair": pair, "count": 9, "me": true, "them": false, "naps": 0, "myMove": [], "theirMove": []],
        ])
    }

    @Test func sampleIsAPair() {
        #expect(WidgetSnapshot.sample.pairs.first?.partner.name == "Mia")
        #expect(WidgetSnapshot.sample.owner != nil)
    }

    @Test func demoSnapshotHasNoServer() {
        let demo = DemoFixtures.widgetSnapshot()
        #expect(demo.server == nil, "previews and demos never fetch")
        #expect(demo.pairs.map(\.partner.name) == ["Mia", "Kiki", "Nova"])
        #expect(demo.tableNames["K9PQR"] == "Kitchen Table")
    }

    static func payload(_ name: String) -> PushPayload? {
        guard let entry = try? Fixtures.pushPayloads().first(where: { $0.name == name }) else { return nil }
        return PushPayload(userInfo: entry.body)
    }
}
