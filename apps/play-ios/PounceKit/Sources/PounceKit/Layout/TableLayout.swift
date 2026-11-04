import CoreGraphics

/// Where one hand card sits: position (card center), rotation and stacking order.
public struct CardPlacement: Equatable, Sendable {
    public var position: CGPoint
    /// Radians, counter-clockwise positive (SpriteKit `zRotation`).
    public var rotation: CGFloat
    public var z: CGFloat

    public init(position: CGPoint, rotation: CGFloat, z: CGFloat) {
        self.position = position
        self.rotation = rotation
        self.z = z
    }
}

/// Pure geometry for the table, in SpriteKit scene points (origin bottom-left, y up).
/// The scene uses `.resizeFill`, so this is computed for the real view size.
///
/// Bands, top to bottom: opponents bar (96 pt, below the safe top), the rug with the
/// deck left and discard right of center, laid-down rows around the piles, phase trays
/// (64 pt) above the hand, and the fanned hand (above the safe bottom). The cat tower
/// runs down the left edge between the opponents bar and the trays. No two hit-test
/// regions (opponent slots, deck, discard, trays, laid rows, tower) overlap.
public struct TableLayout: Sendable {
    public static let opponentsBarHeight: CGFloat = 96
    public static let traysHeight: CGFloat = 64
    public static let towerWidth: CGFloat = 44
    /// The sort button's touch target (drawn 36 pt) at the right, just above the trays.
    public static let sortButtonHit: CGFloat = 44
    public static let shelfCount = 10

    public let size: CGSize
    public let safeTop: CGFloat
    public let safeBottom: CGFloat
    public let cardSize: CGSize
    public let miniCardSize: CGSize

    /// Strip across the top holding the opponent slots.
    public let opponentsBar: CGRect
    /// Opponent avatar centers, evenly spaced, left to right.
    public let opponentSlots: [CGPoint]
    /// Centers of the draw pile and the discard pile.
    public let deck: CGPoint
    public let discard: CGPoint
    public let towerFrame: CGRect
    public let traysFrame: CGRect
    /// Rect all laid-down rows live in (right of the tower, between bar and trays).
    public let laidZone: CGRect
    /// Sort button center; laid rows stop short of its touch target (and the seat's name pill).
    public let sortButton: CGPoint

    // Hand fan.
    private let handBaseY: CGFloat
    private let fanRadius: CGFloat
    private let handSpan: CGFloat
    // Laid rows.
    private let rowHeight: CGFloat
    private let columnWidth: CGFloat
    private let columnGap: CGFloat
    private let rowGap: CGFloat
    /// Full-width rows that fit above and below the piles.
    private let rowsAboveCapacity: Int
    private let rowsBelowCapacity: Int

    private static let handSidePad: CGFloat = 4
    private static let handBottomPad: CGFloat = 4
    private static let liftHeight: CGFloat = 30
    private static let designWidth: CGFloat = 390

