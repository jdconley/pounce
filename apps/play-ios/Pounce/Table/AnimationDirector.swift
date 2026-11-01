import SpriteKit

/// Render on demand (spec §9.2): the `SKView` runs only while something animates or a finger
/// is down. Every table motion goes through `run` / `emit`, which count what's in flight; the
/// scene reports each frame, and the view pauses once nothing has been busy for `idleDelay`.
/// `wake()` unpauses for one-off redraws (a reconcile, a resize).
@MainActor
final class AnimationDirector {
    weak var view: SKView? {
        didSet { wake() }
    }

    /// Actions and emitters in flight.
    private(set) var running = 0
    private var touches = 0
    /// Scene time when the table was last busy (or woken); nil until the next frame.
    private var lastBusy: TimeInterval?

    /// Frames the scene has updated since launch (DEBUG: `table.frames`).
    private(set) var framesRendered = 0

    static let idleDelay: TimeInterval = 0.1

    init(view: SKView?) {
        self.view = view
    }

    var isIdle: Bool { running == 0 && touches == 0 }

    /// Unpauses the view; it pauses again `idleDelay` after the table goes idle.
    func wake() {
        lastBusy = nil
        if let view, view.isPaused { view.isPaused = false }
    }

    func touchBegan() {
        touches += 1
        wake()
    }

    func touchEnded() {
        touches = max(touches - 1, 0)
        wake()
    }

    /// Runs `action` on `node` and returns when it finishes. If the node leaves the tree
    /// before the action completes (SpriteKit then never calls back), a timeout releases it.
    func run(_ action: SKAction, on node: SKNode) async {
        running += 1
        wake()
        let once = Once()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            node.run(action) {
                once.fire { continuation.resume() }
            }
            let timeout = action.duration / Double(max(node.speed, 0.01)) + 0.5
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                once.fire { continuation.resume() }
            }
        }
        running -= 1
        wake()
    }

    /// Adds `emitter` at `at` in `parent` for `lifetime` seconds, then removes it.
    func emit(_ emitter: SKEmitterNode, at point: CGPoint, in parent: SKNode, lifetime: TimeInterval) {
        running += 1
        wake()
        emitter.position = point
        parent.addChild(emitter)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            emitter.removeFromParent()
            guard let self else { return }
            self.running -= 1
            self.wake()
        }
    }

    /// Called by the scene once per frame. Pauses the view after `idleDelay` of idleness.
    func frame(_ time: TimeInterval) {
        framesRendered += 1
        guard isIdle else {
            lastBusy = time
            return
        }
        guard let since = lastBusy else {
            lastBusy = time
            return
        }
        if time - since >= Self.idleDelay {
            view?.isPaused = true
        }
    }
}

/// Fires its body at most once.
@MainActor
private final class Once {
    private var fired = false

    func fire(_ body: () -> Void) {
        guard !fired else { return }
        fired = true
        body()
    }
}
