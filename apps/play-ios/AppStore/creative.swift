// Composes the App Store creative assets (product page header, search results): the hero group
// (Art/store/store-hero.png, made with Art/tools/gen.sh and cut.sh from Art/prompts/store/) and
// the app's own effect sprites on a procedural sunburst, with the name and tagline in the app's
// type (SF Rounded Black with the ink outline, the Loud Toy colors from Palette.swift).
//   swift AppStore/creative.swift            # from apps/play-ios; writes AppStore/creative/
//   swift AppStore/creative.swift --guides   # the same with each layout's safe box drawn
// Sizes are Apple's "Creative assets specifications" (App Store Connect Help, read 2026-11-11):
// header 21:9 3840x1646, search results 3:2 3840x2560, no alpha.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}
// Palette.swift
let ink = "1B0B3A", violet = "7B2FFF", magenta = "FF2E9A", teal = "00D1C1", orange = "FF8A00", sun = "FFD21F"

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Pounce/Resources/Assets.xcassets")

func load(_ url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("can't read \(url.path)")
    }
    return img
}
/// A catalog sprite by name, at @3x.
func sprite(_ name: String) -> CGImage {
    let e = FileManager.default.enumerator(at: catalog, includingPropertiesForKeys: nil)!
    for case let u as URL in e where u.deletingLastPathComponent().lastPathComponent == "\(name).imageset" && u.lastPathComponent.hasSuffix("@3x.png") {
        return load(u)
    }
    fatalError("no sprite \(name)")
}

func rounded(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .black)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size)!
}
func textWidth(_ text: String, _ size: CGFloat, kern: CGFloat = -0.01) -> CGFloat {
    let l = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: rounded(size), .kern: size * kern]))
    return CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
}
/// One line with the app's chunky ink outline (OutlinedText): a fat stroke pass that sits a
/// little low, then the fill on top. `x` is the left edge, or the center when `centered`.
func drawText(_ text: String, size: CGFloat, fill: CGColor, x: CGFloat, baseline: CGFloat, centered: Bool = false,
              kern: CGFloat = -0.01, stroke: CGFloat = 0.2, in ctx: CGContext) {
    let font = rounded(size)
    func line(_ c: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: size * kern, .foregroundColor: NSColor(cgColor: c)!]))
    }
    let plain = line(fill)
    let left = centered ? x - CGFloat(CTLineGetTypographicBounds(plain, nil, nil, nil)) / 2 : x
    ctx.saveGState()
    ctx.setLineJoin(.round)
    ctx.setLineWidth(size * stroke)
    ctx.setStrokeColor(color(ink))
    ctx.setTextDrawingMode(.stroke)
    ctx.textPosition = CGPoint(x: left, y: baseline - size * 0.05)
    CTLineDraw(line(color(ink)), ctx)
    ctx.restoreGState()
    ctx.textPosition = CGPoint(x: left, y: baseline)
    CTLineDraw(plain, ctx)
}

/// Draws an image by its center and height (y up), rotated, with a hard toy shadow under it.
func place(_ img: CGImage, cx: CGFloat, cy: CGFloat, height: CGFloat, rotate deg: CGFloat = 0, flip: Bool = false,
           shadow: CGFloat = 0.022, in ctx: CGContext) {
    let w = height * CGFloat(img.width) / CGFloat(img.height)
    ctx.saveGState()
    if shadow > 0 { ctx.setShadow(offset: CGSize(width: 0, height: -height * shadow), blur: height * 0.012, color: color(ink, 0.5)) }
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: deg * .pi / 180)
    if flip { ctx.scaleBy(x: -1, y: 1) }
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: -w / 2, y: -height / 2, width: w, height: height))
    ctx.restoreGState()
}

