import CoreGraphics
import ImageIO
import PounceKit
import SwiftUI
import Testing
@testable import PounceTV

/// Nine Lives' watch view on a 1080p Apple TV: the quilt and its lip stay inside the box the TV gives
/// it, whatever its shape (a wide stage is 1792 by 848). It is rendered centred on a larger, clear
/// canvas; anything drawn outside the box is overflow.
@MainActor
struct NineLivesWatchTests {
    private static func digits(_ text: String) -> [Int] { text.map { Int(String($0))! } }
    private static let givens = digits("600350270050900130030804906400000003080000020500000009301205080025008040064073002")
    private static let solution = digits("649351278258967134137824956412589763983716425576432819391245687725698341864173592")

    /// The rows and columns of `image` with anything drawn on them.
    private static func inked(_ image: CGImage) -> (rows: ClosedRange<Int>, cols: ClosedRange<Int>)? {
        let (w, h) = (image.width, image.height)
        var alpha = [UInt8](repeating: 0, count: w * h)
        let drew = alpha.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }
        var (top, bottom, left, right) = (h, -1, w, -1)
        for y in 0..<h {
            for x in 0..<w where alpha[y * w + x] > 8 {
                top = min(top, y); bottom = max(bottom, y); left = min(left, x); right = max(right, x)
            }
        }
        return bottom < 0 ? nil : (top...bottom, left...right)
    }

    private static let half = solution.enumerated().map { i, d in givens[i] != 0 || i % 2 == 0 ? d : 0 }

    /// Rendered at 1 pixel a point, in a clear margin of `margin` all round.
    private static func render(_ state: NineLivesState, width: Int, height: Int, margin: Int) throws -> CGImage {
        let watch = NineLivesWatch(puzzle: NineLivesPuzzle(givens: givens), state: state)
        let canvas = watch
            .frame(width: CGFloat(width), height: CGFloat(height))
            .padding(CGFloat(margin))
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    /// Under the lives rules the counters sit beside the quilt (or under it), and the whole of it,
    /// a wrong number and the counters too, stays in the box; the quilt still takes most of it.
    @Test(arguments: [(1792, 848), (848, 1792), (1200, 1200)])
    func theQuiltAndCountersFitTheirBox(width: Int, height: Int) throws {
        let margin = 100
        let open = (0..<81).filter { Self.half[$0] == 0 }
        let state = NineLivesState(
            cells: Self.half, hinted: [], rules: .lives, lives: 1, hintsLeft: 2,
            wrong: [NineLivesWrong(i: open[0], d: Self.solution[open[0]] % 9 + 1), NineLivesWrong(i: open[3], d: 1)])
        let image = try Self.render(state, width: width, height: height, margin: margin)
        let ink = try #require(Self.inked(image))
        #expect(ink.rows.lowerBound >= margin - 1, "drawn above the box")
        #expect(ink.rows.upperBound <= margin + height, "drawn below the box: rows \(ink.rows)")
        #expect(ink.cols.lowerBound >= margin - 1, "drawn left of the box")
        #expect(ink.cols.upperBound <= margin + width, "drawn right of the box")
        // The quilt is as large as the room the counters leave: the box's height beside them, or
        // under them the smaller of its width and what is left of its height.
        let wide = width * 10 >= height * 14
        let room = wide ? height : min(width, Int(CGFloat(height) - NineLivesWatch.panelTall - NineLivesWatch.gap))
        let quilt = wide ? ink.rows.count : ink.cols.count
        #expect(quilt >= room * 95 / 100, "the watch is \(ink.cols.count) by \(ink.rows.count) in \(width) by \(height)")
        // Out of lives, with the solution in: the same.
        let out = NineLivesState(cells: Self.half, hinted: [], rules: .lives, lives: 0, hintsLeft: 0, wrong: state.wrong, solution: Self.solution)
        let ended = try #require(Self.inked(try Self.render(out, width: width, height: height, margin: margin)))
        #expect(ended.cols.upperBound <= margin + width && ended.rows.upperBound <= margin + height && ended.cols.lowerBound >= margin - 1)
    }

    /// The counters' marks: each empty cell's last wrong number, and the solution once out.
    @Test func theWatchShowsWrongNumbersAndTheSolution() {
        let open = (0..<81).filter { Self.half[$0] == 0 }
        var state = NineLivesState(
            cells: Self.half, hinted: [], rules: .lives, lives: 1, hintsLeft: 0,
            wrong: [NineLivesWrong(i: open[0], d: 4), NineLivesWrong(i: open[0], d: 7), NineLivesWrong(i: open[1], d: Self.solution[open[1]] % 9 + 1)])
        var marks = NineLivesWatch.marks(NineLivesBoard(puzzle: NineLivesPuzzle(givens: Self.givens), state: state))
        #expect(marks.wrong[open[0]] == 7 && marks.wrong.count == 2 && marks.solution == nil)
        state = NineLivesState(cells: Self.half, hinted: [], rules: .lives, lives: 0, hintsLeft: 0, wrong: state.wrong, solution: Self.solution)
        marks = NineLivesWatch.marks(NineLivesBoard(puzzle: NineLivesPuzzle(givens: Self.givens), state: state))
        #expect(marks.solution == Self.solution)
        #expect(NineLivesWatch.hintsWords(2) == "2 hints left" && NineLivesWatch.hintsWords(1) == "1 hint left" && NineLivesWatch.hintsWords(0) == "No hints left")
        // The first rules: no counters, no marks.
        let first = NineLivesWatch.marks(NineLivesBoard(puzzle: NineLivesPuzzle(givens: Self.givens), state: NineLivesState(cells: Self.half, hinted: [])))
        #expect(first.wrong.isEmpty && first.solution == nil)
    }

    @Test(arguments: [(1792, 848), (848, 1792), (1200, 1200)])
    func theQuiltFitsItsBox(width: Int, height: Int) throws {
        let margin = 100
        let cells = Self.half
        let watch = NineLivesWatch(puzzle: NineLivesPuzzle(givens: Self.givens), state: NineLivesState(cells: cells, hinted: []))
        let canvas = watch
            .frame(width: CGFloat(width), height: CGFloat(height))
            .padding(CGFloat(margin))
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let ink = try #require(Self.inked(image))
        let short = min(width, height)
        // Inside the box on every side (a pixel of antialiasing allowed).
        #expect(ink.rows.lowerBound >= margin - 1, "drawn above the box")
        #expect(ink.rows.upperBound <= margin + height, "drawn below the box: rows \(ink.rows)")
        #expect(ink.cols.lowerBound >= margin - 1, "drawn left of the box")
        #expect(ink.cols.upperBound <= margin + width, "drawn right of the box")
        // As large as the shorter side allows, with its lip, and centred.
        #expect(ink.cols.count >= short * 97 / 100, "the quilt is \(ink.cols.count) wide in a \(width) by \(height) box")
        let middle = (ink.rows.lowerBound + ink.rows.upperBound) / 2
        #expect(abs(middle - (margin + height / 2)) <= 2, "centred top to bottom: rows \(ink.rows), cols \(ink.cols)")
    }

    /// `NINE_LIVES_WATCH_OUT=<dir>` (`TEST_RUNNER_` prefixed under xcodebuild) keeps a 1080p picture
    /// of the stage, its box dashed, for each state: the PR's screenshots.
    @Test func picturesForThePR() throws {
        guard let dir = ProcessInfo.processInfo.environment["NINE_LIVES_WATCH_OUT"], !dir.isEmpty else { return }
        let open = (0..<81).filter { Self.half[$0] == 0 }
        let wrong = [NineLivesWrong(i: open[0], d: Self.solution[open[0]] % 9 + 1), NineLivesWrong(i: open[5], d: Self.solution[open[5]] % 9 + 1)]
        var cells = Self.half
        cells[open[9]] = Self.solution[open[9]]
        let states: [(String, NineLivesState)] = [
            ("first-rules", NineLivesState(cells: Self.half, hinted: [])),
            ("lives", NineLivesState(cells: cells, hinted: [open[9]], rules: .lives, lives: 1, hintsLeft: 2, wrong: wrong)),
            ("out", NineLivesState(cells: cells, hinted: [open[9]], rules: .lives, lives: 0, hintsLeft: 0,
                                   wrong: wrong + [NineLivesWrong(i: open[7], d: 1)], solution: Self.solution)),
        ]
        for (name, state) in states {
            let stage = ZStack {
                Palette.night
                RoundedRectangle(cornerRadius: 0).strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .frame(width: 1792, height: 848)
                NineLivesWatch(puzzle: NineLivesPuzzle(givens: Self.givens), state: state).frame(width: 1792, height: 848)
            }
            .frame(width: 1920, height: 1080)
            let renderer = ImageRenderer(content: stage)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let url = URL(fileURLWithPath: dir).appendingPathComponent("appletv-1080p-\(name).png")
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(dest, image, nil)
            #expect(CGImageDestinationFinalize(dest))
        }
    }
}
