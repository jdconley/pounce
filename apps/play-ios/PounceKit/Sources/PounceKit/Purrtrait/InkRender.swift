import CoreGraphics
import Foundation

/// How a stroke looks, the same on every device (spec §7): quadratic curves through the midpoints
/// of its points, round caps and joins, the width in grid units scaled with the easel.
public enum InkRender {
    /// The colour for colour number `n` (an unknown number reads as black).
    public static func color(_ n: Int) -> CGColor {
        let c = InkGrid.rgb.indices.contains(n) ? InkGrid.rgb[n] : InkGrid.rgb[0]
        return CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    /// The easel's paper.
    public static let paper = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    /// The stroke's line through `points` (grid units) at `scale` points per unit: a straight
    /// line to the first midpoint, a quadratic curve through each point to the next midpoint, and
    /// a straight line to the last point. One point is a zero-length line, which a round cap draws
    /// as a dot.
    public static func path(_ points: [InkPoint], scale: CGFloat) -> CGPath {
        let path = CGMutablePath()
        add(points, scale: scale, to: path)
        return path
    }

    public static func add(_ points: [InkPoint], scale: CGFloat, to path: CGMutablePath) {
        guard let first = points.first else { return }
        func pt(_ p: InkPoint) -> CGPoint { CGPoint(x: CGFloat(p.x) * scale, y: CGFloat(p.y) * scale) }
        path.move(to: pt(first))
        guard points.count > 1 else {
            path.addLine(to: pt(first))
            return
        }
        guard points.count > 2 else {
            path.addLine(to: pt(points[1]))
            return
        }
        func mid(_ a: InkPoint, _ b: InkPoint) -> CGPoint {
            CGPoint(x: CGFloat(a.x + b.x) * scale / 2, y: CGFloat(a.y + b.y) * scale / 2)
        }
        path.addLine(to: mid(points[0], points[1]))
        for i in 1..<(points.count - 1) {
            path.addQuadCurve(to: mid(points[i], points[i + 1]), control: pt(points[i]))
        }
        path.addLine(to: pt(points[points.count - 1]))
    }

    /// The line width in points for width number `width` at `scale` points per grid unit.
    public static func lineWidth(_ width: Int, scale: CGFloat) -> CGFloat { CGFloat(InkGrid.size(width)) * scale }

    /// Draws `strokes` into `context`, whose user space is `scale` points per grid unit with the
    /// origin at the easel's top left (flip it first for a bottom-left context).
    public static func draw(_ strokes: some Sequence<InkDrawing.Stroke>, in context: CGContext, scale: CGFloat) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for s in strokes {
            context.beginPath()
            context.addPath(path(s.points, scale: scale))
            context.setStrokeColor(color(s.color))
            context.setLineWidth(lineWidth(s.width, scale: scale))
            context.strokePath()
        }
    }
}

/// The finished strokes of an easel as one bitmap, drawn off the main thread (spec §7): a new
/// finished stroke is drawn on top, and an undo, a clear or a new size draws the whole picture
/// again. Each answer is an image and the generation it shows, so the screen drops a late one.
public actor InkRaster {
    /// The bitmap's size in pixels, and pixels per grid unit.
    private var pixels: CGSize = .zero
    private var scale: CGFloat = 1
    private var context: CGContext?
    private var generation = 0

    public init() {}

    public struct Frame: @unchecked Sendable {
        public let image: CGImage?
        /// Goes up with every job; a frame older than the last one shown is dropped.
        public let generation: Int
    }

    /// Starts over at `pixelWidth` pixels across (the height follows the easel's 3:4) with
    /// `strokes` on it.
    public func redraw(_ strokes: [InkDrawing.Stroke], pixelWidth: Int, generation: Int) -> Frame {
        let width = max(pixelWidth, 1)
        let height = max(width * InkGrid.height / InkGrid.width, 1)
        if context == nil || Int(pixels.width) != width || Int(pixels.height) != height {
            context = Self.makeContext(width: width, height: height)
            pixels = CGSize(width: width, height: height)
            scale = CGFloat(width) / CGFloat(InkGrid.width)
        }
        guard let context else { return Frame(image: nil, generation: generation) }
        context.setFillColor(InkRender.paper)
        context.fill(CGRect(origin: .zero, size: pixels))
        InkRender.draw(strokes, in: context, scale: scale)
        self.generation = generation
        return Frame(image: context.makeImage(), generation: generation)
    }

    /// Draws `strokes` over what's there.
    public func add(_ strokes: [InkDrawing.Stroke], generation: Int) -> Frame {
        guard let context else { return Frame(image: nil, generation: generation) }
        InkRender.draw(strokes, in: context, scale: scale)
        self.generation = generation
        return Frame(image: context.makeImage(), generation: generation)
    }

    /// A bitmap context with the grid's top left at its origin.
    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        return context
    }
}
