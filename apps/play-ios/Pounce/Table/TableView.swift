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
        cover(view)
        return view
    }

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

    static func dismantleUIView(_ view: TableSKView, coordinator: ()) {
        (view.scene as? TableScene)?.director.view = nil
        view.presentScene(nil)
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
