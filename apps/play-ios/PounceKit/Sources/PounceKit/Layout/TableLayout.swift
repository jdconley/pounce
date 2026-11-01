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

    // Hand fan.
    private let handBaseY: CGFloat
    private let fanRadius: CGFloat
    private let handSpan: CGFloat
    // Laid rows.
    private let rowHeight: CGFloat
    private let columnWidth: CGFloat
    private let columnGap: CGFloat
    private let rowGap: CGFloat

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
        miniCardSize = CGSize(width: (cardW * 0.55).rounded(), height: (card.height * 0.55).rounded())

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

        // Tower: left edge, from above the trays to below the opponents bar.
        let towerBottom = trays.maxY + 6
        towerFrame = CGRect(x: 0, y: towerBottom, width: Self.towerWidth, height: bar.minY - 4 - towerBottom)

        // Laid zone: right of the tower, between the bar and the trays.
        let zoneMinX = towerFrame.maxX + 8
        let zone = CGRect(x: zoneMinX, y: towerBottom, width: width - 8 - zoneMinX, height: bar.minY - 8 - towerBottom)
        laidZone = zone

        // Rows: two columns; rows above and below the piles hug them.
        let gap: CGFloat = 10
        let rowH = miniCardSize.height + 10
        rowHeight = rowH
        rowGap = gap
        columnGap = 8
        columnWidth = (zone.width - 8) / 2

        // Pile height is fixed by the largest table (3 laid rows: 1 above, 2 below) so the
        // piles never jump between player counts.
        let stack = 3 * rowH + 4 * gap + card.height
        let slack = max((zone.height - stack) / 2, 0)
        let pilesY = zone.maxY - slack - rowH - gap - card.height / 2
        let pileOffset = card.width / 2 + 8
        deck = CGPoint(x: zone.midX - pileOffset, y: pilesY)
        discard = CGPoint(x: zone.midX + pileOffset, y: pilesY)
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
        let step = count > 1 ? min(cardSize.width * 0.72, 2 * handSpan / CGFloat(count - 1)) : 0
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

    /// Laid-down row for seat `slot` of `total` seats. Two columns; rows above the piles
    /// fill from the top, rows below from the piles down. A lone last row is centered.
    public func laidRow(slot: Int, of total: Int) -> CGRect {
        let total = max(total, 1)
        let slot = min(max(slot, 0), total - 1)
        let rows = (total + 1) / 2
        let rowsAbove = rows / 2
        let r = slot / 2
        let alone = total % 2 == 1 && slot == total - 1
        let x: CGFloat = alone
            ? laidZone.midX - columnWidth / 2
            : laidZone.minX + CGFloat(slot % 2) * (columnWidth + columnGap)
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
        return CGRect(x: x, y: midY - rowHeight / 2, width: columnWidth, height: rowHeight)
    }
}
