import CoreGraphics

/// The edges of a TV's picture that nothing may sit in, in points: tvOS's TV-safe area, or a
/// TV's overscan.
public struct TVInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public init(all: CGFloat) { self.init(top: all, left: all, bottom: all, right: all) }

    public static let zero = TVInsets(all: 0)
    /// tvOS's TV-safe area on its 1920 x 1080 point screen.
    public static let tvSafe = TVInsets(top: 60, left: 80, bottom: 60, right: 80)

    public func scaled(by k: CGFloat) -> TVInsets {
        TVInsets(top: top * k, left: left * k, bottom: bottom * k, right: right * k)
    }
}

/// Both games' TV tables are planned in 1080p points, top-left origin, y down (as the web's
/// `ct-layout.ts` plans them), and drawn at `unit = min(width / 1920, height / 1080)`: 1 on an
/// Apple TV, 2 on a 3840 x 2160 frame, so 4K draws exactly twice 1080p. The plan is the safe
/// area (the frame less its insets) in plan points, so things keep their planned size and the
/// table fits around them; a margin keeps everything at least `edge` from the frame's edge.
struct TVPlan {
    static let width: CGFloat = 1920
    static let height: CGFloat = 1080
    /// What both games' TV tables share, in plan points (the web's `TV`).
    static let edge: CGFloat = 24
    static let gap: CGFloat = 24
    static let avatar: CGFloat = 136
    /// A seat is its cat with its name and score under it: at least room for a 20-character
    /// name, and wider where its place on the table has the room, for fewer cut-off names.
    static let seatW: CGFloat = 372
    static let seatMaxW: CGFloat = 560
    static let seatH: CGFloat = avatar + 96
    static let bannerW: CGFloat = 760
    static let bannerH: CGFloat = 88
    /// The widest the banner grows for a long name ("Great Aunt Josephine's turn").
    static let bannerMaxW: CGFloat = 1400
    /// The menu's button, a square in the bottom-right corner.
    static let menu: CGFloat = 88

    let size: CGSize
    let insets: TVInsets
    let unit: CGFloat
    /// The plan's size: the safe area in plan points.
    let w: CGFloat
    let h: CGFloat
    /// The margins inside the plan, so nothing is nearer the frame's edge than `edge`.
    let left: CGFloat
    let top: CGFloat
    let right: CGFloat
    let bottom: CGFloat

    init(size: CGSize, insets: TVInsets) {
        self.size = size
        self.insets = insets
        let u = min(size.width / Self.width, size.height / Self.height)
        let unit = u.isFinite && u > 0 ? u : 1
        self.unit = unit
        w = max(size.width - insets.left - insets.right, 0) / unit
        h = max(size.height - insets.top - insets.bottom, 0) / unit
        func margin(_ inset: CGFloat) -> CGFloat { max(Self.edge - inset / unit, 0) }
        left = margin(insets.left)
        top = margin(insets.top)
        right = margin(insets.right)
        bottom = margin(insets.bottom)
    }

    /// The bottom-right corner both games keep free for the menu's button (plan).
    var menuRect: CGRect {
        CGRect(x: w - right - Self.menu, y: h - bottom - Self.menu, width: Self.menu, height: Self.menu)
    }

    /// The room a banner has to grow into for a long name, centred on it, kept `gap` clear of
    /// `minX` and `maxX` (plan).
    func bannerRoom(_ banner: CGRect, minX: CGFloat, maxX: CGFloat) -> CGRect {
        let half = max(min(Self.bannerMaxW / 2, banner.midX - minX - Self.gap, maxX - Self.gap - banner.midX), banner.width / 2)
        return CGRect(x: banner.midX - half, y: banner.minY, width: 2 * half, height: banner.height)
    }

    /// A plan length on the screen.
    func len(_ v: CGFloat) -> CGFloat { v * unit }

    /// A plan point on the screen (SpriteKit: origin bottom-left, y up).
    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: insets.left + p.x * unit, y: insets.bottom + (h - p.y) * unit)
    }

    /// A plan rect on the screen.
    func rect(_ r: CGRect) -> CGRect {
        CGRect(x: insets.left + r.minX * unit, y: insets.bottom + (h - r.maxY) * unit, width: r.width * unit, height: r.height * unit)
    }
}
