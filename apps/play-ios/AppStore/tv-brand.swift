// Composes the Apple TV brand art in PounceTV/Resources/TVAssets.xcassets: the layered App Icon
// (home screen and App Store) and the two Top Shelf images, from the app's own art. The look is
// the iPhone icon's and the App Store header's: the living room from home-bg under a sunburst,
// the cats, and the name in the app's type (SF Rounded Black with the ink outline, the Loud Toy
// colors from Palette.swift).
//   swift AppStore/tv-brand.swift                 # from apps/play-ios; rewrites the brand assets
//   swift AppStore/tv-brand.swift --preview <dir> # also writes each icon flattened, to look at
// Sizes are Apple's tvOS "App icons" and "Top Shelf" specs: icon 400x240 pt (@1x, @2x) with 2 to
// 5 layers and an opaque back layer; App Store icon 1280x768; Top Shelf 1920x720 and Top Shelf
// Wide 2320x720 (@1x, @2x).
//
// The icon has three layers, so the parallax reads as depth: the room (back, blurred like a far
// wall), the cats cheering (middle), and the name with a few stars (front). The cats stand behind
// the name, as on a game's title card.
import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    let v = UInt32(hex, radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}
// Palette.swift
let ink = "1B0B3A", violet = "7B2FFF", magenta = "FF2E9A", orange = "FF8A00", sun = "FFD21F", night = "2A0F5C"

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Pounce/Resources/Assets.xcassets")
let out = root.appendingPathComponent("PounceTV/Resources/TVAssets.xcassets")

func load(_ url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("can't read \(url.path)")
    }
    return img
}
var spriteCache: [String: CGImage] = [:]
/// A catalog sprite by name, at @3x.
func sprite(_ name: String) -> CGImage {
    if let i = spriteCache[name] { return i }
    let e = FileManager.default.enumerator(at: catalog, includingPropertiesForKeys: nil)!
    for case let u as URL in e where u.deletingLastPathComponent().lastPathComponent == "\(name).imageset" && u.lastPathComponent.hasSuffix("@3x.png") {
        let i = load(u)
        spriteCache[name] = i
        return i
    }
    fatalError("no sprite \(name)")
}
let hero = load(root.appendingPathComponent("Art/store/store-hero.png"))

func rounded(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .black)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size)!
}
func textWidth(_ text: String, _ size: CGFloat, kern: CGFloat) -> CGFloat {
    let l = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: rounded(size), .kern: size * kern]))
    return CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
}
/// One line with the app's chunky ink outline (OutlinedText): a hard ink drop, a fat stroke pass
/// that sits a little low, then the fill on top. Centered on `cx` unless `left`.
func drawText(_ text: String, size: CGFloat, fill: CGColor, cx: CGFloat, baseline: CGFloat, left: Bool = false,
              kern: CGFloat = -0.01, stroke: CGFloat = 0.2, drop: CGFloat = 0, in ctx: CGContext) {
    let font = rounded(size)
    func line(_ c: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: size * kern, .foregroundColor: NSColor(cgColor: c)!]))
    }
    let plain = line(fill)
    let x = left ? cx : cx - CGFloat(CTLineGetTypographicBounds(plain, nil, nil, nil)) / 2
    ctx.saveGState()
    ctx.setLineJoin(.round)
    ctx.setLineWidth(size * stroke)
    ctx.setStrokeColor(color(ink))
    ctx.setTextDrawingMode(.fillStroke)
    if drop > 0 {
        ctx.textPosition = CGPoint(x: x, y: baseline - size * drop)
        CTLineDraw(line(color(ink)), ctx)
    }
    ctx.textPosition = CGPoint(x: x, y: baseline - size * 0.05)
    CTLineDraw(line(color(ink)), ctx)
    ctx.restoreGState()
    ctx.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(plain, ctx)
}

