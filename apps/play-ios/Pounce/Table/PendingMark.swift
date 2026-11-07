import PounceKit
import SpriteKit

/// A move this phone sent that the server hasn't answered yet: after a moment (a normal answer
/// comes well before), an hourglass sits on the card where it was played, or on the pile drawn
/// from or the lay-down button, and the played card dims. It stays while the move is pending,
/// across a reconnect (`RoomStore.pendingMove`), and goes with the snapshot or refusal that
/// answers it.
extension TableScene {
    /// How long a move may wait before it shows as pending.
    static let pendingAfter: Duration = .milliseconds(700)

    func schedulePendingMark() {
        pendingMarkTask?.cancel()
        pendingMarkTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pendingAfter)
            guard !Task.isCancelled else { return }
            self?.updatePendingMark()
        }
    }

    func hidePendingMark() {
        pendingMarkTask?.cancel()
        pendingMarkTask = nil
        guard pendingMark.parent != nil else { return }
        pendingMark.removeFromParent()
        provisionalNode?.alpha = 1
        director.wake()
    }

    /// Shows or hides the mark for the move in flight now.
    func updatePendingMark() {
        guard lastAct != nil, store.actionInFlight, let (anchor, size) = pendingAnchor() else { return hidePendingMark() }
        let fx = layer(.fx)
        if pendingMark.parent == nil { fx.addChild(pendingMark) }
        let side = max(26, min(size.width * 0.55, 40))
        pendingMark.size = CGSize(width: side, height: side)
        pendingMark.zPosition = 50
        pendingMark.position = CGPoint(x: anchor.x + size.width / 2 - side * 0.3, y: anchor.y + size.height / 2 - side * 0.3)
        provisionalNode?.alpha = 0.6
        pendingMark.accessibilityLabel = String(
            localized: "Sending your move", comment: "VoiceOver: the hourglass on a move the server hasn't answered yet")
        director.wake()
    }

    /// Where the move shows: the played card, else the pile drawn from, the lay-down button or
    /// the card in the hand; in the fx layer's space, with that node's size.
    private func pendingAnchor() -> (CGPoint, CGSize)? {
        let node: SKNode? = if let provisionalNode {
            provisionalNode
        } else {
            switch lastAct {
            case .draw(let pile): pile == .deck ? deck : discard
            case .layDown: trays.layDownButton
            case .card(let card): hand.node(for: card)
            case nil: nil
            }
        }
        guard let node, let parent = node.parent, !node.isHidden else { return nil }
        let frame = node.calculateAccumulatedFrame()
        let center = layer(.fx).convert(CGPoint(x: frame.midX, y: frame.midY), from: parent)
        return (center, frame.size)
    }
}
