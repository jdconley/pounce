import CoreGraphics
import Foundation
import Testing
@testable import PounceKit

@Suite struct InkCodecTests {
    private func roundTrip(_ ops: [InkOp]) throws -> [InkOp] {
        let data = try JSONEncoder().encode(ops)
        return try JSONDecoder().decode([InkOp].self, from: data)
    }

    @Test func opsRoundTripThroughJSON() throws {
        let ops: [InkOp] = [
            .stroke(id: 0, color: 3, width: 2, start: InkPoint(10, 20), deltas: [InkPoint(-3, 4), InkPoint(768, -768)]),
            .stroke(id: 1, color: 8, width: 0, start: InkPoint(767, 1023), deltas: []),
            .extend(id: 1, deltas: [InkPoint(0, -5)]),
            .undo(id: 0), .clear,
        ]
        #expect(try roundTrip(ops) == ops)
        #expect(String(decoding: try JSONEncoder().encode(ops[3]), as: UTF8.self) == #"["u",0]"#)
        #expect(String(decoding: try JSONEncoder().encode(InkOp.clear), as: UTF8.self) == #"["c"]"#)
    }

    @Test func compactMatchesTheServerOnStrokeStrokeUndoClearStroke() {
        let a = InkOp.stroke(id: 0, color: 0, width: 1, start: InkPoint(1, 1), deltas: [])
        let b = InkOp.stroke(id: 1, color: 1, width: 1, start: InkPoint(2, 2), deltas: [])
        let c = InkOp.stroke(id: 2, color: 2, width: 1, start: InkPoint(3, 3), deltas: [InkPoint(4, 4)])
        #expect(InkCodec.compact([a, b, .undo(id: 1), .clear, c]) == [c])
        #expect(InkCodec.compact([a, .extend(id: 0, deltas: [InkPoint(1, 0)]), b, .undo(id: 1)]) == [a, .extend(id: 0, deltas: [InkPoint(1, 0)])])
        #expect(InkCodec.compact([a, .clear]) == [])
    }

    @Test func pointsUnderTwoUnitsAreDropped() {
        let kept = InkCodec.filter([InkPoint(0, 0), InkPoint(1, 1), InkPoint(2, 0), InkPoint(3, 3), InkPoint(3, 4)], after: nil)
        #expect(kept == [InkPoint(0, 0), InkPoint(2, 0), InkPoint(3, 3)])
        #expect(InkCodec.filter([InkPoint(1, 0)], after: InkPoint(0, 0)).isEmpty)
    }

    @Test func simplifyKeepsCornersAndDropsTheStraight() {
        let line = (0...20).map { InkPoint($0 * 5, 0) }
        #expect(InkCodec.simplify(line) == [InkPoint(0, 0), InkPoint(100, 0)])
        let corner = (0...10).map { InkPoint($0 * 10, 0) } + (1...10).map { InkPoint(100, $0 * 10) }
        #expect(InkCodec.simplify(corner) == [InkPoint(0, 0), InkPoint(100, 0), InkPoint(100, 100)])
        // Within a unit: gone.
        #expect(InkCodec.simplify([InkPoint(0, 0), InkPoint(50, 1), InkPoint(100, 0)]) == [InkPoint(0, 0), InkPoint(100, 0)])
    }

    @Test func bigStepsSplitUnderTheDeltaLimit() {
        let d = InkCodec.deltas(from: InkPoint(0, 0), through: [InkPoint(0, 1023), InkPoint(767, 1023)])
        #expect(d.allSatisfy { abs($0.x) <= 768 && abs($0.y) <= 768 })
        var at = InkPoint(0, 0)
        for step in d { at = at + step }
        #expect(at == InkPoint(767, 1023))
    }