/// Draws an image by its center and height (y up), rotated, with a hard toy shadow under it.
func place(_ img: CGImage, cx: CGFloat, cy: CGFloat, height: CGFloat, rotate deg: CGFloat = 0, flip: Bool = false,
           shadow: CGFloat = 0.02, in ctx: CGContext) {
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

func canvas(_ w: Int, _ h: Int, opaque: Bool) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// A Gaussian blur, clamped at the edges so the frame stays opaque.
func blurred(_ img: CGImage, radius: CGFloat) -> CGImage {
    let ci = CIImage(cgImage: img).clampedToExtent().applyingGaussianBlur(sigma: radius)
    let ctx = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])
    return ctx.createCGImage(ci, from: CGRect(x: 0, y: 0, width: img.width, height: img.height), format: .RGBA8, colorSpace: sRGB)!
}

/// The back: the living room from home-bg (window, moon, sofa) filling the frame, washed in the
/// brand's violet to magenta, with the sunburst lit behind `burst` and a little ink in the
/// corners. `focus` is the point of home-bg (0...1, y down) the frame centers on; `zoom` scales
/// past filling the width.
func room(W: CGFloat, H: CGFloat, focus: CGPoint, zoom: CGFloat, burst: CGPoint, blur: CGFloat, rays: CGFloat) -> CGImage {
    let ctx = canvas(Int(W), Int(H), opaque: true)
    let bg = sprite("home-bg")
    let iw = W * zoom, ih = iw * CGFloat(bg.height) / CGFloat(bg.width)
    var y = H / 2 - (1 - focus.y) * ih
    y = min(0, max(H - ih, y))
    ctx.interpolationQuality = .high
    ctx.draw(bg, in: CGRect(x: W / 2 - focus.x * iw, y: y, width: iw, height: ih))
    // The brand wash, so the room reads as Pounce's violet and the cats pop off it.
    let wash = CGGradient(colorsSpace: sRGB, colors: [color("3B0FB5", 0.62), color(violet, 0.5), color("C726E8", 0.42), color(magenta, 0.5)] as CFArray,
                          locations: [0, 0.4, 0.72, 1])!
    ctx.drawLinearGradient(wash, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Sunburst: alternate wedges lit from the burst, then a warm glow on top.
    let R = hypot(W, H), wedges = 28
    ctx.saveGState()
    let path = CGMutablePath()
    for i in 0..<wedges where i % 2 == 0 {
        let a0 = CGFloat(i) / CGFloat(wedges) * 2 * .pi + 0.07, a1 = CGFloat(i + 1) / CGFloat(wedges) * 2 * .pi + 0.07
        path.move(to: burst)
        path.addLine(to: CGPoint(x: burst.x + R * cos(a0), y: burst.y + R * sin(a0)))
        path.addLine(to: CGPoint(x: burst.x + R * cos(a1), y: burst.y + R * sin(a1)))
        path.closeSubpath()
    }
    ctx.addPath(path)
    ctx.clip()
    let rayFill = CGGradient(colorsSpace: sRGB, colors: [color(sun, 0.9 * rays), color(orange, 0.62 * rays), color(magenta, 0.3 * rays), color("FFFFFF", 0.05 * rays)] as CFArray,
                             locations: [0, 0.24, 0.52, 1])!
    ctx.drawRadialGradient(rayFill, startCenter: burst, startRadius: 0, endCenter: burst, endRadius: R * 0.6, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    let glow = CGGradient(colorsSpace: sRGB, colors: [color("FFF3A6", 0.9), color(sun, 0.7), color(orange, 0.4), color(magenta, 0)] as CFArray, locations: [0, 0.2, 0.5, 1])!
    ctx.drawRadialGradient(glow, startCenter: burst, startRadius: 0, endCenter: burst, endRadius: H * 0.6, options: [])
    let vignette = CGGradient(colorsSpace: sRGB, colors: [color(ink, 0), color(ink, 0.45)] as CFArray, locations: [0.5, 1])!
    ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: 0, endCenter: CGPoint(x: W / 2, y: H / 2),
                           endRadius: R * 0.55, options: [.drawsAfterEndLocation])
    let img = ctx.makeImage()!
    return blur > 0 ? blurred(img, radius: blur) : img
}

// MARK: the icon

/// The icon in points, laid out on 400x240 and scaled to `W` pixels wide.
struct IconLayers { let back, middle, front: CGImage }

func icon(width W: CGFloat) -> IconLayers {
    let H = W * 0.6, u = W / 400  // u: one point of the 400x240 layout
    let back = room(W: W, H: H, focus: CGPoint(x: 0.5, y: 0.36), zoom: 1.05, burst: CGPoint(x: W / 2, y: H * 0.62), blur: 2.2 * u, rays: 1)

    // Middle: three cats cheering, the tabby in front, standing behind the name.
    let mid = canvas(Int(W), Int(H), opaque: false)
    place(sprite("cat1-celebrate"), cx: 112 * u, cy: 128 * u, height: 150 * u, rotate: 8, shadow: 0.015, in: mid)
    place(sprite("cat2-celebrate"), cx: 288 * u, cy: 128 * u, height: 150 * u, rotate: -8, shadow: 0.015, in: mid)
    place(sprite("cat0-celebrate"), cx: 200 * u, cy: 138 * u, height: 176 * u, shadow: 0.015, in: mid)

    // Front: the name, big, across the cats' middles, and a few stars and sparkles round it.
    let front = canvas(Int(W), Int(H), opaque: false)
    let size = 80 * u
    place(sprite("fx-star"), cx: 58 * u, cy: 100 * u, height: 32 * u, rotate: -18, shadow: 0.05, in: front)
    place(sprite("fx-star"), cx: 352 * u, cy: 104 * u, height: 28 * u, rotate: 16, shadow: 0.05, in: front)
    place(sprite("fx-sparkle"), cx: 340 * u, cy: 196 * u, height: 30 * u, shadow: 0, in: front)
    place(sprite("fx-sparkle"), cx: 62 * u, cy: 186 * u, height: 22 * u, shadow: 0, in: front)
    drawText("Pounce", size: size, fill: color("FFFFFF"), cx: W / 2, baseline: 38 * u, kern: -0.025, stroke: 0.2, drop: 0.12, in: front)
    return IconLayers(back: back, middle: mid.makeImage()!, front: front.makeImage()!)
}

// MARK: the Top Shelf

/// The Top Shelf: the room and sunburst, the name and tagline on the left, the hero group on the
/// right. `W` x `H` in pixels; the layout is in points on a 720-tall band, with the art kept in the
/// middle 1920 points, which both the plain and the wide image show.
func topShelf(W: CGFloat, H: CGFloat) -> CGImage {
    let u = H / 720, mid = W / 2
    let cats = CGPoint(x: mid + 470 * u, y: 350 * u)
    let back = room(W: W, H: H, focus: CGPoint(x: 0.5, y: 0.38), zoom: 1.0, burst: cats, blur: 3 * u, rays: 1)
    let ctx = canvas(Int(W), Int(H), opaque: true)
    ctx.draw(back, in: CGRect(x: 0, y: 0, width: W, height: H))
    var seed: UInt64 = 1116
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10_000) / 10_000 }
    let fx = [sprite("fx-star"), sprite("fx-sparkle"), sprite("fx-confetti")]
    let heroH = 600 * u, half = heroH * CGFloat(hero.width) / CGFloat(hero.height) / 2
    for i in 0..<20 {
        let a = rnd() * 2 * .pi, d = 1.0 + 0.4 * rnd()
        let p = CGPoint(x: cats.x + (half + 30 * u) * d * cos(a), y: cats.y + (heroH / 2) * d * sin(a))
        guard p.y > 40 * u, p.y < H - 40 * u, p.x > mid + 120 * u else { continue }
        place(fx[i % 3], cx: p.x, cy: p.y, height: (26 + 26 * rnd()) * u, rotate: rnd() * 70 - 35, shadow: i % 3 == 1 ? 0 : 0.05, in: ctx)
    }
    place(hero, cx: cats.x, cy: cats.y, height: heroH, shadow: 0.014, in: ctx)
    let textX = mid - 820 * u, nameBase = 360 * u
    drawText("Pounce", size: 230 * u, fill: color("FFFFFF"), cx: textX, baseline: nameBase, left: true, kern: -0.025, stroke: 0.17, drop: 0.1, in: ctx)
    drawText("Family game night,", size: 84 * u, fill: color("FFFFFF"), cx: textX + 8 * u, baseline: nameBase - 136 * u, left: true, drop: 0.08, in: ctx)
    drawText("every night", size: 84 * u, fill: color(sun), cx: textX + 8 * u, baseline: nameBase - 230 * u, left: true, drop: 0.08, in: ctx)
    return ctx.makeImage()!
}

