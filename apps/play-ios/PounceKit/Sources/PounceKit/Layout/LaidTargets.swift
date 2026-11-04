import CoreGraphics

/// Which laid group a dragged (or tapped) card is over, and which end of it. Shared by the
/// live drop preview and the drop itself, so the card always lands where the preview showed.
public enum LaidTargets {
    /// How far past a group's edge a finger still takes it (laid cards are small; on an
    /// iPhone SE a mini card is about 41 pt wide).
    public static let reach: CGFloat = 16

    /// The group nearest `p` within `reach` of its frame; a finger on a group always picks
    /// it. Rows and groups sit only 8 pt apart, so the reaches overlap and the nearest edge
    /// decides (never the first group listed).
    public static func target(at p: CGPoint, in frames: [(target: HitTarget, frame: CGRect)], reach: CGFloat = reach) -> HitTarget? {
        var best: (target: HitTarget, distance: CGFloat)?
        for (target, f) in frames {
            let dx = max(f.minX - p.x, 0, p.x - f.maxX)
            let dy = max(f.minY - p.y, 0, p.y - f.maxY)
            let d = hypot(dx, dy)
            if d <= reach, d < (best?.distance ?? .infinity) { best = (target, d) }
        }
        return best?.target
    }

    /// The end of a group a finger at `p` is nearer: the left half is the start.
    public static func side(at p: CGPoint, of frame: CGRect) -> HitSide {
        p.x < frame.midX ? .start : .end
    }
}
