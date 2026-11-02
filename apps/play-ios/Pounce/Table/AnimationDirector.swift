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
    /// Without a view nothing renders, so nothing could ever finish: going nil releases every
    /// waiter (`cancelAll`), and actions started while detached finish at once.
    weak var view: SKView? {
        didSet {
            if view == nil {
                stopFlourishes()
                cancelAll()
            }
            wake()
        }
    }

    /// Idle life (spec §9.2): called every 5–9 s while the table changed in the last
    /// `flourishWindow`; the scene runs a short decorative action (a cat blink) through `run`,
    /// so the view unpauses only for that.
    var flourish: (() -> Void)?
    static let flourishWindow: Duration = .seconds(60)
    static let flourishGap: ClosedRange<Double> = 5...9
    private var lastChange: ContinuousClock.Instant?
    private var flourishTask: Task<Void, Never>?

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
        await runAll([(action, node)], decorative: decorative)
    }

    /// Runs every action on its node at once and returns when the last one is done (finished,
    /// cancelled or timed out), so one intent can move many nodes on one timeline.
    func runAll(_ items: [(SKAction, SKNode)], decorative: Bool = false) async {
        guard !items.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var remaining = items.count
            for (action, node) in items {
                start(action, on: node, decorative: decorative) {
                    remaining -= 1
                    if remaining == 0 { continuation.resume() }
                }
            }
        }
        wake()
    }

    private func start(_ action: SKAction, on node: SKNode, decorative: Bool, finish: @escaping () -> Void) {
        guard view != nil else { return finish() }  // never rendered: don't wait on it
        let token = gate.begin(duration: RenderGate.sanitize(action.duration) / Self.effectiveSpeed(node))
        let key = "director.\(token)"
        pending[token] = Pending(node: node, key: key, decorative: decorative, finish: finish)
        node.run(.sequence([action, .run { [weak self] in self?.finish(token, removeAction: false) }]), withKey: key)
        wake()
    }

    /// Adds `emitter` at `point` in `parent` for `lifetime` seconds of rendered time (at the
    /// parent's speed, like an action), then removes it and calls `onEnd`.
    func emit(
        _ emitter: SKEmitterNode, at point: CGPoint, in parent: SKNode, lifetime: TimeInterval,
        onEnd: (() -> Void)? = nil
    ) {
        guard view != nil else {
            onEnd?()
            return
        }
        let token = gate.begin(duration: lifetime / Self.effectiveSpeed(parent), grace: 0)
        emitter.position = point
        parent.addChild(emitter)
        pending[token] = Pending(node: emitter, key: "", decorative: true) {
            emitter.removeFromParent()
            onEnd?()
        }
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

    /// The view is going away (or already gone): every action and emitter is given up on now.
    /// Awaiters resume, actions are removed, emitters leave and return their particles.
    func cancelAll() {
        let tokens = Set(gate.cancelAll()).union(pending.keys).sorted()
        for token in tokens { finish(token, removeAction: true, gateEnded: true) }
        #if DEBUG
        if !tokens.isEmpty { print("[director] cancelAll released \(tokens.count)") }
        #endif
    }

    // MARK: particle budget (spec §9.2: emitters are counted by the director)

    /// Particles alive in this table's bursts.
    var liveParticles: Int { gate.particles }

    func reserveParticles(_ wanted: Int) -> Int { gate.reserveParticles(wanted) }

    func releaseParticles(_ count: Int) { gate.releaseParticles(count) }

    /// The table just changed (a redraw): idle flourishes run for the next `flourishWindow`.
    func noteChange() {
        lastChange = .now
        guard flourishTask == nil, view != nil else { return }
        flourishTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: Self.flourishGap)))
                guard let self, !Task.isCancelled, let last = self.lastChange,
                      ContinuousClock.now - last < Self.flourishWindow else { break }
                if self.isIdle, self.view != nil { self.flourish?() }
            }
            if !Task.isCancelled { self?.flourishTask = nil }
        }
    }

    func stopFlourishes() {
        flourishTask?.cancel()
        flourishTask = nil
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
