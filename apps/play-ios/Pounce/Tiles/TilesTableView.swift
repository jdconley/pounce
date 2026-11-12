import PounceKit
import SpriteKit
import SwiftUI

/// Hosts the tile game's scene in one `SKView`, like `TableView` does Cat Tower's: 60 fps cap,
/// the director controls `isPaused`. It adds the rug's pinch and double tap (tile game spec
/// §5.7) and the swipe home from the left edge.
struct TilesTableView: UIViewRepresentable {
    let scene: TilesScene

    func makeUIView(context: Context) -> TilesSKView {
        let view = TilesSKView(frame: .zero)
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
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinched))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped))
        double.numberOfTapsRequired = 2
        double.cancelsTouchesInView = false
        double.delaysTouchesEnded = false
        double.delegate = context.coordinator
        view.addGestureRecognizer(double)
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ view: TilesSKView, context: Context) {
        if view.scene !== scene {
            view.presentScene(scene)
            scene.director.view = view
        }
    }

    static func dismantleUIView(_ view: TilesSKView, coordinator: Coordinator) {
        (view.scene as? TilesScene)?.director.view = nil
        view.presentScene(nil)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private func scene(_ recognizer: UIGestureRecognizer) -> TilesScene? {
            (recognizer.view as? SKView)?.scene as? TilesScene
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let scene = scene(recognizer) else { return false }
            if recognizer is UIScreenEdgePanGestureRecognizer { return scene.allowsSwipeHome }
            if recognizer is UITapGestureRecognizer, let view = recognizer.view {
                // Only on the rug's own ground: a double tap on a set is two taps on the set.
                return scene.isOpenRug(scene.convertPoint(fromView: recognizer.location(in: view)))
            }
            return true
        }

        @objc func swiped(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view else { return }
            let moved = recognizer.translation(in: view)
            let speed = recognizer.velocity(in: view)
            guard moved.x > abs(moved.y), moved.x >= TableView.Coordinator.distance || (moved.x >= 24 && speed.x >= TableView.Coordinator.speed) else { return }
            Haptics.shared.tick()
            scene(recognizer)?.onSwipeHome()
        }

        @objc func pinched(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else { return }
            scene(recognizer)?.pinch(scale: recognizer.scale, began: recognizer.state == .began)
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view, let scene = scene(recognizer) else { return }
            scene.doubleTap(at: scene.convertPoint(fromView: recognizer.location(in: view)))
        }
    }
}

/// Forwards safe-area and text size changes to the scene and exposes its accessibility elements.
final class TilesSKView: SKView {
    private var tilesScene: TilesScene? { scene as? TilesScene }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        tilesScene?.safeInsets = safeAreaInsets
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            tilesScene?.redraw()
        }
    }

    override var isAccessibilityElement: Bool {
        get { false }
        set {}
    }

    override var accessibilityElements: [Any]? {
        get { tilesScene?.accessibilityElements(in: self) }
        set {}
    }
}

extension TilesScene {
    /// A point on the rug with no set under it (where a double tap zooms).
    func isOpenRug(_ point: CGPoint) -> Bool {
        guard let layout, let flow, loupe == nil, selection.isEmpty, layout.rugArt.contains(point) else { return false }
        return flow.set(at: rugPoint(point), slop: 5) == nil && !flow.newSlot.contains(rugPoint(point))
    }
}
