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
}
