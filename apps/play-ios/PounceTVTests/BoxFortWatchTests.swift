import Foundation
import PounceKit
import SwiftUI
import Testing
@testable import PounceTV

/// Box Fort's watch view on a 1080p TV: drawn on the stage the board gives a run (1792 by 848 points),
/// its score row is tall enough to read from the couch and the rug keeps its size.
///
/// With `BOXFORT_SHOTS_DIR` set (pass it as `TEST_RUNNER_BOXFORT_SHOTS_DIR`), each state is also
/// saved as a 1080p picture, named with `BOXFORT_SHOTS_PREFIX` ("before-", "after-").
@MainActor
struct BoxFortWatchTests {
    nonisolated static let stage = CGSize(width: 1792, height: 848)

    nonisolated private static func piece(_ id: String, _ picture: String, tint: Int) -> BoxFortPiece {
        var cells: [BoxFortCell] = []
        for (r, line) in picture.split(separator: "/").enumerated() {
            for (c, ch) in line.enumerated() where ch == "#" { cells.append(BoxFortCell(row: r, col: c)) }
        }
        return BoxFortPiece(id: id, tint: tint, cells: cells)
    }

    nonisolated private static func rug(_ rows: String...) -> [Int] {
        rows.flatMap { row in row.map { $0 == "#" ? BoxFortRules.clutter : 0 } }
    }

    nonisolated static var early: BoxFortState {
        var s = BoxFortRules.start(BoxFortPublicPuzzle(
            rug: rug(".#....##", "#...#...", "......##", "..#.....", "........", "..#.....", "........", "...###.."),
            sets: 15,
            pieces: [piece("five-v", "#/#/#/#/#", tint: 3), piece("tee-left", ".#/##/.#", tint: 5), piece("sq2", "##/##", tint: 2)]))
        s.points = 5
        return s
    }

    /// The widest the score row gets: a big score, a combo and the last set.
    nonisolated static var late: BoxFortState {
        var s = early
        s.rug = rug("##.##.##", "#......#", "..####..", "#......#", "##.##.##", "........", "#.#.#.#.", "........")
        s.set = 14
        s.points = 12345
        s.combo = 12
        s.lines = 40
        s.placed = [true, false, false]
        return s
    }

    @Test func theScoreRowReadsFromTheCouch() {
        let head = BoxFortLayout.watchHeader(for: Self.stage)
        let layout = BoxFortLayout(size: Self.stage, headerHeight: head)
        // The set count is a third of the row: 28 points or more on a 1080p TV.
        #expect(head * 0.34 >= 28)
        #expect(layout.cell >= 70, "the rug keeps its size")
    }

    @Test(arguments: [("early", early), ("late", late)])
    func drawsOnTheStage(name: String, state: BoxFortState) throws {
        let page = ZStack(alignment: .topLeading) {
            Palette.night
            BoxFortWatch(state: state)
                .frame(width: Self.stage.width, height: Self.stage.height)
                .offset(x: 64, y: 168)
        }
        .frame(width: 1920, height: 1080)
        let renderer = ImageRenderer(content: page)
        renderer.scale = 1
        let image = try #require(renderer.uiImage)
        #expect(image.size == CGSize(width: 1920, height: 1080))
        guard let dir = ProcessInfo.processInfo.environment["BOXFORT_SHOTS_DIR"] else { return }
        let prefix = ProcessInfo.processInfo.environment["BOXFORT_SHOTS_PREFIX"] ?? ""
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try #require(image.pngData())
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)appletv-watch-\(name)-1080p.png"))
    }
}
