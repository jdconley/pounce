import Foundation
import Testing
@testable import PounceKit

/// A TV's kept Daily Dish board token: 30 days, then gone.
@Suite("A TV's kept board")
struct BoardKeepTests {
    private let token = String(repeating: "B", count: 22)
    private let day: TimeInterval = 86_400

    @Test func aBoardIsKeptForThirtyDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let kept = KeptBoard.fresh(token, now: now)
        #expect(kept.token == token)
        #expect(kept.live(at: now.addingTimeInterval(29 * day)))
        #expect(!kept.live(at: now.addingTimeInterval(30 * day + 1)))
    }

    @Test func aTokenThatIsNotOneIsNeverLive() {
        #expect(!KeptBoard(token: "short", until: .distantFuture).live(at: .now))
        #expect(!KeptBoard(token: "B/BBBBBBBBBBBBBBBBBBBB", until: .distantFuture).live(at: .now))
    }

    @Test func memoryKeepsAndForgets() async {
        let keep = MemoryBoardKeep()
        #expect(await keep.load() == nil)
        let kept = KeptBoard.fresh(token, now: .now)
        await keep.keep(kept)
        #expect(await keep.load() == kept)
        await keep.keep(nil)
        #expect(await keep.load() == nil)
    }

    @Test func itRoundTripsAsJSON() throws {
        let kept = KeptBoard.fresh(token, now: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try JSONEncoder().encode(kept)
        #expect(try JSONDecoder().decode(KeptBoard.self, from: data) == kept)
    }
}
