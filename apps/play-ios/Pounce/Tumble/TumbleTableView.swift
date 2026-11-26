import PounceKit
import SpriteKit
import SwiftUI

/// Hosts Toy Tumble's scene in one `SKView` at the screen's top frame rate. No edge swipe goes
/// home here (unlike the turn-based tables): a drag from the very edge moves the toy, and the
/// stage defers the system's edge gestures while playing (spec §5.3).
struct TumbleTableView: UIViewRepresentable {
    let scene: TumbleScene

    func makeUIView(context: Context) -> TumbleSKView {
        let view = TumbleSKView(frame: .zero)
        view.runAtTopFrameRate()
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        #if os(iOS)
        view.isMultipleTouchEnabled = false
        view.isExclusiveTouch = true
        #endif
        view.backgroundColor = UIColor(Palette.night)
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: TumbleSKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
    }

    static func dismantleUIView(_ view: TumbleSKView, coordinator: ()) {
        view.presentScene(nil)
    }
}

/// Forwards safe-area and text size changes to the scene and exposes its accessibility elements.
final class TumbleSKView: SKView {
    private var tumbleScene: TumbleScene? { scene as? TumbleScene }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        runAtTopFrameRate()
        #if DEBUG
        MainThreadWatchdog.shared?.watch(self)
        #endif
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        tumbleScene?.safeInsets = safeAreaInsets
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            tumbleScene?.redraw()
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
            return tumbleScene?.accessibilityElements(in: self)
        }
        set {}
    }
}

extension TumbleScene {
    /// VoiceOver and the UI tests: your box, each other box, and the tray's tricks.
    func accessibilityElements(in view: UIView) -> [UIAccessibilityElement] {
        guard let layout else { return [] }
        func frame(_ r: CGRect) -> CGRect {
            let flipped = CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)
            return view.convert(flipped, to: nil)
        }
        var out: [UIAccessibilityElement] = []
        let room = store.room
        for (seat, node) in boxNodes.sorted(by: { $0.key < $1.key }) {
            let e = UIAccessibilityElement(accessibilityContainer: view)
            let name = room.map { SeatInfo.name($0, seat) } ?? ""
            let box = table.box(seat)
            let height = box.map { Tumble.highest($0) + 1 } ?? 0
            if seat == mySeat {
                e.accessibilityIdentifier = "tumble.box"
                e.accessibilityLabel = String(localized: "Your box", comment: "Toy Tumble VoiceOver: this player's own box")
                if let toy = table.local?.toy {
                    e.accessibilityValue = "toy=\(toy.n) rot=\(toy.spot.rot) x=\(toy.spot.x) y=\(toy.spot.y) next=\(table.local?.box.next ?? 0)"
                }
            } else {
                e.accessibilityIdentifier = "tumble.mini.\(seat)"
                e.accessibilityLabel = name
                e.accessibilityValue = table.isOut(seat) ? TumbleWords.out : String(localized: "\(height) rows high", comment: "Toy Tumble VoiceOver: how high a box's stack is")
            }
            e.accessibilityTraits = lifted != nil ? .button : []
            e.accessibilityFrameInContainerSpace = view.convert(CGRect(x: node.rect.minX, y: size.height - node.rect.maxY, width: node.rect.width, height: node.rect.height), to: view)
            out.append(e)
        }
        let held = table.local?.box.held ?? []
        for (i, r) in layout.slots.enumerated() where i < held.count {
            let e = UIAccessibilityElement(accessibilityContainer: view)
            e.accessibilityIdentifier = "tumble.trick.\(i)"
            e.accessibilityLabel = TumbleWords.trick(held[i])
            e.accessibilityTraits = lifted == i ? [.button, .selected] : .button
            e.accessibilityFrameInContainerSpace = CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)
            out.append(e)
        }
        if !menuButton.isHidden {
            let e = UIAccessibilityElement(accessibilityContainer: view)
            e.accessibilityIdentifier = "tumble.menu"
            e.accessibilityLabel = String(localized: "Menu", comment: "Toy Tumble VoiceOver: the paw menu")
            e.accessibilityTraits = .button
            let m = menuButton.frame
            e.accessibilityFrameInContainerSpace = CGRect(x: m.minX, y: size.height - m.maxY, width: m.width, height: m.height)
            out.append(e)
        }
        _ = frame
        return out
    }
}
