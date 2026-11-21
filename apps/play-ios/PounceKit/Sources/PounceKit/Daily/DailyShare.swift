import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One square of a share card's grid. It carries no letter or digit: Sniff's marks, and nothing
/// that spoils a puzzle.
public enum DailyShareMark: Sendable, Hashable {
    /// The right spot.
    case hit
    /// In it, elsewhere.
    case near
    /// Not in it.
    case miss
    case empty
}

/// What a finished run shares (spec §7): a card image and the text "Sniff 12: 4 of 6" with the
/// Dish's link. The card has the game's color, the number, the result and, for Sniff, a grid of
/// marks. Nine Lives and Cat Nap show only the time and hints. Kittens never get here (no links
/// out from an under-13's device).
public struct DailyShare: Sendable {
    public static let link = URL(string: "https://play.conleychaos.com/daily")!

    public let game: DailyGameInfo
    public let result: DailyResult
    public let marks: [[DailyShareMark]]?

    public init(game: DailyGameInfo, result: DailyResult, marks: [[DailyShareMark]]?) {
        self.game = game
        self.result = result
        self.marks = marks
    }

    public var text: String { "\(game.line(result))\n\(Self.link.absoluteString)" }

    /// The line under the result: hints used, or nothing.
    public var detail: String? {
        switch result.hints {
        case 0: nil
        case 1: "1 hint"
        default: "\(result.hints) hints"
        }
    }

    /// The card, 600 by 600 points at `scale`, as PNG. Drawn with CoreGraphics, off the main actor.
    @concurrent public func png(scale: CGFloat = 2) async -> Data? {
        let side = Int(600 * scale)
        guard
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Points, top-left origin, like a view.
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: scale, y: -scale)
        draw(in: context)
        guard let image = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    // MARK: drawing

    private static let ink = color(0x1B0B3A)
    private static let night = color(0x2A0F5C)
    private static let violet = color(0x7B2FFF)
    private static let yellow = color(0xFFD21F)
    private static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }

    private func draw(in c: CGContext) {
        let tint = Self.color(game.tint)
        // The night background, then a tinted card with a chunky ink outline and a lip.
        c.setFillColor(Self.night)
        c.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
        let card = CGRect(x: 40, y: 40, width: 520, height: 510)
        c.setFillColor(Self.ink)
        c.addPath(CGPath(roundedRect: card.offsetBy(dx: 0, dy: 10), cornerWidth: 48, cornerHeight: 48, transform: nil))
        c.fillPath()
        c.setFillColor(tint)
        c.addPath(CGPath(roundedRect: card, cornerWidth: 48, cornerHeight: 48, transform: nil))
        c.fillPath()
        c.setStrokeColor(Self.ink)
        c.setLineWidth(10)
        c.addPath(CGPath(roundedRect: card.insetBy(dx: 5, dy: 5), cornerWidth: 44, cornerHeight: 44, transform: nil))
        c.strokePath()

        text("\(game.title) \(result.number)", size: 52, color: Self.white, y: 78, in: c)
        text(game.summary(result), size: marks == nil ? 112 : 84, color: Self.yellow, y: marks == nil ? 210 : 160, in: c)
        if let detail { text(detail, size: 34, color: Self.white, y: marks == nil ? 360 : 262, in: c) }
        if let marks { grid(marks, top: detail == nil ? 270 : 316, in: c) }
        text("play.conleychaos.com/daily", size: 28, color: Self.white, y: 492, in: c)
    }

    private func grid(_ rows: [[DailyShareMark]], top: CGFloat, in c: CGContext) {
        let count = max(1, rows.map(\.count).max() ?? 1)
        let room: CGFloat = 470 - top
        let cell = min(40, (room - CGFloat(rows.count - 1) * 6) / CGFloat(max(1, rows.count)), 300 / CGFloat(count))
        let width = CGFloat(count) * cell + CGFloat(count - 1) * 6
        // A night plate under the marks, so every mark reads on every game's color.
        let height = CGFloat(rows.count) * cell + CGFloat(rows.count - 1) * 6
        let plate = CGRect(x: 300 - width / 2 - 14, y: top - 14, width: width + 28, height: height + 28)
        c.setFillColor(Self.night)
        c.addPath(CGPath(roundedRect: plate, cornerWidth: 20, cornerHeight: 20, transform: nil))
        c.fillPath()
        for (r, row) in rows.enumerated() {
            for (i, mark) in row.enumerated() {
                let rect = CGRect(x: 300 - width / 2 + CGFloat(i) * (cell + 6), y: top + CGFloat(r) * (cell + 6), width: cell, height: cell)
                let path = CGPath(roundedRect: rect, cornerWidth: cell * 0.28, cornerHeight: cell * 0.28, transform: nil)
                c.setFillColor(fill(mark))
                c.addPath(path)
                c.fillPath()
                c.setStrokeColor(Self.ink)
                c.setLineWidth(4)
                c.addPath(path)
                c.strokePath()
                // Shapes as well as colors: a filled dot for the right spot, a ring for elsewhere.
                let dot = rect.insetBy(dx: cell * 0.3, dy: cell * 0.3)
                switch mark {
                case .hit:
                    c.setFillColor(Self.ink)
                    c.fillEllipse(in: dot)
                case .near:
                    c.setStrokeColor(Self.ink)
                    c.setLineWidth(3)
                    c.strokeEllipse(in: dot)
                default: break
                }
            }
        }
    }

    private func fill(_ mark: DailyShareMark) -> CGColor {
        switch mark {
        case .hit: Self.color(0xFF2E9A)
        case .near: Self.color(0x2EB8FF)
        case .miss: Self.violet
        case .empty: Self.color(0x1B0B3A, alpha: 0.35)
        }
    }

    /// One line, centred on the card at `y` (its top), heavy and outlined in ink.
    private func text(_ string: String, size: CGFloat, color: CGColor, y: CGFloat, in c: CGContext) {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        func line(_ attributes: [NSAttributedString.Key: Any]) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        }
        let fillLine = line([.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): color])
        let strokeLine = line([
            .init(kCTFontAttributeName as String): font, .init(kCTStrokeColorAttributeName as String): Self.ink,
            .init(kCTStrokeWidthAttributeName as String): 14,
        ])
        let width = min(CTLineGetTypographicBounds(fillLine, nil, nil, nil), 480)
        let shrink = width >= 480 ? 480 / CTLineGetTypographicBounds(fillLine, nil, nil, nil) : 1
        c.saveGState()
        // CoreText draws with a bottom-left origin: flip around the line's baseline.
        c.translateBy(x: 300 - width / 2, y: y + size * 0.9 * shrink)
        c.scaleBy(x: shrink, y: -shrink)
        c.setLineJoin(.round)
        c.textPosition = .zero
        CTLineDraw(strokeLine, c)
        // Drawing a line moves the text position to its end: back to the start for the fill.
        c.textPosition = .zero
        CTLineDraw(fillLine, c)
        c.restoreGState()
    }
}