struct Group { let art: String; let cx, cy, h: CGFloat }
struct Layout {
    let name: String
    let W: CGFloat, H: CGFloat
    /// The box every device shows (drawn by --guides).
    let safe: CGRect
    let burst: CGPoint          // sunburst center
    let groups: [Group]
    /// The name's left edge, or its center when `centered`.
    let textX: CGFloat, centered: Bool, nameSize: CGFloat, nameBaseline: CGFloat, tagSize: CGFloat
}

func background(_ L: Layout, in ctx: CGContext) {
    let W = L.W, H = L.H
    let base = CGGradient(colorsSpace: sRGB, colors: [color("3B0FB5"), color(violet), color("C726E8"), color(magenta)] as CFArray, locations: [0, 0.38, 0.72, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Sunburst: alternate wedges lit from the center, then a warm glow on top.
    let c = L.burst, R = hypot(W, H)
    let wedges = 28
    ctx.saveGState()
    let path = CGMutablePath()
    for i in 0..<wedges where i % 2 == 0 {
        let a0 = CGFloat(i) / CGFloat(wedges) * 2 * .pi + 0.07, a1 = CGFloat(i + 1) / CGFloat(wedges) * 2 * .pi + 0.07
        path.move(to: c)
        path.addLine(to: CGPoint(x: c.x + R * cos(a0), y: c.y + R * sin(a0)))
        path.addLine(to: CGPoint(x: c.x + R * cos(a1), y: c.y + R * sin(a1)))
        path.closeSubpath()
    }
    ctx.addPath(path)
    ctx.clip()
    let rays = CGGradient(colorsSpace: sRGB, colors: [color(sun, 0.95), color(orange, 0.7), color(magenta, 0.32), color("FFFFFF", 0.07)] as CFArray, locations: [0, 0.22, 0.5, 1])!
    ctx.drawRadialGradient(rays, startCenter: c, startRadius: 0, endCenter: c, endRadius: R * 0.62, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    let glow = CGGradient(colorsSpace: sRGB, colors: [color("FFF3A6", 0.95), color(sun, 0.75), color(orange, 0.45), color(magenta, 0)] as CFArray, locations: [0, 0.2, 0.5, 1])!
    ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: H * 0.62, options: [])
    // Big soft dots, like the screenshots' backgrounds.
    var seed: UInt64 = 20261111
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10_000) / 10_000 }
    for _ in 0..<22 {
        let r = H * (0.04 + 0.11 * rnd())
        let p = CGPoint(x: rnd() * W, y: rnd() * H)
        let far = min(1, hypot(p.x - c.x, p.y - c.y) / (H * 0.9))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: (0.05 + 0.06 * rnd()) * far))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }
    // A little ink toward the corners, so the middle glows.
    let vignette = CGGradient(colorsSpace: sRGB, colors: [color(ink, 0), color(ink, 0.34)] as CFArray, locations: [0.55, 1])!
    ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: 0, endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: R * 0.56, options: [.drawsAfterEndLocation])
}

