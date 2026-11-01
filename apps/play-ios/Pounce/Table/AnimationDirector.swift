import PounceKit
import SpriteKit

/// Render on demand (spec §9.2): the `SKView` runs only while something animates or a finger
/// is down. Every table motion goes through `run` / `emit`; the bookkeeping is PounceKit's
/// `RenderGate`, which the scene feeds once per frame and which pauses the view once nothing
/// has been busy for `RenderGate.idleDelay` of rendered time. `wake()` unpauses for one-off
/// redraws (a reconcile, a resize).
///
/// Actions run under a key. One that never calls back (its node left the tree) is removed and
/// released after `duration + grace` of *rendered* time, so a paused view never strands an
/// action half way, and a released action can't resume later over a reconcile.
@MainActor
final class AnimationDirector {
    weak var view: SKView? {
        didSet { wake() }
    }

    private struct Pending {
        weak var node: SKNode?
        let key: String
        /// Decorative actions only touch properties reconcile never sets, so they survive it.
        let decorative: Bool
        let finish: () -> Void
    }

    private var gate = RenderGate()
    private var pending: [Int: Pending] = [:]

    /// Frames the scene has updated since launch (DEBUG: `table.frames`).
    private(set) var framesRendered = 0

    init(view: SKView?) {
        self.view = view
    }

    var isIdle: Bool { gate.isIdle }
    /// Actions and emitters in flight.
    var running: Int { gate.running.count }

    /// Unpauses the view; it pauses again once the table has been idle for a moment.
    func wake() {
        gate.wake()
        if let view, view.isPaused { view.isPaused = false }
    }

    func touchBegan() {
        gate.touchBegan()
        wake()
    }

    func touchEnded() {
        gate.touchEnded()
        wake()
    }

    /// Runs `action` on `node` and returns when it finishes, is cancelled by a reconcile, or
    /// times out. `decorative` actions (a pop on a badge) are left alone by `cancelActions`.
    func run(_ action: SKAction, on node: SKNode, decorative: Bool = false) async {
        let token = gate.begin(duration: RenderGate.sanitize(action.duration) / Self.effectiveSpeed(node))
        let key = "director.\(token)"
        wake()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pending[token] = Pending(node: node, key: key, decorative: decorative) { continuation.resume() }
            node.run(.sequence([action, .run { [weak self] in self?.finish(token, removeAction: false) }]), withKey: key)
        }
        wake()
    }

    /// Adds `emitter` at `point` in `parent` for `lifetime` seconds of rendered time.
    func emit(_ emitter: SKEmitterNode, at point: CGPoint, in parent: SKNode, lifetime: TimeInterval) {
        let token = gate.begin(duration: lifetime, grace: 0)
        emitter.position = point
        parent.addChild(emitter)
        pending[token] = Pending(node: emitter, key: "", decorative: true) { emitter.removeFromParent() }
        wake()
    }

    /// A reconcile is about to snap the nodes under `root`: stop every non-decorative director
    /// action there (the snap wins) and release whoever awaits it.
    func cancelActions(under root: SKNode) {
        let tokens = pending.compactMap { token, p -> Int? in
            guard !p.decorative, p.key != "", let node = p.node else { return nil }
            return node === root || node.inParentHierarchy(root) ? token : nil
        }
        for token in tokens { finish(token, removeAction: true) }
    }

    /// Called by the scene once per frame.
    func frame(_ time: TimeInterval) {
        framesRendered += 1
        let result = gate.frame(time)
        for token in result.expired { finish(token, removeAction: true, gateEnded: true) }
        if result.pause { view?.isPaused = true }
    }

    /// The node's speed times every ancestor's (the scene's included), floored so a stopped
    /// node only stretches the timeout instead of dividing by zero.
    private static func effectiveSpeed(_ node: SKNode) -> Double {
        var speed = Double(node.speed)
        var parent = node.parent
        while let p = parent {
            speed *= Double(p.speed)
            parent = p.parent
        }
        return max(speed, 0.01)
    }

    private func finish(_ token: Int, removeAction: Bool, gateEnded: Bool = false) {
        guard let p = pending.removeValue(forKey: token) else { return }
        if !gateEnded { gate.end(token) }
        if removeAction, !p.key.isEmpty { p.node?.removeAction(forKey: p.key) }
        p.finish()
    }
}