    public init(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, opponents: Int) {
        self.size = size
        self.safeTop = safeTop
        self.safeBottom = safeBottom
        let width = size.width

        // Cards: 64 x 90 at 390 pt wide, scaled with the width, 56...76 wide.
        let cardW = min(max(64 * width / Self.designWidth, 56), 76)
        let card = CGSize(width: cardW, height: (cardW * 90 / 64).rounded())
        cardSize = card
        // Laid cards: 0.66 of a hand card (41 pt wide on a 375 pt phone), the smallest at which
        // the compact face's two-digit numerals keep an 11 pt cap height.
        miniCardSize = CGSize(width: (cardW * 0.66).rounded(), height: (card.height * 0.66).rounded())

        // Opponents bar and slots.
        let barH = Self.opponentsBarHeight
        let bar = CGRect(x: 0, y: size.height - safeTop - barH, width: width, height: barH)
        opponentsBar = bar
        let n = min(max(opponents, 1), 6)  // 6: every seat, on a phone that holds none
        opponentSlots = (0..<n).map { CGPoint(x: width * (CGFloat($0) + 0.5) / CGFloat(n), y: bar.midY) }

        // Hand fan: a circular arc of radius `fanRadius` centered below the hand. The
        // outermost card sits fully inside the width once its rotated corners are counted.
        let radius = width * 1.5
        fanRadius = radius
        var edge = width / 2 - Self.handSidePad - cardW / 2
        for _ in 0..<6 {
            let t = edge / radius
            edge = width / 2 - Self.handSidePad - (cardW / 2 * cos(t) + card.height / 2 * sin(t))
        }
        handSpan = edge
        let tMax = edge / radius
        let drop = edge * edge / (2 * radius)
        let edgeHalfHeight = card.height / 2 * cos(tMax) + cardW / 2 * sin(tMax)
        let baseY = safeBottom + Self.handBottomPad + drop + edgeHalfHeight
        handBaseY = baseY
        let handTop = baseY + card.height / 2 + 4

        // Trays sit just above the hand.
        let trays = CGRect(x: 8, y: handTop + 6, width: width - 16, height: Self.traysHeight)
        traysFrame = trays
        sortButton = CGPoint(x: width - 26, y: trays.maxY + 24)

        // Tower: left edge, from above the trays to below the opponents bar.
        let towerBottom = trays.maxY + 6
        towerFrame = CGRect(x: 0, y: towerBottom, width: Self.towerWidth, height: bar.minY - 4 - towerBottom)

        // Laid zone: right of the tower, between the bar and the trays.
        let zoneMinX = towerFrame.maxX + 8
        let zone = CGRect(x: zoneMinX, y: towerBottom, width: width - 8 - zoneMinX, height: bar.minY - 8 - towerBottom)
        laidZone = zone

        // Rows: two columns; rows above and below the piles hug them.
        let gap: CGFloat = 8
        let rowH = miniCardSize.height + 8
        rowHeight = rowH
        rowGap = gap
        columnGap = 8
        columnWidth = (zone.width - 8) / 2

        // Pile height is fixed by the largest table (3 laid rows: 1 above, 2 below) so the
        // piles never jump between player counts. Centered, unless that puts the lowest row
        // beside the sort button: then raised as far as it takes (or fits).
        let stack = 3 * rowH + 4 * gap + card.height
        let clearOfSort = zone.maxY - stack + gap - (sortButton.y + Self.sortButtonHit / 2) - 1
        let slack = max(min((zone.height - stack) / 2, clearOfSort), 0)
        let pilesY = zone.maxY - slack - rowH - gap - card.height / 2
        let pileOffset = card.width / 2 + 8
        deck = CGPoint(x: zone.midX - pileOffset, y: pilesY)
        discard = CGPoint(x: zone.midX + pileOffset, y: pilesY)
        // A scene not sized yet can make these NaN.
        func rows(fitting span: CGFloat) -> Int {
            let n = (span / (rowH + gap)).rounded(.down)
            return n.isFinite && n > 0 ? Int(n) : 0
        }
        rowsAboveCapacity = rows(fitting: zone.maxY - pilesY - card.height / 2)
        rowsBelowCapacity = rows(fitting: pilesY - card.height / 2 - zone.minY)
    }

    public var sortButtonFrame: CGRect {
        let d = Self.sortButtonHit
        return CGRect(x: sortButton.x - d / 2, y: sortButton.y - d / 2, width: d, height: d)
    }

    /// The widest the bottom seat's name pill gets.
    public static let seatTagWidth: CGFloat = 150
    public static let seatTagHeight: CGFloat = 26

    /// Where the bottom seat's name pill may sit (it is right-aligned in here): just left of
    /// the sort button, on its line. Laid rows stop short of it too.
    public var seatTagFrame: CGRect {
        let sort = sortButtonFrame
        return CGRect(
            x: sort.minX - 4 - Self.seatTagWidth, y: sortButton.y - Self.seatTagHeight / 2,
            width: Self.seatTagWidth, height: Self.seatTagHeight)
    }

    /// Cat-tower shelf center, 0 (bottom) ... 9 (top).
    public func shelf(_ index: Int) -> CGPoint {
        let i = min(max(index, 0), Self.shelfCount - 1)
        let step = towerFrame.height / CGFloat(Self.shelfCount)
        return CGPoint(x: towerFrame.midX, y: towerFrame.minY + step * (CGFloat(i) + 0.5))
    }

    /// `count` equal tray slots across `traysFrame`, left to right, with gaps between.
    public func trayFrames(count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let gap: CGFloat = 8
        let w = (traysFrame.width - gap * CGFloat(count - 1)) / CGFloat(count)
        return (0..<count).map {
            CGRect(x: traysFrame.minX + CGFloat($0) * (w + gap), y: traysFrame.minY, width: w, height: traysFrame.height)
        }
    }

