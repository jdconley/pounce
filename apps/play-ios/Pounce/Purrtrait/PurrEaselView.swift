import PounceKit
import QuartzCore
import SwiftUI
import UIKit

/// Purrtrait's easel (spec §7): one view for the drawer's canvas on iPhone and iPad and the TV's
/// easel. Not PencilKit, not SpriteKit: layers.
///
/// - The finished strokes are one bitmap (`InkRaster`, drawn off the main thread), so a frame
///   costs the same however much is on the easel.
/// - The stroke in progress is a live `CAShapeLayer` path, rebuilt when its points change.
/// - A stroke that just finished stays a shape layer of its own until the bitmap that holds it
///   comes back, so nothing blinks while the raster works.
/// - An undo, a clear or a new size draws the bitmap again from the strokes.
///
/// The owner keeps the `InkDrawing` and hands it over with what changed (`show(_:change:)`).
@MainActor
class PurrEaselView: UIView {
    private let bitmap = CALayer()
    private let live = CAShapeLayer()
    /// Strokes finished and not yet in the bitmap, by id.
    private var settling: [Int: CAShapeLayer] = [:]
    private let raster = InkRaster()
    /// Raster jobs run one after another, in the order they were asked for.
    private var lastJob: Task<Void, Never>?
    private var generation = 0
    /// Frames older than the last full redraw asked for are stale.
    private var baseGeneration = 0
    private var shownGeneration = 0
    private(set) var drawing = InkDrawing()
    /// Display-only points after the live stroke's end (the drawer's predicted touches).
    private var preview: [InkPoint] = []
    private var rasterWidth = 0

    /// Points per grid unit.
    var unit: CGFloat { bounds.width / CGFloat(InkGrid.width) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(cgColor: InkRender.paper)
        isOpaque = true
        layer.masksToBounds = true
        bitmap.contentsGravity = .resize
        bitmap.isOpaque = true
        bitmap.backgroundColor = InkRender.paper
        layer.addSublayer(bitmap)
        for l in [live] {
            l.fillColor = nil
            l.lineCap = .round
            l.lineJoin = .round
            layer.addSublayer(l)
        }
        // The live stroke changes every frame a finger moves: no implicit animations on it.
        live.actions = ["path": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull()]
        bitmap.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bitmap.frame = bounds
        live.frame = bounds
        for l in settling.values { l.frame = bounds }
        CATransaction.commit()
        let width = Int((bounds.width * contentScale).rounded())
        guard width > 0, width != rasterWidth else { return }
        rasterWidth = width
        redrawAll()
    }

    private var contentScale: CGFloat {
        #if os(iOS)
        window?.screen.scale ?? traitCollection.displayScale
        #else
        traitCollection.displayScale
        #endif
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let scale = max(contentScale, 1)
        bitmap.contentsScale = scale
        live.contentsScale = scale
        setNeedsLayout()
    }

    // MARK: showing a drawing

    /// The stroke being drawn: the newest one, until it's finished (a newer one starts, the
    /// drawer's finger lifts) or undone. Every other stroke is in the bitmap or settling into it.
    private(set) var liveID: Int?

    /// The drawing is now `next`; `change` says how it got there from the last one shown.
    func show(_ next: InkDrawing, change: InkDrawing.Change) {
        drawing = next
        switch change {
        case .none:
            return
        case .extended:
            drawLive()
        case .started:
            // The stroke before the new one is finished: it settles into the bitmap.
            finishLive()
            liveID = next.strokes.last?.id
            drawLive()
        case .removedLive:
            liveID = nil
            drawLive()
        case .finishedChanged:
            for (id, layer) in settling where !next.strokes.contains(where: { $0.id == id }) {
                layer.removeFromSuperlayer()
                settling[id] = nil
            }
            drawLive()
            redrawAll()
        case .cleared:
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bitmap.contents = nil
            for l in settling.values { l.removeFromSuperlayer() }
            settling = [:]
            CATransaction.commit()
            liveID = nil
            drawLive()
            redrawAll()
        }
    }

    /// The live stroke is done (the drawer's finger lifted): into the bitmap with it.
    func finishLive() {
        defer {
            liveID = nil
            preview = []
            drawLive()
        }
        guard let id = liveID, let stroke = drawing.strokes.first(where: { $0.id == id }) else { return }
        settle(stroke)
    }

    /// Shows `drawing` from blank: a new turn, a TV that came back, a resize. Its newest stroke
    /// is live (a TV joining mid-stroke keeps adding to it).
    func reset(_ next: InkDrawing, live: Bool = true) {
        drawing = next
        liveID = live ? next.strokes.last?.id : nil
        preview = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in settling.values { l.removeFromSuperlayer() }
        settling = [:]
        if next.isEmpty { bitmap.contents = nil }
        CATransaction.commit()
        drawLive()
        redrawAll()
    }

    /// Points to draw past the live stroke's end until the real ones come (predicted touches).
    func preview(_ points: [InkPoint]) {
        guard points != preview else { return }
        preview = points
        drawLive()
    }

