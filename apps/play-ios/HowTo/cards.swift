// Draws the How to play videos' overlays from HowTo/beats.json: the title card (the game's name
// and "How to play" over its cover on the night background; it is also the poster) and one transparent frame-sized caption
// per beat, a chunky ink pill with the line in the app's type (SF Rounded Black with the ink
// outline, like OutlinedText). make.sh lays them over the footage with ffmpeg.
//   swift HowTo/cards.swift <game id> <out dir>    # from apps/play-ios
// Writes <out>/title.png and <out>/cap-<seg>-<beat>.png at the video's size (beats.json "size").
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Sheet: Decodable {
    struct Beat: Decodable { let seg, beat, caption: String; let y: Double? }
    struct Game: Decodable { let title, cover, tint: String; let captionY: Double; let beats: [Beat] }
    let size: [Int]
    let games: [String: Game]
}

func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}
let ink = "1B0B3A", night = "2A0F5C", yellow = "FFD21F", orange = "FF8A00"
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rounded(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .black)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size)!
}

func line(_ text: String, _ size: CGFloat, _ fill: CGColor) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
        .font: rounded(size), .kern: -size * 0.01, .foregroundColor: NSColor(cgColor: fill)!,
    ]))
}

func width(_ text: String, _ size: CGFloat) -> CGFloat {
    CGFloat(CTLineGetTypographicBounds(line(text, size, color(ink)), nil, nil, nil))
}

/// One centered line with the app's chunky ink outline: a fat stroke pass, then the fill on top.
func draw(_ text: String, size: CGFloat, fill: CGColor, centerX: CGFloat, baseline: CGFloat, in ctx: CGContext) {
    let x = centerX - width(text, size) / 2
    ctx.saveGState()
    ctx.setLineJoin(.round)
    ctx.setLineWidth(size * 0.2)
    ctx.setStrokeColor(color(ink))
    ctx.setTextDrawingMode(.stroke)
    ctx.textPosition = CGPoint(x: x, y: baseline - size * 0.045)
    CTLineDraw(line(text, size, color(ink)), ctx)
    ctx.restoreGState()
    ctx.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(line(text, size, fill), ctx)
}

/// Splits `text` into the fewest lines that fit `maxWidth` (at most two, broken near the middle).
func wrap(_ text: String, size: CGFloat, maxWidth: CGFloat) -> [String] {
    if width(text, size) <= maxWidth { return [text] }
    let words = text.split(separator: " ").map(String.init)
    var best: [String] = [text]
    var bestScore = CGFloat.infinity
    for i in 1..<words.count {
        let a = words[..<i].joined(separator: " "), b = words[i...].joined(separator: " ")
        let score = max(width(a, size), width(b, size))
        if score < bestScore { bestScore = score; best = [a, b] }
    }
    return best
}

func canvas(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ ctx: CGContext, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

func caption(_ text: String, tint: String, centerY: Double, w: Int, h: Int, out: String) {
    let ctx = canvas(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    var size = (W * 0.066).rounded()
    let maxText = W - 64
    var lines = wrap(text, size: size, maxWidth: maxText)
    while lines.contains(where: { width($0, size) > maxText }) { size -= 1; lines = wrap(text, size: size, maxWidth: maxText) }
    let lead = size * 1.14
    let textW = lines.map { width($0, size) }.max()!
    let boxW = textW + size * 1.3, boxH = lead * CGFloat(lines.count) + size * 0.75
    // CoreGraphics counts y up from the bottom.
    let cy = H * (1 - CGFloat(centerY))
    let box = CGRect(x: (W - boxW) / 2, y: cy - boxH / 2, width: boxW, height: boxH)
    let r = min(boxH / 2, size * 0.9)
    // A hard toy shadow, the ink body, a tint rim.
    ctx.setFillColor(color(ink, 0.55))
    ctx.addPath(CGPath(roundedRect: box.offsetBy(dx: 0, dy: -5), cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(color(ink, 0.92))
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.fillPath()
    ctx.setStrokeColor(color(tint))
    ctx.setLineWidth(4)
    ctx.addPath(CGPath(roundedRect: box.insetBy(dx: 3, dy: 3), cornerWidth: r - 3, cornerHeight: r - 3, transform: nil))
    ctx.strokePath()
    let top = cy + lead * CGFloat(lines.count) / 2
    for (i, l) in lines.enumerated() {
        draw(l, size: size, fill: color(i == 0 ? yellow : yellow), centerX: W / 2, baseline: top - lead * CGFloat(i + 1) + size * 0.3, in: ctx)
    }
    save(ctx, out)
}

func title(_ game: Sheet.Game, w: Int, h: Int, out: String) {
    let ctx = canvas(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    // Night, with a sunburst of tint rays from behind the cover.
    ctx.setFillColor(color(night))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let center = CGPoint(x: W / 2, y: H * 0.52)
    for i in 0..<18 where i % 2 == 0 {
        let a0 = CGFloat(i) / 18 * 2 * .pi, a1 = CGFloat(i + 1) / 18 * 2 * .pi
        ctx.move(to: center)
        ctx.addLine(to: CGPoint(x: center.x + cos(a0) * H, y: center.y + sin(a0) * H))
        ctx.addLine(to: CGPoint(x: center.x + cos(a1) * H, y: center.y + sin(a1) * H))
        ctx.closePath()
    }
    ctx.setFillColor(color(game.tint, 0.28))
    ctx.fillPath()
    // The cover, in a chunky ink frame.
    if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: game.cover) as CFURL, nil),
       let cover = CGImageSourceCreateImageAtIndex(src, 0, nil) {
        let cw = W - 56, ch = cw * CGFloat(cover.height) / CGFloat(cover.width)
        let rect = CGRect(x: 28, y: center.y - ch / 2, width: cw, height: ch)
        let frame = rect.insetBy(dx: -7, dy: -7)
        ctx.setFillColor(color(ink, 0.5))
        ctx.addPath(CGPath(roundedRect: frame.offsetBy(dx: 0, dy: -9), cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(color(ink))
        ctx.addPath(CGPath(roundedRect: frame, cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 28, cornerHeight: 28, transform: nil))
        ctx.clip()
        ctx.draw(cover, in: rect)
        ctx.restoreGState()
    }
    var size = (W * 0.15).rounded()
    while width(game.title, size) > W - 48 { size -= 1 }
    // The name and "How to play" over the cover; the bottom third stays clear for the app's play
    // button on the poster.
    draw(game.title, size: size, fill: color(yellow), centerX: W / 2, baseline: H * 0.80, in: ctx)
    draw("How to play", size: (W * 0.085).rounded(), fill: color(orange), centerX: W / 2, baseline: H * 0.735, in: ctx)
    save(ctx, out)
}

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("usage: swift HowTo/cards.swift <game id> <out dir>") }
let sheet = try JSONDecoder().decode(Sheet.self, from: Data(contentsOf: URL(fileURLWithPath: "HowTo/beats.json")))
guard let game = sheet.games[args[1]] else { fatalError("no game \(args[1]) in beats.json") }
let out = args[2]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let (w, h) = (sheet.size[0], sheet.size[1])
title(game, w: w, h: h, out: "\(out)/title.png")
for beat in game.beats {
    caption(beat.caption, tint: game.tint, centerY: beat.y ?? game.captionY, w: w, h: h, out: "\(out)/cap-\(beat.seg)-\(beat.beat).png")
}
print("\(out): title.png and \(game.beats.count) captions")
