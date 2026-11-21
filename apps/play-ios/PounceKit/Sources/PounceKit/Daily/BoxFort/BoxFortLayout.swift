import CoreGraphics

/// Where Box Fort's pieces go on screen: the score row, the rug and the three tray slots, and the
/// drag's arithmetic (where a lifted piece is drawn, which spot it snaps to). Pure geometry, so the
/// drag's per-frame work is a few multiplications.
///
/// Phones and iPad portrait stack the score, the rug and the tray. A wide space (iPad landscape)
/// puts the tray in a column beside the rug.
public struct BoxFortLayout: Equatable, Sendable {
    /// A rug spot never grows past this, so the rug stays a board on a big iPad.
    public static let maxCell: CGFloat = 76
    /// Pieces in the tray are drawn at this share of a rug spot.
    public static let trayScale: CGFloat = 0.5
    /// A lifted piece floats this many spots above the finger, so the finger never hides it.
    public static let lift: CGFloat = 1.1
    /// The rug's border and fringe reach this many spots past its spots, all round.
    public static let fringe: CGFloat = 0.5

    private static let gutter: CGFloat = 16
    private static let gap: CGFloat = 12
    private static let headerHeight: CGFloat = 48
    /// A tray slot holds a five-box piece at tray scale, plus this padding around it.
    private static let slotPad: CGFloat = 10

    public let size: CGSize
    /// A rug spot's side.
    public let cell: CGFloat
    public let header: CGRect
    public let rug: CGRect
    public let slots: [CGRect]
    /// The tray sits beside the rug rather than below it.
    public let sideTray: Bool

    public var trayCell: CGFloat { cell * Self.trayScale }

    public init(size: CGSize) {
        self.size = size
        let w = size.width
        let h = size.height
        let g = Self.gap
        let pad = Self.slotPad
        // A tray slot's depth: five boxes at tray scale and its padding.
        let depth: (CGFloat) -> CGFloat = { cell in 5 * cell * Self.trayScale + 2 * pad }
        sideTray = w > h * 1.15
        if sideTray {
            // Room under the rug for the finger: a piece going on the bottom row floats above a
            // finger `lift` spots below the rug (the stacked layout's tray gives it that room).
            let byHeight = (h - Self.headerHeight - 2 * g) / (8 + Self.fringe + Self.lift)
            let byWidth = (w - 2 * Self.gutter - g - 2 * pad) / (8 + 2 * Self.fringe + 5 * Self.trayScale)
            cell = max(1, min(Self.maxCell, byHeight, byWidth))
        } else {
            let byWidth = (w - 2 * Self.gutter) / 8
            let byHeight = (h - Self.headerHeight - 3 * g - 2 * pad) / (8 + 2 * Self.fringe + 5 * Self.trayScale)
            cell = max(1, min(Self.maxCell, byWidth, byHeight))
        }
        let side = 8 * cell
        let trayDepth = depth(cell)
        if sideTray {
            let total = side + 2 * Self.fringe * cell + g + trayDepth
            let left = (w - total) / 2
            let fringe = Self.fringe * cell
            let top = Self.headerHeight + g + fringe + max(0, (h - Self.headerHeight - g - fringe - side - Self.lift * cell) / 2)
            header = CGRect(x: left, y: 0, width: total, height: Self.headerHeight)
            let board = CGRect(x: left + fringe, y: top, width: side, height: side)
            rug = board
            let slotHeight = side / 3
            slots = (0..<3).map { i in
                CGRect(x: board.maxX + fringe + g, y: top + CGFloat(i) * slotHeight, width: trayDepth, height: slotHeight)
            }
        } else {
            let fringe = Self.fringe * cell
            let total = Self.headerHeight + g + fringe + side + fringe + g + trayDepth
            let top = max(0, (h - total) / 2)
            let left = (w - side) / 2
            header = CGRect(x: left, y: top, width: side, height: Self.headerHeight)
            let board = CGRect(x: left, y: top + Self.headerHeight + g + fringe, width: side, height: side)
            rug = board
            let slotWidth = side / 3
            slots = (0..<3).map { i in
                CGRect(x: left + CGFloat(i) * slotWidth, y: board.maxY + fringe + g, width: slotWidth, height: trayDepth)
            }
        }
    }

    /// The rect of a rug spot, in the layout's space.
    public func cellRect(row: Int, col: Int) -> CGRect {
        CGRect(x: rug.minX + CGFloat(col) * cell, y: rug.minY + CGFloat(row) * cell, width: cell, height: cell)
    }

    /// Where a piece of `size` is drawn while a finger at `finger` holds it: centered across the
    /// finger and floating `lift` spots above it, at full rug size.
    public func lifted(finger: CGPoint, size: BoxFortCell) -> CGPoint {
        CGPoint(
            x: finger.x - CGFloat(size.col) * cell / 2,
            y: finger.y - CGFloat(size.row) * cell - Self.lift * cell)
    }

    /// The rug spot a piece whose top-left is drawn at `origin` lands on: the nearest one, or nil
    /// when the piece would hang off the rug there.
    public func snap(origin: CGPoint, size: BoxFortCell) -> BoxFortCell? {
        let row = Int(((origin.y - rug.minY) / cell).rounded())
        let col = Int(((origin.x - rug.minX) / cell).rounded())
        guard row >= 0, col >= 0, row + size.row <= 8, col + size.col <= 8 else { return nil }
        return BoxFortCell(row: row, col: col)
    }

    /// Top-left of a piece of `size` resting in tray `slot`, at tray scale.
    public func trayOrigin(slot: Int, size: BoxFortCell) -> CGPoint {
        let rect = slots[slot]
        return CGPoint(
            x: rect.midX - CGFloat(size.col) * trayCell / 2,
            y: rect.midY - CGFloat(size.row) * trayCell / 2)
    }

    /// The tray slot under `point`, if any.
    public func slot(at point: CGPoint) -> Int? {
        slots.firstIndex { $0.contains(point) }
    }
}
