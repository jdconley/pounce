import Foundation
import Testing

@testable import PounceKit

@Suite struct DailyShareTests {
    private func result(_ outcome: DailyOutcome, guesses: Int? = nil, hints: Int = 0) -> DailyResult {
        DailyResult(game: "sniff", date: "2026-11-23", number: 12, outcome: outcome, timeMs: 247_000, hints: hints, progress: 1, guesses: guesses)
    }

    @Test func textIsTheLineAndLink() {
        let share = DailyShare(game: DailyCatalog.sniff, result: result(.solved, guesses: 4), marks: nil)
        #expect(share.text == "Sniff 12: 4 of 6\nhttps://play.conleychaos.com/daily")
    }

    /// Until launch day sets `LAUNCH`, a server's numbers are below 1: never show them.
    @Test func numbersBelowOneAreLeftOut() {
        let early = DailyResult(game: "sniff", date: "2026-11-23", number: -26339, outcome: .solved, timeMs: 1, progress: 1, guesses: 4)
        #expect(DailyCatalog.sniff.name(number: -26339) == "Sniff")
        #expect(DailyCatalog.sniff.name(number: 0) == "Sniff")
        #expect(DailyCatalog.sniff.name(number: 1) == "Sniff 1")
        #expect(DailyCatalog.sniff.line(early) == "Sniff: 4 of 6")
        #expect(DailyShare(game: DailyCatalog.sniff, result: early, marks: nil).text == "Sniff: 4 of 6\nhttps://play.conleychaos.com/daily")
        #expect(!DailyShare(game: DailyCatalog.sniff, result: early, marks: nil).title.contains("-"))
    }

    @Test func nineLivesShowsTimeAndHints() {
        let share = DailyShare(game: DailyCatalog.nineLives, result: result(.solved, hints: 1), marks: nil)
        #expect(share.text.hasPrefix("Nine Lives 12: 4:07\n"))
        #expect(share.detail == "1 hint")
    }

    @Test func pngRenders() async throws {
        let marks: [[DailyShareMark]] = [[.miss, .near, .miss, .miss, .hit], [.hit, .hit, .hit, .hit, .hit]]
        let share = DailyShare(game: DailyCatalog.sniff, result: result(.solved, guesses: 2), marks: marks)
        let png = try #require(await share.png(scale: 2))
        #expect(png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        // The PNG's IHDR width, big-endian at byte 16.
        let width = png[16..<20].reduce(0) { $0 << 8 | Int($1) }
        #expect(width == 1200)
        // `DAILY_SHARE_OUT=<dir>` keeps the card to look at.
        if let dir = ProcessInfo.processInfo.environment["DAILY_SHARE_OUT"] {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("share-sniff.png"))
            let plain = DailyShare(game: DailyCatalog.nineLives, result: result(.solved, hints: 1), marks: nil)
            try await plain.png()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("share-nine-lives.png"))
        }
    }
}
