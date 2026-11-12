import PounceKit
import SpriteKit
import SwiftUI
import UIKit

/// The bad connection glyph: three signal bars rising left to right, the tallest wearing cat
/// ears, chunky with ink outlines like the rest of the art. `weak` fills one bar with ink;
/// `lost` fills none. It sits on orange (weak) or red (lost): the pill's own color, or a disc of
/// it with an ink rim on a seat (`badge`). Drawn in code, cached per size.
enum SignalGlyph {
    enum Level: Hashable {
        case weak, lost
    }

    @MainActor private static var cache: [String: UIImage] = [:]

    /// The glyph alone (`badge` false), or on a night disc with an ink rim, like the seat badges.
    @MainActor static func image(_ level: Level, side: CGFloat, badge: Bool = false) -> UIImage {
        let key = "\(level)|\(Int(side))|\(badge)"
        if let cached = cache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            var area = CGRect(x: 0, y: 0, width: side, height: side)
            if badge {
                let rim = max(1.5, side * 0.07)
                UIColor(Palette.ink).setFill()
                UIBezierPath(ovalIn: area).fill()
                UIColor(level == .lost ? Palette.refuse : Palette.orange).setFill()
                UIBezierPath(ovalIn: area.insetBy(dx: rim, dy: rim)).fill()
                area = area.insetBy(dx: side * 0.22, dy: side * 0.2).offsetBy(dx: 0, dy: side * 0.03)
            }
            draw(level, in: area, cg)
        }
        cache[key] = image
        return image
    }

    @MainActor static func texture(_ level: Level, side: CGFloat) -> SKTexture {
        SKTexture(image: image(level, side: side, badge: true))
    }

    @MainActor private static var pills: [String: SKTexture] = [:]

    /// The seat's pill under its name: ink on orange (weak) or white on red (lost), with an ink
    /// rim; cut short with an ellipsis past `maxWidth`, never shrunk below legible.
    @MainActor static func pillTexture(_ level: Level, text: String, maxWidth: CGFloat, size: CGFloat = 12) -> SKTexture {
        let key = "\(level)|\(text)|\(Int(maxWidth))|\(Int(size))"
        if let cached = pills[key] { return cached }
        let font = UIFont.systemFont(ofSize: size, weight: .black).rounded
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: level == .weak ? UIColor(Palette.ink) : UIColor.white,
        ]
        let h = ceil(font.lineHeight + 4)
        let pad = h * 0.45
        let textSize = (text as NSString).size(withAttributes: attrs)
        let canvas = CGSize(width: min(maxWidth, ceil(textSize.width + 2 * pad)), height: h)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            let pill = CGRect(origin: .zero, size: canvas)
            UIColor(Palette.ink).setFill()
            UIBezierPath(roundedRect: pill, cornerRadius: h / 2).fill()
            UIColor(level == .weak ? Palette.orange : Palette.refuse).setFill()
            UIBezierPath(roundedRect: pill.insetBy(dx: 1.5, dy: 1.5), cornerRadius: h / 2 - 1.5).fill()
            let box = CGRect(x: pad, y: (h - textSize.height) / 2, width: canvas.width - 2 * pad, height: textSize.height)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            var drawn = attrs
            drawn[.paragraphStyle] = style
            (text as NSString).draw(in: box, withAttributes: drawn)
        }
        let texture = SKTexture(image: image)
        pills[key] = texture
        return texture
    }

    private static func draw(_ level: Level, in area: CGRect, _ cg: CGContext) {
        let s = area.width
        let line = max(1.2, s * 0.08)
        let barWidth = s * 0.22
        let gap = (s - 3 * barWidth - line) / 2
        let bottom = area.maxY - line / 2
        let heights: [CGFloat] = [0.34, 0.56, 0.74].map { $0 * s }
        let lit = level == .weak ? 1 : 0
        for (i, height) in heights.enumerated() {
            let x = area.minX + line / 2 + CGFloat(i) * (barWidth + gap)
            let bar = CGRect(x: x, y: bottom - height, width: barWidth, height: height)
            let path = UIBezierPath(roundedRect: bar, cornerRadius: barWidth * 0.3)
            if i == 2 {
                // Cat ears on the tallest bar.
                let ear = barWidth * 0.55
                path.move(to: CGPoint(x: bar.minX, y: bar.minY + ear * 0.3))
                path.addLine(to: CGPoint(x: bar.minX + ear * 0.15, y: bar.minY - ear * 0.75))
                path.addLine(to: CGPoint(x: bar.minX + ear * 0.8, y: bar.minY + ear * 0.1))
                path.close()
                path.move(to: CGPoint(x: bar.maxX, y: bar.minY + ear * 0.3))
                path.addLine(to: CGPoint(x: bar.maxX - ear * 0.15, y: bar.minY - ear * 0.75))
                path.addLine(to: CGPoint(x: bar.maxX - ear * 0.8, y: bar.minY + ear * 0.1))
                path.close()
            }
            let fill: UIColor = i < lit ? UIColor(Palette.ink) : UIColor.white
            fill.setFill()
            path.fill()
            UIColor(Palette.ink).setStroke()
            path.lineWidth = line
            path.lineJoinStyle = .round
            path.stroke()
        }
        _ = cg
    }
}

private extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// What a seat's or this phone's link shows: the glyph level and its short words.
enum LinkWords {
    static func weak() -> String {
        String(localized: "Weak signal", comment: "Bad connection: round trips to the server are slow")
    }

    static func reconnecting() -> String {
        String(localized: "Reconnecting", comment: "Bad connection: the connection dropped and the app is getting it back")
    }

    /// A seat's link as words, or nil when it is fine. One short word: the tag sits under a cat
    /// in the top bar, as wide as the seat.
    static func seat(_ link: SeatLink?) -> (level: SignalGlyph.Level, text: String)? {
        switch link {
        case .some(.weak): (.weak, String(localized: "Weak", comment: "A seat's tag in the top bar: that player's connection is slow"))
        case .some(.lost): (.lost, String(localized: "Offline", comment: "A seat's tag in the top bar: that player's connection dropped"))
        case .some(let other) where !other.rawValue.isEmpty:  // a future value: say something mild
            (.weak, String(localized: "Weak", comment: "A seat's tag in the top bar: that player's connection is slow"))
        default: nil
        }
    }
}

/// This phone's connection at the top of the table and lobby: the glyph and a word or two on an
/// ink pill. Never a modal: it covers nothing that can be tapped.
struct ConnectionPill: View {
    let connection: RoomStore.Connection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var level: SignalGlyph.Level { connection == .weak ? .weak : .lost }
    private var text: String { connection == .weak ? LinkWords.weak() : LinkWords.reconnecting() }

    var body: some View {
        HStack(spacing: 6) {
            Image(uiImage: SignalGlyph.image(level, side: 22))
                .resizable()
                .frame(width: 22, height: 22)
                .opacity(connection == .reconnecting && pulse && !reduceMotion ? 0.45 : 1)
            Text(verbatim: text)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(connection == .weak ? Palette.ink : .white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(connection == .weak ? Palette.orange : Palette.refuse))
        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 2.5))
        .overlay(Capsule().strokeBorder(.white, lineWidth: 1).padding(2.5))
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
        .onAppear {
            // Not under a UI test: XCUITest waits for the app to idle, and an endless animation never does.
            guard !Pace.underTest else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).paced) { pulse = true }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityIdentifier("table.connection")
        .accessibilityValue(connection == .weak ? "weak" : "reconnecting")
    }
}
