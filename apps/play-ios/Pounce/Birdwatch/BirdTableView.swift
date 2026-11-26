import PounceKit
import SpriteKit
import SwiftUI

/// Hosts Birdwatch's scene in one `SKView` at the screen's top frame rate, with the swipe home
/// from the left edge on the iPhone.
struct BirdTableView: UIViewRepresentable {
    let scene: BirdScene

    func makeUIView(context: Context) -> BirdSKView {
        let view = BirdSKView(frame: .zero)
        view.runAtTopFrameRate()
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        #if os(iOS)
        view.isMultipleTouchEnabled = false
        let swipe = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swiped))
        swipe.edges = .left
        view.addGestureRecognizer(swipe)
        #endif
        view.backgroundColor = UIColor(Palette.night)
        view.presentScene(scene)
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ view: BirdSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
    }

    static func dismantleUIView(_ view: BirdSKView, coordinator: Coordinator) {
        view.presentScene(nil)
    }

    @MainActor
    final class Coordinator: NSObject {
        #if os(iOS)
        @objc func swiped(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view else { return }
            let moved = recognizer.translation(in: view)
            let speed = recognizer.velocity(in: view)
            guard moved.x > abs(moved.y), moved.x >= TableView.Coordinator.distance || (moved.x >= 24 && speed.x >= TableView.Coordinator.speed) else { return }
            Haptics.shared.tick()
            ((view as? SKView)?.scene as? BirdScene)?.onSwipeHome()
        }
        #endif
    }
}

/// Forwards safe-area and text size changes to the scene and exposes its accessibility elements.
final class BirdSKView: SKView {
    private var birdScene: BirdScene? { scene as? BirdScene }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        runAtTopFrameRate()
        #if DEBUG
        MainThreadWatchdog.shared?.watch(self)
        #endif
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        birdScene?.safeInsets = safeAreaInsets
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            birdScene?.redraw()
        }
    }

    override var isAccessibilityElement: Bool {
        get { false }
        set {}
    }

    override var accessibilityElements: [Any]? {
        get {
            #if DEBUG
            MainThreadWatchdog.shared?.noteQuery()
            #endif
            return birdScene?.accessibilityElements(in: self)
        }
        set {}
    }
}