// MARK: writing the catalog

func writePNG(_ image: CGImage, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("can't write \(url.path)") }
    let kb = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) / 1024
    print("\(url.path.replacingOccurrences(of: out.path + "/", with: ""))  \(image.width)x\(image.height)  \(kb) KB")
}
func writeJSON(_ object: [String: Any], _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! (String(data: data, encoding: .utf8)! + "\n").write(to: url, atomically: true, encoding: .utf8)
}
let info: [String: Any] = ["author": "xcode", "version": 1]

/// An image set of `stem` at the given scales (1x first), images[i] at scale i+1.
func imageSet(_ dir: URL, stem: String, _ images: [CGImage]) {
    var entries: [[String: Any]] = []
    for (i, img) in images.enumerated() {
        let file = i == 0 ? "\(stem).png" : "\(stem)@\(i + 1)x.png"
        writePNG(img, dir.appendingPathComponent(file))
        entries.append(["filename": file, "idiom": "tv", "scale": "\(i + 1)x"])
    }
    writeJSON(["images": entries, "info": info], dir.appendingPathComponent("Contents.json"))
}
/// An image stack, front layer first as Xcode lists them.
func imageStack(_ dir: URL, _ layers: [(String, [CGImage])]) {
    for (name, images) in layers {
        let layer = dir.appendingPathComponent("\(name).imagestacklayer")
        writeJSON(["info": info], layer.appendingPathComponent("Contents.json"))
        imageSet(layer.appendingPathComponent("Content.imageset"), stem: name.lowercased(), images)
    }
    writeJSON(["info": info, "layers": layers.map { ["filename": "\($0.0).imagestacklayer"] }], dir.appendingPathComponent("Contents.json"))
}

