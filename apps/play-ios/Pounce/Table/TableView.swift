import SpriteKit
import SwiftUI

/// Hosts the table scene in one `SKView` (not `SpriteView`), so the director controls
/// `isPaused` directly (spec §8). 60 fps cap, sibling order ignored, off-screen nodes culled.
struct TableView: UIViewRepresentable {
    let scene: TableScene
    /// The pass-and-play curtain is over the table: no touches reach the scene and VoiceOver
    /// skips its elements.
    var covered = false

    func makeUIView(context: Context) -> TableSKView {
        let view = TableSKView(frame: .zero)
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        view.isMultipleTouchEnabled = false
        view.backgroundColor = UIColor(Palette.night)
        view.presentScene(scene)
        scene.director.view = view
        let swipe = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swiped))
        swipe.edges = .left
        swipe.delegate = context.coordinator
        view.addGestureRecognizer(swipe)
        cover(view)
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ view: TableSKView, context: Context) {
        if view.scene !== scene {
            view.presentScene(scene)
            scene.director.view = view
        }
        cover(view)
    }

    private func cover(_ view: TableSKView) {
        guard view.accessibilityElementsHidden != covered else { return }
        view.accessibilityElementsHidden = covered
        view.isUserInteractionEnabled = !covered
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    static func dismantleUIView(_ view: TableSKView, coordinator: Coordinator) {
        (view.scene as? TableScene)?.director.view = nil
        view.presentScene(nil)
    }
}

extension TableView {
    /// The swipe in from the left edge that goes Home. It starts only while no card can be under
    /// the finger (`TableScene.allowsSwipeHome`), so it never takes a card drag over; once it
    /// starts, the scene's touch is cancelled.
    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// How far, or how fast, the swipe has to go right to count.
        static let distance: CGFloat = 70
        static let speed: CGFloat = 600

        private func scene(_ recognizer: UIGestureRecognizer) -> TableScene? {
            (recognizer.view as? SKView)?.scene as? TableScene
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            scene(recognizer)?.allowsSwipeHome ?? false
        }

        @objc func swiped(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view else { return }
            let moved = recognizer.translation(in: view)
            let speed = recognizer.velocity(in: view)
            guard moved.x > abs(moved.y), moved.x >= Self.distance || (moved.x >= 24 && speed.x >= Self.speed) else { return }
            Haptics.shared.tick()
            scene(recognizer)?.onSwipeHome()
        }
    }
}

/// Forwards safe-area changes to the scene and exposes the scene's accessibility elements.
final class TableSKView: SKView {
    private var tableScene: TableScene? { scene as? TableScene }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        tableScene?.safeInsets = safeAreaInsets
    }

    override var isAccessibilityElement: Bool {
        get { false }
        set {}
    }

    override var accessibilityElements: [Any]? {
        // Under the curtain the table has no elements at all, not just hidden ones.
        get { accessibilityElementsHidden ? [] : tableScene?.accessibilityElements(in: self) }
        set {}
    }
}