    /// Fanned hand, left to right. Card `lifted` (if in range) is raised and straightened;
    /// `z` strictly increases left to right either way.
    public func hand(count: Int, lifted: Int?) -> [CardPlacement] {
        guard count > 0 else { return [] }
        let mid = CGFloat(count - 1) / 2
        let step = handStep(count: count)
        let cx = size.width / 2
        return (0..<count).map { i in
            let dx = (CGFloat(i) - mid) * step
            var y = handBaseY - dx * dx / (2 * fanRadius)
            var rotation = -dx / fanRadius
            if i == lifted {
                y += Self.liftHeight
                rotation *= 0.5
            }
            return CardPlacement(position: CGPoint(x: cx + dx, y: y), rotation: rotation, z: 10 + CGFloat(i))
        }
    }

    /// The fan with an empty slot at `gap` (a card being dragged over the hand): `count` cards
    /// spread over `count + 1` slots, exactly where they sit once the dragged card lands in the
    /// gap, so dropping it moves nothing else.
    public func hand(count: Int, gap: Int) -> [CardPlacement] {
        guard count > 0 else { return [] }
        let gap = min(max(gap, 0), count)
        let slots = hand(count: count + 1, lifted: nil)
        return (0..<count).map { slots[$0 < gap ? $0 : $0 + 1] }
    }

    /// The slot, 0 ... `count` - 1, that a card dragged with its center at `x` lands in, in a
    /// fan of `count` slots (the dragged card's own included): the slot whose center is nearest.
    /// `current` (the slot shown now) holds until `x` is `slotHysteresis` of a step past the
    /// halfway line to a neighbor, so a card resting on a boundary doesn't flicker between two.
    public func handSlot(x: CGFloat, count: Int, current: Int?) -> Int {
        guard count > 1 else { return 0 }
        let step = handStep(count: count)
        let first = size.width / 2 - CGFloat(count - 1) / 2 * step
        let raw = ((x - first) / step).rounded()
        let nearest = raw.isFinite ? Int(min(max(raw, 0), CGFloat(count - 1))) : 0
        if let current, (0..<count).contains(current), nearest != current {
            let center = first + CGFloat(current) * step
            if abs(x - center) <= step * (0.5 + Self.slotHysteresis) { return current }
        }
        return nearest
    }

    /// How far past a slot boundary, as a fraction of the slot step, a dragged card must go
    /// before the target slot changes.
    public static let slotHysteresis: CGFloat = 0.2

    /// Distance between neighboring card centers in a fan of `count`.
    private func handStep(count: Int) -> CGFloat {
        count > 1 ? min(cardSize.width * 0.72, 2 * handSpan / CGFloat(count - 1)) : 0
    }

    /// Laid-down row for seat `slot` of `total` seats. When a row per seat fits above and below
    /// the piles, each row spans the zone (seats top to bottom, the upper half above the
    /// piles). Otherwise two columns; rows above the piles fill from the top, rows below from
    /// the piles down, and a lone last row is centered.
    public func laidRow(slot: Int, of total: Int) -> CGRect {
        let total = max(total, 1)
        let slot = min(max(slot, 0), total - 1)
        let r: Int, rowsAbove: Int, x: CGFloat, width: CGFloat
        if total <= rowsAboveCapacity + rowsBelowCapacity {
            rowsAbove = max(total - rowsBelowCapacity, min(rowsAboveCapacity, total / 2))
            r = slot
            x = laidZone.minX
            width = laidZone.width
        } else {
            rowsAbove = (total + 1) / 2 / 2
            r = slot / 2
            let alone = total % 2 == 1 && slot == total - 1
            x = alone ? laidZone.midX - columnWidth / 2 : laidZone.minX + CGFloat(slot % 2) * (columnWidth + columnGap)
            width = columnWidth
        }
        let pilesY = deck.y
        let half = cardSize.height / 2
        let midY: CGFloat
        if r < rowsAbove {
            let k = CGFloat(rowsAbove - 1 - r)
            midY = pilesY + half + rowGap + rowHeight / 2 + k * (rowHeight + rowGap)
        } else {
            let k = CGFloat(r - rowsAbove)
            midY = pilesY - half - rowGap - rowHeight / 2 - k * (rowHeight + rowGap)
        }
        var row = CGRect(x: x, y: midY - rowHeight / 2, width: width, height: rowHeight)
        let corner = sortButtonFrame.union(seatTagFrame)
        if row.intersects(corner) { row.size.width = max(corner.minX - 4 - row.minX, 0) }
        return row
    }
}
