// Composes the App Store screenshot set: each raw capture (AppStore/raw/<set>/<shot>.png, from
// capture.sh) on a branded background under its caption (captions.json), at the capture's own
// pixel size, so the output is exactly a size App Store Connect accepts (1206x2622 for the required
// medium-display iPhone set, 2064x2752 for the 13" iPad set). JPEG, no alpha, under 1.5 MB.
//   swift AppStore/compose.swift            # from apps/play-ios; writes AppStore/screenshots/
// Type and palette are the app's: SF Rounded Black with the ink outline (OutlinedText), and the
// Loud Toy colors (Palette.swift).
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Caption: Decodable { let shot, line1, line2, top, bottom: String }

func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}
let ink = "1B0B3A"
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rounded(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .black)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size)!
}

/// One centered line with the app's chunky ink outline: a fat stroke pass, then the fill on top.
func draw(_ text: String, size: CGFloat, fill: CGColor, centerX: CGFloat, baseline: CGFloat, in ctx: CGContext) {
    let font = rounded(size)
    func line(_ attrs: [NSAttributedString.Key: Any]) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs.merging([.font: font, .kern: -size * 0.01]) { a, _ in a }))
    }
    let plain = line([.foregroundColor: NSColor(cgColor: fill)!])
    let width = CTLineGetTypographicBounds(plain, nil, nil, nil)
    let x = centerX - CGFloat(width) / 2
    ctx.saveGState()
    ctx.setLineJoin(.round)
    ctx.setLineWidth(size * 0.2)
    ctx.setStrokeColor(color(ink))
    ctx.setTextDrawingMode(.stroke)
    // The outline sits a little low, like a toy's drop edge.
    ctx.textPosition = CGPoint(x: x, y: baseline - size * 0.045)
    CTLineDraw(line([.foregroundColor: NSColor(cgColor: color(ink))!]), ctx)
    ctx.restoreGState()
    ctx.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(plain, ctx)
}

func width(_ text: String, _ size: CGFloat) -> CGFloat {
    let l = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: rounded(size), .kern: -size * 0.01]))
    return CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
}

func compose(raw: URL, caption: Caption, out: URL) throws {
    guard let src = CGImageSourceCreateWithURL(raw as CFURL, nil), let shot = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw NSError(domain: "compose", code: 1, userInfo: [NSLocalizedDescriptionKey: "can't read \(raw.path)"])
    }
    let W = CGFloat(shot.width), H = CGFloat(shot.height)
    let pad = H > W * 1.8  // a phone: taller caption band
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Background: a two-color candy gradient with big soft dots.
    let gradient = CGGradient(colorsSpace: sRGB, colors: [color(caption.top), color(caption.bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
    var seed = UInt64(caption.shot.unicodeScalars.reduce(7) { $0 &* 31 &+ Int($1.value) } & 0xFFFF) + 11
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10_000) / 10_000 }
    for _ in 0..<14 {
        let r = W * (0.05 + 0.13 * rnd())
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07 + 0.06 * rnd()))
        ctx.fillEllipse(in: CGRect(x: rnd() * W - r, y: rnd() * H - r, width: 2 * r, height: 2 * r))
    }

    // Caption: two lines, sized to fit the width.
    let band = pad ? H * 0.2 : H * 0.185
    var size = pad ? W * 0.118 : W * 0.085
    let widest = max(width(caption.line1, size), width(caption.line2, size))
    let room = W * 0.88
    if widest > room { size *= room / widest }
    let mid = H - band / 2 - (pad ? H * 0.012 : 0)
    draw(caption.line1, size: size, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), centerX: W / 2, baseline: mid + size * 0.2, in: ctx)
    draw(caption.line2, size: size, fill: color("FFD21F"), centerX: W / 2, baseline: mid - size * 0.92, in: ctx)

    // The capture: whole screen, rounded, in a chunky ink frame with a hard toy shadow.
    let bottom = H * 0.022
    let h = H - band - bottom - (pad ? H * 0.012 : H * 0.01)
    let scale = h / H
    let rect = CGRect(x: (W - W * scale) / 2, y: bottom, width: W * scale, height: h)
    let radius = (pad ? W * 0.085 : W * 0.03)
    let frame = W * 0.011
    let outer = rect.insetBy(dx: -frame, dy: -frame)
    ctx.setFillColor(color(ink, 0.45))
    ctx.addPath(CGPath(roundedRect: outer.offsetBy(dx: 0, dy: -frame * 1.4), cornerWidth: radius + frame, cornerHeight: radius + frame, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(color(ink))
    ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius + frame, cornerHeight: radius + frame, transform: nil))
    ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(shot, in: rect)
    ctx.restoreGState()

    let image = ctx.makeImage()!
    // JPEG under 1.5 MB: step the quality down until it fits.
    for quality in stride(from: 0.92, through: 0.5, by: -0.04) {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
        if data.length < 1_450_000 {
            try (data as Data).write(to: out)
            print("\(out.lastPathComponent)  \(Int(W))x\(Int(H))  \(data.length / 1024) KB  q\(String(format: "%.2f", quality))")
            return
        }
    }
    throw NSError(domain: "compose", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(out.lastPathComponent) won't fit under 1.5 MB"])
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppStore")
let captions = try JSONDecoder().decode([Caption].self, from: Data(contentsOf: root.appendingPathComponent("captions.json")))
let outDir = root.appendingPathComponent("screenshots")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for set in ["iphone", "ipad"] {
    for (i, caption) in captions.enumerated() {
        try compose(raw: root.appendingPathComponent("raw/\(set)/\(caption.shot).png"), caption: caption,
                    out: outDir.appendingPathComponent("\(set)-\(i + 1).jpg"))
    }
}