    private func drawLive() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let id = liveID, let stroke = drawing.strokes.last(where: { $0.id == id }), bounds.width > 0 else {
            live.path = nil
            return
        }
        live.path = InkRender.path(stroke.points + preview, scale: unit)
        live.strokeColor = InkRender.color(stroke.color)
        live.lineWidth = InkRender.lineWidth(stroke.width, scale: unit)
    }

    /// A finished stroke: a layer of its own until the bitmap has it.
    private func settle(_ stroke: InkDrawing.Stroke) {
        guard bounds.width > 0 else { return }
        let l = CAShapeLayer()
        l.frame = bounds
        l.contentsScale = live.contentsScale
        l.fillColor = nil
        l.lineCap = .round
        l.lineJoin = .round
        l.actions = ["path": NSNull(), "opacity": NSNull()]
        l.path = InkRender.path(stroke.points, scale: unit)
        l.strokeColor = InkRender.color(stroke.color)
        l.lineWidth = InkRender.lineWidth(stroke.width, scale: unit)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.insertSublayer(l, below: live)
        CATransaction.commit()
        settling[stroke.id]?.removeFromSuperlayer()
        settling[stroke.id] = l
        let ids = [stroke.id]
        job { raster, gen in await raster.add([stroke], generation: gen) } done: { [weak self] in self?.settled(ids) }
    }

    /// Every finished stroke into a fresh bitmap.
    private func redrawAll() {
        guard rasterWidth > 0 else { return }
        let strokes = drawing.strokes.filter { $0.id != liveID }
        let width = rasterWidth
        let ids = strokes.map(\.id)
        // Shapes for the strokes still settling are drawn again at the new scale meanwhile.
        for (id, l) in settling {
            guard let s = drawing.strokes.first(where: { $0.id == id }) else { continue }
            l.path = InkRender.path(s.points, scale: unit)
            l.lineWidth = InkRender.lineWidth(s.width, scale: unit)
        }
        drawLive()
        job(full: true) { raster, gen in await raster.redraw(strokes, pixelWidth: width, generation: gen) } done: { [weak self] in
            self?.settled(ids)
        }
    }

    private func settled(_ ids: [Int]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in ids {
            settling[id]?.removeFromSuperlayer()
            settling[id] = nil
        }
        CATransaction.commit()
    }

    /// Runs a raster job after the ones before it, then shows its image unless a later full
    /// redraw has been asked for since.
    private func job(full: Bool = false, _ work: @escaping @Sendable (InkRaster, Int) async -> InkRaster.Frame,
                     done: @escaping @MainActor () -> Void) {
        generation += 1
        let gen = generation
        if full { baseGeneration = gen }
        let previous = lastJob
        let raster = raster
        lastJob = Task { [weak self] in
            await previous?.value
            let frame = await work(raster, gen)
            guard let self, frame.generation >= self.baseGeneration, frame.generation > self.shownGeneration else { return }
            self.shownGeneration = frame.generation
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.bitmap.contents = frame.image
            CATransaction.commit()
            done()
        }
    }

    /// The bitmap's last image and every raster job asked for has finished (tests).
    func settle() async {
        while let job = lastJob {
            await job.value
            if lastJob == job { break }
        }
    }

    var bitmapImage: CGImage? {
        guard let contents = bitmap.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return nil }
        return (contents as! CGImage)
    }

    var settlingCount: Int { settling.count }
}

/// The TV's easel, and the drawer's after a reconnect: a drawing kept from a room's `InkFeed`.
/// A whole drawing (a new turn, `inkSync`) is built off the main thread; ops that arrive
/// meanwhile wait and go on after it.
@MainActor
final class PurrInkFollower {
    private weak var view: PurrEaselView?
    private let feed: InkFeed
    private var drawing = InkDrawing()
    private var building = false
    private var waiting: [InkOp] = []
    private var buildTask: Task<Void, Never>?

    init(feed: InkFeed, view: PurrEaselView) {
        self.feed = feed
        self.view = view
        feed.onChange = { [weak self] change in self?.changed(change) }
        rebuild()
    }

    func stop() {
        feed.onChange = nil
        buildTask?.cancel()
    }

    private func changed(_ change: InkFeed.Change) {
        switch change {
        case .reset: rebuild()
        case .ops(let ops):
            if building {
                waiting.append(contentsOf: ops)
            } else {
                apply(ops)
            }
        case .resend: break
        }
    }

    private func apply(_ ops: [InkOp]) {
        for op in ops {
            let change = drawing.apply(op)
            view?.show(drawing, change: change)
        }
    }

    private func rebuild() {
        let ops = feed.compacted
        waiting = []
        guard !ops.isEmpty else {
            building = false
            drawing = InkDrawing()
            view?.reset(drawing)
            return
        }
        building = true
        buildTask?.cancel()
        buildTask = Task { [weak self] in
            let built = await Self.build(ops)
            guard let self, !Task.isCancelled else { return }
            self.drawing = built
            self.building = false
            self.view?.reset(built)
            let rest = self.waiting
            self.waiting = []
            self.apply(rest)
        }
    }

    @concurrent
    private static func build(_ ops: [InkOp]) async -> InkDrawing { InkDrawing(ops: ops) }
}
