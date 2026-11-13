import Foundation
import Testing
@testable import PounceKit

@Suite struct HomeTablesTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private var nowMs: Double { now.timeIntervalSince1970 * 1000 }
    private let hour: Double = 3_600_000

    private func entry(_ code: String, _ status: String, turn: Bool = false, ago: Double = 0) -> TableEntry {
        TableEntry(code: code, status: status, yourTurn: turn, updatedAt: nowMs - ago)
    }

    private func cached(_ code: String, turn: Seat? = nil) -> CachedTable {
        CachedTable(
            code: code, status: .playing,
            seats: [
                CachedSeat(kind: .human, name: "Mochi", cat: 2, yours: true),
                CachedSeat(kind: .human, name: "Biscuit", cat: 5),
            ],
            turn: turn, updatedAt: now)
    }

    @Test func yourTurnFirstThenRecentThenFinished() {
        let items = HomeTables.merge(
            entries: [
                entry("OVER2", "over", ago: 2 * hour),
                entry("WAIT1", "playing", ago: 1 * hour),
                entry("MINE1", "playing", turn: true, ago: 5 * hour),
                entry("LOBB1", "lobby", ago: 3 * hour),
                entry("MINE2", "playing", turn: true, ago: 1 * hour),
            ],
            cache: [:], now: now)
        #expect(items.map(\.id) == ["MINE2", "MINE1", "WAIT1", "LOBB1", "OVER2"])
        #expect(items.map(\.yourTurn) == [true, true, false, false, false])
    }

    @Test func aGameInPlaySaysHowManyWholeDaysItsMoveHasWaited() throws {
        let day = 24 * hour
        func moved(_ code: String, _ status: String = "playing", ago: Double?) -> TableEntry {
            TableEntry(code: code, status: status, yourTurn: false, updatedAt: nowMs, movedAt: ago.map { nowMs - $0 })
        }
        let items = HomeTables.merge(
            entries: [
                moved("FRESH", ago: day - 1), moved("DAY01", ago: day), moved("DAYS3", ago: 3 * day + hour),
                moved("OLDSV", ago: nil), moved("LOBBY", "lobby", ago: 5 * day), moved("OVER1", "over", ago: 5 * day),
            ],
            cache: [:], now: now)
        let days = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.idleDays) })
        #expect(days == ["FRESH": nil, "DAY01": 1, "DAYS3": 3, "OLDSV": nil, "LOBBY": nil, "OVER1": nil])
        // The server's field decodes, and a list without it still does.
        let json = #"{"code":"BCDFG","status":"playing","yourTurn":true,"updatedAt":5,"movedAt":4}"#
        #expect(try JSONDecoder().decode(TableEntry.self, from: Data(json.utf8)).movedAt == 4)
        let old = #"{"code":"BCDFG","status":"playing","yourTurn":true,"updatedAt":5}"#
        #expect(try JSONDecoder().decode(TableEntry.self, from: Data(old.utf8)).movedAt == nil)
    }

    @Test func nameComesFromTheServerListThenTheCacheThenTheCode() {
        var named = cached("CACH1")
        named.name = "Cached Name"
        var stale = cached("BOTH1")
        stale.name = "Old Name"
        let items = HomeTables.merge(
            entries: [
                TableEntry(code: "LIST1", name: "Taco Night", status: "lobby", yourTurn: false, updatedAt: nowMs),
                TableEntry(code: "BOTH1", name: "New Name", status: "lobby", yourTurn: false, updatedAt: nowMs - 1),
                entry("CACH1", "lobby", ago: 2),
                entry("NONE1", "lobby", ago: 3),
            ],
            cache: ["CACH1": named, "BOTH1": stale], now: now)
        #expect(items.map(\.name) == ["Taco Night", "New Name", "Cached Name", nil])
        #expect(items.map(\.title) == ["Taco Night", "New Name", "Cached Name", "Table NONE1"])
    }

    @Test func overAndOldIsDropped() {
        let items = HomeTables.merge(
            entries: [entry("OLD11", "over", ago: 25 * hour), entry("NEW11", "over", ago: 23 * hour)],
            cache: [:], now: now)
        #expect(items.map(\.id) == ["NEW11"])
    }

    @Test func finishedTableNeverClaimsYourTurn() {
        let items = HomeTables.merge(
            entries: [entry("DONE1", "over", turn: true, ago: hour), entry("PLAY1", "playing", ago: 2 * hour)],
            cache: [:], now: now)
        #expect(items.map(\.id) == ["PLAY1", "DONE1"])
        #expect(items.last?.yourTurn == false)
    }

    @Test func codesMissingFromServerAreDropped() {
        let items = HomeTables.merge(
            entries: [entry("KEEP1", "playing")],
            cache: ["KEEP1": cached("KEEP1"), "GONE1": cached("GONE1")], now: now)
        #expect(items.map(\.id) == ["KEEP1"])
    }

    @Test func catsAreFilledFromCache() {
        let items = HomeTables.merge(
            entries: [entry("CATS1", "playing", turn: true), entry("CATS2", "playing")],
            cache: ["CATS1": cached("CATS1", turn: 1), "CATS2": cached("CATS2", turn: 0)], now: now)
        #expect(items[0].seats.map(\.cat) == [2, 5])
        #expect(items[0].turnCat == 5)
        #expect(items[1].turnCat == 2)
    }

    @Test func theListsSeatsWinOverTheCache() {
        let listed = TableEntry(
            code: "CATS1", status: "playing", yourTurn: false, updatedAt: nowMs,
            seats: [
                TableSeat(kind: .human, person: Person(id: "me", name: "Mochi", cat: 2), yours: true),
                TableSeat(kind: .human, person: Person(id: "sam", name: "Sam", cat: 6)),
            ])
        let items = HomeTables.merge(
            entries: [listed, entry("CATS2", "lobby", ago: 1)],
            cache: ["CATS1": cached("CATS1", turn: 1), "CATS2": cached("CATS2")], now: now)
        #expect(items[0].seats == [
            CachedSeat(kind: .human, name: "Mochi", cat: 2, yours: true, person: "me"),
            CachedSeat(kind: .human, name: "Sam", cat: 6, person: "sam"),
        ])
        // The turn still comes from the cache, read against the list's seats.
        #expect(items[0].turnCat == 6)
        // A list entry without seats falls back to the cache.
        #expect(items[1].seats.map(\.name) == ["Mochi", "Biscuit"])
    }

    @Test func uncachedTableStillAppearsWithoutCats() {
        let items = HomeTables.merge(entries: [entry("BARE1", "lobby")], cache: [:], now: now)
        #expect(items.count == 1)
        #expect(items[0].seats.isEmpty)
        #expect(items[0].turnCat == nil)
        #expect(items[0].status == "lobby")
    }

    @Test func turnOutsideSeatsGivesNoCat() {
        let items = HomeTables.merge(
            entries: [entry("ODD11", "playing")], cache: ["ODD11": cached("ODD11", turn: 9)], now: now)
        #expect(items[0].turnCat == nil)
    }

    // MARK: archive

    @Test func archivedTablesLeaveHomeForTheArchivedList() {
        let entries = [
            entry("KEEP1", "playing", ago: hour), entry("HIDE1", "playing", ago: 2 * hour),
            entry("HIDE2", "lobby", ago: 3 * hour),
        ]
        let archived = ["HIDE1": nowMs - 2 * hour, "HIDE2": nowMs - 3 * hour]
        #expect(HomeTables.merge(entries: entries, cache: [:], archived: archived, now: now).map(\.id) == ["KEEP1"])
        #expect(
            HomeTables.archivedItems(entries: entries, cache: [:], archived: archived, now: now).map(\.id)
                == ["HIDE1", "HIDE2"])
    }

    @Test func aTableArchivedOnYourTurnStaysArchivedUntilSomeoneMoves() {
        let untouched = entry("MINE1", "playing", turn: true, ago: hour)
        #expect(HomeTables.isArchived(untouched, mark: untouched.updatedAt))
        let moved = entry("MINE1", "playing", turn: true, ago: 0)
        #expect(!HomeTables.isArchived(moved, mark: untouched.updatedAt))
    }

    @Test func aNewTurnForYouBringsATableBack() {
        let mark = nowMs - 2 * hour
        let items = HomeTables.merge(
            entries: [entry("BACK1", "playing", turn: true, ago: hour)], cache: [:],
            archived: ["BACK1": mark], now: now)
        #expect(items.map(\.id) == ["BACK1"])
        #expect(HomeTables.archivedItems(
            entries: [entry("BACK1", "playing", turn: true, ago: hour)], cache: [:],
            archived: ["BACK1": mark], now: now).isEmpty)
    }

    @Test func otherPlayersMovesAndTheEndDoNotBringATableBack() {
        let mark = nowMs - 5 * hour
        #expect(HomeTables.isArchived(entry("PLAY1", "playing", ago: hour), mark: mark))
        #expect(HomeTables.isArchived(entry("DONE1", "over", turn: true, ago: hour), mark: mark))
        #expect(HomeTables.isArchived(entry("LOBB1", "lobby", ago: hour), mark: mark))
    }

    @Test func oldFinishedTablesLeaveTheArchivedListToo() {
        let items = HomeTables.archivedItems(
            entries: [entry("OLD11", "over", ago: 25 * hour), entry("NEW11", "over", ago: hour)],
            cache: [:], archived: ["OLD11": 0, "NEW11": 0], now: now)
        #expect(items.map(\.id) == ["NEW11"])
    }

    @Test func keptArchiveDropsUnlistedAndReturnedTables() {
        let archived = ["STAY1": nowMs - 3 * hour, "GONE1": nowMs - 3 * hour, "BACK1": nowMs - 3 * hour]
        let kept = HomeTables.keptArchive(
            entries: [entry("STAY1", "playing", ago: hour), entry("BACK1", "playing", turn: true, ago: hour)],
            archived: archived)
        #expect(kept == ["STAY1": nowMs - 3 * hour])
    }

    // MARK: a table you sit at alone

    private func lobby(_ code: String, _ seats: [TableSeat]) -> TableEntry {
        TableEntry(code: code, status: "lobby", yourTurn: false, updatedAt: nowMs, seats: seats)
    }

    private let me = TableSeat(kind: .human, person: Person(id: "a", name: "Mochi", cat: 2), yours: true)
    private let open = TableSeat(kind: .open)

    @Test func aNewTableNobodyWasInvitedToStaysOffHome() {
        let entries = [lobby("ALONE", [me, open, open])]
        #expect(HomeTables.merge(entries: entries, cache: [:], now: now).isEmpty)
        #expect(HomeTables.archivedItems(entries: entries, cache: [:], archived: ["ALONE": nowMs], now: now).isEmpty)
    }

    @Test func anInviteKeepsItOnHomeForADay() {
        let entries = [lobby("ALONE", [me, open])]
        let hourAgo = nowMs - 3_600_000
        #expect(HomeTables.merge(entries: entries, cache: [:], invited: ["ALONE": hourAgo], now: now).map(\.id) == ["ALONE"])
        let dayAgo = nowMs - 24 * 3_600_000
        #expect(HomeTables.merge(entries: entries, cache: [:], invited: ["ALONE": dayAgo], now: now).isEmpty)
    }

    @Test func anyoneSittingDownMakesItATable() {
        let bot = TableSeat(kind: .bot)
        let mia = TableSeat(kind: .human, person: Person(id: "m", name: "Mia", cat: 4))
        let sam = TableSeat(kind: .human, person: Person(id: "s", name: "Sam", cat: 6), yours: true)
        let entries = [lobby("BOT01", [me, bot]), lobby("MIA01", [me, mia]), lobby("PASS1", [me, sam])]
        #expect(HomeTables.merge(entries: entries, cache: [:], now: now).map(\.id).sorted() == ["BOT01", "MIA01", "PASS1"])
    }

    @Test func aTableInPlayOrWithUnknownSeatsIsNeverHidden() {
        let playing = TableEntry(code: "PLAY1", status: "playing", yourTurn: false, updatedAt: nowMs, seats: [me, open])
        let unknown = TableEntry(code: "OLD01", status: "lobby", yourTurn: false, updatedAt: nowMs)
        #expect(HomeTables.merge(entries: [playing, unknown], cache: [:], now: now).map(\.id).sorted() == ["OLD01", "PLAY1"])
    }
}
