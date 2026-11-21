import CoreGraphics
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

    @Test(arguments: [(1792, 848), (848, 1792), (1200, 1200)])
    func theQuiltFitsItsBox(width: Int, height: Int) throws {
        let margin = 100
        let cells = Self.solution.enumerated().map { i, d in Self.givens[i] != 0 || i % 2 == 0 ? d : 0 }
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
}
