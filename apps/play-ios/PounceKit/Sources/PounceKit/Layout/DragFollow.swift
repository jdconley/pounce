import CoreGraphics

/// Where a dragged card is drawn. It sits on its target (the finger plus the grab offset, or
/// lifted clear of the laid group under the finger) on every frame, so it never trails the
/// finger. When the target jumps (the card lifts above a group, comes back down, or moves to
/// another row) the jump is eased out as a shrinking offset over `duration`, so the card
/// glides across while it keeps moving with the finger.
public struct DragFollow: Equatable, Sendable {
    /// Seconds a jump takes to ease out.
    public let duration: Double
    private var target: CGPoint?
    private var offset: CGVector = .zero
    private var start: Double = -.infinity

    public init(duration: Double) {
        self.duration = max(duration, 0)
    }

    /// Moves the target at `time`. A `jump` eases over from wherever the card is drawn now.
    public mutating func move(to target: CGPoint, jump: Bool, at time: Double) {
        if jump, let drawn = position(at: time), duration > 0 {
            offset = CGVector(dx: drawn.x - target.x, dy: drawn.y - target.y)
            start = time
        }
        self.target = target
    }

    /// Where the card is drawn at `time`; nil before the first `move`.
    public func position(at time: Double) -> CGPoint? {
        guard let target else { return nil }
        let k = remaining(at: time)
        return CGPoint(x: target.x + offset.dx * k, y: target.y + offset.dy * k)
    }

    /// A jump is still easing out at `time`.
    public func isEasing(at time: Double) -> Bool { remaining(at: time) > 0 }

    /// The share of the last jump still to go: ease out, 1 at the jump, 0 after `duration`.
    private func remaining(at time: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        let t = min(max((time - start) / duration, 0), 1)
        return CGFloat((1 - t) * (1 - t))
    }
}