    /// Review focus 1: a fast scribble on a 60 Hz phone comes as coalesced touches, tens of
    /// units apart. Every one is kept, simplified only where it's straight, and the TV's line
    /// ends where the finger did, with no gap.
    @Test func coalescedFastLineStaysWhole() throws {
        var pen = InkPen()
        var clock = Duration.zero
        // A zigzag across the easel in 0.3 s: 240 Hz coalesced samples, 18 frames at 60 Hz.
        var samples: [InkPoint] = []
        for i in 0..<72 {
            let x = 40 + i * 10
            let y = 300 + (i % 8 < 4 ? (i % 4) * 60 : (4 - i % 4) * 60)
            samples.append(InkPoint(min(x, 767), y))
        }
        pen.down(samples[0])
        var sent: [InkOp] = []
        for frame in stride(from: 1, to: samples.count, by: 4) {
            pen.move(Array(samples[frame..<min(frame + 4, samples.count)]))
            clock += .milliseconds(16)
            if let ops = pen.take(now: clock) { sent += ops }
        }
        pen.up()
        clock += .milliseconds(1)
        if let ops = pen.take(now: clock) { sent += ops }
        let tv = InkDrawing(ops: sent)
        let line = try #require(tv.strokes.first)
        #expect(tv.strokes.count == 1)
        #expect(line.points.first == samples.first)
        #expect(line.points.last == samples.last)
        // Every corner of the zigzag survived the simplification.
        let corners = samples.indices.filter { $0 > 0 && $0 < samples.count - 1 && $0 % 4 == 0 }.map { samples[$0] }
        for c in corners { #expect(line.points.contains(c), "corner \(c)") }
        // And no step between kept points is longer than the finger moved between samples.
        let longest = zip(line.points, line.points.dropFirst()).map { InkCodec.distance($0, $1) }.max() ?? 0
        #expect(longest < 400)
    }

    @Test func aBatchStaysUnderEightKilobytes() throws {
        var pen = InkPen()
        pen.down(InkPoint(0, 0))
        // A huge batch: 2 000 points in one go (nobody draws this fast; the limit still holds).
        pen.move((1...2000).map { InkPoint(($0 * 7) % 768, ($0 * 13) % 1024) })
        pen.up()
        let taken = pen.take(now: .seconds(1))
        let ops = try #require(taken)
        for message in InkCodec.chunk(ops) {
            let json = try Codec.encode(ClientMessage.ink(seat: 9, turn: "2:19", ops: message))
            #expect(json.utf8.count < 8192)
        }
        // The pieces draw the same stroke.
        let whole = InkDrawing(ops: InkCodec.chunk(ops).flatMap { $0 })
        #expect(whole == InkDrawing(ops: ops))
    }

    @Test func theDrawingFollowsOps() {
        var d = InkDrawing()
        #expect(d.apply(.stroke(id: 0, color: 1, width: 0, start: InkPoint(10, 10), deltas: [InkPoint(5, 0)])) == .started)
        #expect(d.apply(.extend(id: 0, deltas: [InkPoint(0, 5)])) == .extended)
        #expect(d.strokes[0].points == [InkPoint(10, 10), InkPoint(15, 10), InkPoint(15, 15)])
        #expect(d.apply(.stroke(id: 1, color: 2, width: 1, start: InkPoint(1, 1), deltas: [])) == .started)
        #expect(d.finished.map(\.id) == [0])
        #expect(d.apply(.undo(id: 0)) == .finishedChanged)
        #expect(d.apply(.undo(id: 1)) == .removedLive)
        #expect(d.apply(.undo(id: 7)) == .none)
        #expect(d.isEmpty)
        #expect(d.highestID == 1)
    }

    // MARK: drawing

    @Test func linesAreSmoothedThroughMidpoints() {
        let path = InkRender.path([InkPoint(0, 0), InkPoint(10, 0), InkPoint(10, 10), InkPoint(20, 10)], scale: 1)
        var parts: [String] = []
        path.applyWithBlock { el in
            let e = el.pointee
            switch e.type {
            case .moveToPoint: parts.append("M\(e.points[0].x),\(e.points[0].y)")
            case .addLineToPoint: parts.append("L\(e.points[0].x),\(e.points[0].y)")
            case .addQuadCurveToPoint: parts.append("Q\(e.points[0].x),\(e.points[0].y) \(e.points[1].x),\(e.points[1].y)")
            default: parts.append("?")
            }
        }
        #expect(parts == ["M0.0,0.0", "L5.0,0.0", "Q10.0,0.0 10.0,5.0", "Q10.0,10.0 15.0,10.0", "L20.0,10.0"])
        // One point: a dot (a zero-length line the round cap draws).
        var dot = 0
        InkRender.path([InkPoint(4, 4)], scale: 2).applyWithBlock { _ in dot += 1 }
        #expect(dot == 2)
    }

    @Test func finishedStrokesFlattenIntoTheBitmap() async throws {
        let raster = InkRaster()
        let stroke = InkDrawing.Stroke(id: 0, color: 1, width: 2, points: [InkPoint(100, 512), InkPoint(668, 512)])
        let blank = await raster.redraw([], pixelWidth: 192, generation: 1)
        let drawn = await raster.add([stroke], generation: 2)
        #expect(blank.generation == 1)
        #expect(drawn.generation == 2)
        let image = try #require(drawn.image)
        #expect(image.width == 192)
        #expect(image.height == 256)
        #expect(Self.pixel(image, x: 96, y: 128).r > 200)  // red ink in the middle
        #expect(Self.pixel(image, x: 96, y: 128).g < 120)
        #expect(Self.pixel(image, x: 96, y: 20).g > 240)  // paper above it
    }

    /// Resizing draws the whole picture again from its strokes, at the new size.
    @Test func resizeRedrawsFromTheStrokes() async throws {
        let raster = InkRaster()
        let stroke = InkDrawing.Stroke(id: 0, color: 5, width: 2, points: [InkPoint(384, 100), InkPoint(384, 900)])
        _ = await raster.redraw([stroke], pixelWidth: 96, generation: 1)
        let big = try #require(await raster.redraw([stroke], pixelWidth: 384, generation: 2).image)
        #expect(big.width == 384)
        #expect(Self.pixel(big, x: 192, y: 256).b > 200)
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        // Rows run top to bottom in memory.
        let i = (y * image.width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }
}
