import PounceKit
import QuartzCore
import SwiftUI
import UIKit

/// The drawer's easel on iPhone and iPad: the easel view with a finger (or an Apple Pencil, as a
/// finger: pressure is ignored) drawing on it. Every coalesced touch goes to the pen, and the line
/// is drawn on the frame it happens (spec §7). While a finger is down, a display link asks for the
/// screen's top rate (120 on ProMotion) and sends the ink when it's due.
@MainActor
final class PurrCanvasView: PurrEaselView {
    var model: PurrDrawModel? {
        didSet {
            guard model !== oldValue else { return }
            reset(model?.drawing ?? InkDrawing(), live: false)
        }
    }
    /// A stroke began (the tips learn the easel).
    var onStroke: () -> Void = {}

    private var finger: UITouch?
    private var link: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
        accessibilityLabel = String(localized: "Easel", comment: "Purrtrait: VoiceOver, the drawing area")
        accessibilityTraits = [.allowsDirectInteraction]
    }

    private func grid(_ p: CGPoint) -> InkPoint {
        let u = max(unit, 0.0001)
        return InkPoint(Int((p.x / u).rounded()), Int((p.y / u).rounded()))
    }

    // MARK: touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard finger == nil, let touch = touches.first, let model else { return }
        let work = FrameWork("purr.touch"); defer { work.end() }
        guard model.down(grid(touch.location(in: self))) else { return }
        finger = touch
        show(model.drawing, change: .started)
        startLink()
        onStroke()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let finger, touches.contains(finger), let model else { return }
        let work = FrameWork("purr.touch"); defer { work.end() }
        let samples = event?.coalescedTouches(for: finger) ?? [finger]
        if model.move(samples.map { grid($0.location(in: self)) }) {
            show(model.drawing, change: .extended)
        }
        let ahead = event?.predictedTouches(for: finger) ?? []
        preview(ahead.map { grid($0.location(in: self)) })
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let finger, touches.contains(finger) else { return }
        end()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let finger, touches.contains(finger) else { return }
        end()
    }

    /// The finger lifted, the touch was cancelled, or the app is going away: the stroke ends.
    func end() {
        finger = nil
        guard let model else { return }
        model.up()
        finishLive()
        if !model.needsTicks { stopLink() }
    }

    /// The model's picture changed without a touch (undo, clear, a resend): draw it again.
    func refresh(change: InkDrawing.Change) {
        guard let model else { return }
        if change == .cleared || change == .finishedChanged || change == .removedLive {
            reset(model.drawing, live: false)
        } else {
            show(model.drawing, change: change)
        }
        if model.needsTicks { startLink() }
    }

    // MARK: the display link

    private func startLink() {
        guard link == nil else { return }
        let link = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick))
        // The top rate while a finger draws (120 on ProMotion; Info.plist's
        // CADisableMinimumFrameDurationOnPhone allows it on iPhone).
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    fileprivate func tick() {
        guard let model else { return stopLink() }
        model.tick()
        if finger == nil, !model.needsTicks { stopLink() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            end()
            stopLink()
        }
    }

    /// Breaks the display link's hold on the view.
    @MainActor private final class Ticker: NSObject {
        weak var view: PurrCanvasView?
        init(_ view: PurrCanvasView) { self.view = view }
        @objc func tick() { view?.tick() }
    }

    #if DEBUG
    /// `-autoplay` (the frame-rate gate): a scripted finger drawing loops through the same code a
    /// touch runs, `samples` points a frame, for as long as the canvas is up.
    func autoplayStep(_ t: Double) {
        guard let model else { return }
        let w = Double(InkGrid.width), h = Double(InkGrid.height)
        func at(_ s: Double) -> InkPoint {
            InkPoint(Int(w * (0.5 + 0.38 * sin(s * 1.7))), Int(h * (0.5 + 0.38 * sin(s * 2.3 + 0.6))))
        }
        let phase = t.truncatingRemainder(dividingBy: 2.2)
        if phase > 2.0 {
            if model.pen.isDrawing {
                model.up()
                finishLive()
            }
            if model.drawing.strokes.count > 40 {
                model.clear()
                reset(model.drawing, live: false)
            }
            return
        }
        if !model.pen.isDrawing {
            _ = model.down(at(t))
            show(model.drawing, change: .started)
            startLink()
            return
        }
        // Four coalesced samples a frame, as a 240 Hz digitizer gives a 60 Hz frame.
        let samples = (1...4).map { at(t + Double($0) * 0.004) }
        if model.move(samples) { show(model.drawing, change: .extended) }
    }
    #endif
}

/// The canvas in SwiftUI.
struct PurrCanvas: UIViewRepresentable {
    let model: PurrDrawModel
    var onStroke: () -> Void = {}
    /// Bumped by the tools: the picture changed without a touch.
    var revision: Revision = .init()

    struct Revision: Equatable {
        var serial = 0
        var change: InkDrawing.Change = .none
    }

    func makeUIView(context: Context) -> PurrCanvasView {
        let view = PurrCanvasView(frame: .zero)
        view.model = model
        view.onStroke = onStroke
        view.accessibilityIdentifier = "purr.easel"
        return view
    }

    func updateUIView(_ view: PurrCanvasView, context: Context) {
        view.model = model
        view.onStroke = onStroke
        if context.coordinator.serial != revision.serial {
            context.coordinator.serial = revision.serial
            view.refresh(change: revision.change)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var serial = 0
    }
}