func compose(_ L: Layout, guides: Bool) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(L.W), height: Int(L.H), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    background(L, in: ctx)
    let nameWidth = textWidth("Pounce", L.nameSize, kern: -0.025), tagWidth = textWidth("one turn at a time", L.tagSize)
    let textLeft = L.centered ? L.textX - max(nameWidth, tagWidth) / 2 : L.textX
    let textBox = CGRect(x: textLeft, y: L.nameBaseline - L.tagSize * 3.1, width: max(nameWidth, tagWidth), height: L.tagSize * 3.1 + L.nameSize * 0.95)
        .insetBy(dx: -L.nameSize * 0.22, dy: -L.nameSize * 0.2)
    // Stars, sparkles and confetti scattered around the art, clear of the text.
    let fx = [sprite("fx-star"), sprite("fx-sparkle"), sprite("fx-confetti")]
    var seed: UInt64 = 77
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10_000) / 10_000 }
    for g in L.groups {
        let img = art(g.art), half = g.h * CGFloat(img.width) / CGFloat(img.height) / 2
        for i in 0..<22 {
            let a = rnd() * 2 * .pi, d = 0.96 + 0.42 * rnd()
            let p = CGPoint(x: g.cx + (half + g.h * 0.04) * d * cos(a), y: g.cy + (g.h / 2) * d * sin(a))
            let size = L.H * (0.03 + 0.04 * rnd()), rot = rnd() * 70 - 35
            guard !textBox.contains(p), p.y > L.H * 0.05, p.y < L.H * 0.95 else { continue }
            place(fx[i % 3], cx: p.x, cy: p.y, height: size, rotate: rot, shadow: i % 3 == 1 ? 0 : 0.05, in: ctx)
        }
    }
    for g in L.groups { place(art(g.art), cx: g.cx, cy: g.cy, height: g.h, shadow: 0.014, in: ctx) }
    // Name and tagline.
    let tagX = L.centered ? L.textX : L.textX + L.nameSize * 0.035
    drawText("Pounce", size: L.nameSize, fill: color("FFFFFF"), x: L.textX, baseline: L.nameBaseline, centered: L.centered, kern: -0.025, stroke: 0.17, in: ctx)
    drawText("Game night,", size: L.tagSize, fill: color("FFFFFF"), x: tagX, baseline: L.nameBaseline - L.tagSize * 1.62, centered: L.centered, in: ctx)
    drawText("one turn at a time", size: L.tagSize, fill: color(sun), x: tagX, baseline: L.nameBaseline - L.tagSize * 2.74, centered: L.centered, in: ctx)
    if guides {
        ctx.setStrokeColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 0.9)); ctx.setLineWidth(L.H * 0.003)
        ctx.stroke(L.safe)
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ url: URL, _ type: UTType, quality: CGFloat = 0.92) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("can't write \(url.path)") }
    let kb = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) / 1024
    print("\(url.lastPathComponent)  \(image.width)x\(image.height)  \(kb) KB")
}

let layouts: [Layout] = [
    // The header is shown whole only on an iPad in portrait. Device Preview in App Store Connect
    // (2026-11-11): an iPhone trims about 6% off each side and lays its back and share buttons
    // over the top fifth; an iPad in landscape keeps the middle 70% of the height, an unfolded
    // iPhone Duo in landscape the middle 61%, both with toolbar buttons along the top of that.
    // So the name, tagline and cats stay inside the middle band.
    Layout(name: "header", W: 3840, H: 1646, safe: CGRect(x: 330, y: 340, width: 3180, height: 960),
           burst: CGPoint(x: 2930, y: 840),
           groups: [Group(art: "store-hero", cx: 2950, cy: 823, h: 1040)],
           textX: 520, centered: false, nameSize: 440, nameBaseline: 849, tagSize: 160),
    Layout(name: "search", W: 3840, H: 2560, safe: CGRect(x: 0, y: 0, width: 3840, height: 2560),
           burst: CGPoint(x: 2940, y: 1300),
           groups: [Group(art: "store-hero", cx: 2990, cy: 1280, h: 1900)],
           textX: 190, centered: false, nameSize: 530, nameBaseline: 1390, tagSize: 196),
]

var artCache: [String: CGImage] = [:]
/// A cutout from Art/store by name.
func art(_ name: String) -> CGImage {
    if let i = artCache[name] { return i }
    let i = load(root.appendingPathComponent("Art/store/\(name).png"))
    artCache[name] = i
    return i
}
let outDir = root.appendingPathComponent("AppStore/creative")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let guides = CommandLine.arguments.contains("--guides")
let only = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
for L in layouts where only.isEmpty || only.contains(L.name) {
    let image = compose(L, guides: guides)
    let stem = "\(L.name)\(guides ? "-guides" : "")"
    // A PNG of the search results image passes 10 MB, so it goes out as a JPEG, which the spec
    // also takes.
    if L.name == "search" { write(image, outDir.appendingPathComponent("\(stem).jpg"), .jpeg, quality: 0.95) }
    else { write(image, outDir.appendingPathComponent("\(stem).png"), .png) }
}
