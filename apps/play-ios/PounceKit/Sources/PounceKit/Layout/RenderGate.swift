import Foundation

/// Render-on-demand bookkeeping for the table (spec §9.2), free of SpriteKit so it can be tested.
///
/// The scene reports every rendered frame. Time here is *rendered* time: it only advances
/// between consecutive frames, each step clamped to `maxStep`, and `wake()` forgets the last
/// frame. So a paused view (app inactive, Control Center, a call) never runs a timeout down:
/// an action is only given up on after it had `duration + grace` of real frames to finish.
///
/// - `begin` / `end` bracket an action or emitter; `frame` returns the ones whose deadline
///   passed (the director removes those actions so they can't resume later) and whether the
///   view should pause: nothing running, no touch down, for `idleDelay` of rendered time.
/// - `cancelAll` gives up on everything at once (the view is going away and will never render
///   the rest), so every waiter can be released.
/// - The particle budget: bursts reserve particles up front and release them when their
///   emitter goes, so at most `maxParticles` are ever alive on the table.
public struct RenderGate: Sendable {
    /// Most particles alive at once across every emitter on the table.
    public static let maxParticles = 60
    public static let idleDelay: TimeInterval = 0.1
    /// Extra rendered time an action gets past its duration before it is given up on.
    public static let grace: TimeInterval = 0.5
    /// The most one frame can advance rendered time (a hitch or a resume after a pause).
    public static let maxStep: TimeInterval = 0.1

    public struct FrameResult: Equatable, Sendable {
        public var expired: [Int]
        public var pause: Bool
    }

    /// Running tokens and their deadlines in rendered time.
    public private(set) var running: [Int: TimeInterval] = [:]
    public private(set) var touches = 0
    public private(set) var renderedTime: TimeInterval = 0
    /// Particles reserved by emitters still on screen.
    public private(set) var particles = 0
    private var lastFrame: TimeInterval?
    private var idleSince: TimeInterval?
    private var nextToken = 0

    public init() {}

    public var isIdle: Bool { running.isEmpty && touches == 0 }

    /// A duration SpriteKit could report that isn't usable (infinite, NaN, negative) counts as 0.
    public static func sanitize(_ duration: TimeInterval) -> TimeInterval {
        duration.isFinite && duration > 0 ? duration : 0
    }

    /// Starts tracking something that lasts `duration` of rendered time; returns its token.
    public mutating func begin(duration: TimeInterval, grace: TimeInterval = RenderGate.grace) -> Int {
        let token = nextToken
        nextToken += 1
        running[token] = renderedTime + Self.sanitize(duration) + Self.sanitize(grace)
        idleSince = nil
        return token
    }

    /// Stops tracking `token`. False if it already ended or expired.
    @discardableResult public mutating func end(_ token: Int) -> Bool {
        running.removeValue(forKey: token) != nil
    }

    /// Stops tracking every running token and returns them (sorted), so the caller can release
    /// what waits on them. Touches are forgotten too: no finger stays down on a gone view.
    public mutating func cancelAll() -> [Int] {
        let tokens = running.keys.sorted()
        running.removeAll()
        touches = 0
        idleSince = nil
        return tokens
    }

    /// Reserves up to `wanted` particles within `maxParticles`; returns how many were granted.
    public mutating func reserveParticles(_ wanted: Int) -> Int {
        let granted = min(max(wanted, 0), max(Self.maxParticles - particles, 0))
        particles += granted
        return granted
    }

    public mutating func releaseParticles(_ count: Int) {
        particles = max(particles - max(count, 0), 0)
    }

    public mutating func touchBegan() {
        touches += 1
        idleSince = nil
    }

    public mutating func touchEnded() {
        touches = max(touches - 1, 0)
        idleSince = nil
    }

    /// The view is about to (re)start: the gap since the last frame counts for nothing and
    /// the idle countdown starts over.
    public mutating func wake() {
        lastFrame = nil
        idleSince = nil
    }

    /// One rendered frame at scene time `time`.
    public mutating func frame(_ time: TimeInterval) -> FrameResult {
        if let last = lastFrame {
            renderedTime += min(max(time - last, 0), Self.maxStep)
        }
        lastFrame = time
        let now = renderedTime
        let expired = running.filter { $0.value <= now + 1e-9 }.keys.sorted()
        for token in expired { running[token] = nil }
        guard isIdle else {
            idleSince = nil
            return FrameResult(expired: expired, pause: false)
        }
        let since = idleSince ?? now
        idleSince = since
        return FrameResult(expired: expired, pause: now - since >= Self.idleDelay - 1e-9)
    }
}