let brand = out.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
try? FileManager.default.removeItem(at: brand)
writeJSON(["info": info], out.appendingPathComponent("Contents.json"))

let small1 = icon(width: 400), small2 = icon(width: 800), store = icon(width: 1280)
imageStack(brand.appendingPathComponent("App Icon.imagestack"), [
    ("Front", [small1.front, small2.front]), ("Middle", [small1.middle, small2.middle]), ("Back", [small1.back, small2.back]),
])
imageStack(brand.appendingPathComponent("App Icon - App Store.imagestack"), [
    ("Front", [store.front]), ("Middle", [store.middle]), ("Back", [store.back]),
])
imageSet(brand.appendingPathComponent("Top Shelf Image.imageset"), stem: "top-shelf",
         [topShelf(W: 1920, H: 720), topShelf(W: 3840, H: 1440)])
imageSet(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), stem: "top-shelf-wide",
         [topShelf(W: 2320, H: 720), topShelf(W: 4640, H: 1440)])
writeJSON(["assets": [
    ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
    ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
    ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
], "info": info], brand.appendingPathComponent("Contents.json"))

// The launch screen's color (Info.plist UILaunchScreen) is the iPhone's own LaunchViolet: the TV
// shares Pounce/Resources/Assets.xcassets, so it is not written here.

// --preview <dir>: each icon flattened as the TV draws it at rest, to look at.
if let i = CommandLine.arguments.firstIndex(of: "--preview"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    for (name, l) in [("icon-400", small1), ("icon-800", small2), ("icon-1280", store)] {
        let ctx = canvas(l.back.width, l.back.height, opaque: true)
        let r = CGRect(x: 0, y: 0, width: l.back.width, height: l.back.height)
        for img in [l.back, l.middle, l.front] { ctx.draw(img, in: r) }
        writePNG(ctx.makeImage()!, dir.appendingPathComponent("\(name).png"))
    }
}
