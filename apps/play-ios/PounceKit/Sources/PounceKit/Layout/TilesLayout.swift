import CoreGraphics

/// Pure geometry for the tile game's table (tile game spec §5.2), in SpriteKit scene points
/// (origin bottom-left, y up), computed for the real view size.
///
/// Bands, top to bottom: the opponents bar (as Cat Tower's), the rug where the sets flow in rows
/// with the toy box in its top right corner, the action strip (undo, reset, the turn button,
/// the sort and tidy toggles, with the opening meter riding on its top edge before the seat has
/// opened), and the stash: rows of seven pieces 48 pt wide on a phone.
public struct TilesLayout: Equatable, Sendable {
    /// A piece is this much taller than it is wide.
    public static let pieceAspect: CGFloat = 1.2
    /// The smallest touch target a control gets.
    public static let buttonHit: CGFloat = 44
    /// Rows the stash shows before it scrolls sideways.
    public static let rackRowLimit = 3

    public let size: CGSize
    public let safeTop: CGFloat
    public let safeBottom: CGFloat
    public let arrangement: TableLayout.Arrangement

    public let opponentsBar: CGRect
    public let opponentSlots: [CGPoint]
    public let catDiameter: CGFloat
    public let catLift: CGFloat
    public let nameDrop: CGFloat
    public let menuButton: CGPoint
    public let menuSide: CGFloat

    /// The rug's art.
    public let rugArt: CGRect
    /// Where sets flow: inside the rug's border.
    public let rug: CGRect
    /// How much larger than its art the rug's border is drawn (bigger on a roomy screen).
    public let rugBorderScale: CGFloat
    /// The toy box, in the rug's top right corner.
    public let pool: CGRect
    /// A rug piece at its largest (a small table) and smallest (a full one).
    public let rugPieceMax: CGFloat
    public let rugPieceMin: CGFloat

    public let strip: CGRect
    public let undo: CGRect
    public let reset: CGRect
    public let turn: CGRect
    public let sortNumber: CGRect
    public let sortToy: CGRect
    public let tidy: CGRect
    /// The opening meter, riding on the strip's top edge. Zero when the seat has opened.
    public let meter: CGRect

    public let rack: CGRect
    public let rackPiece: CGSize
    /// Pieces per stash row: seven on a phone.
    public let rackColumns: Int
    public let rackRows: Int
    private let rackGap: CGFloat
    private let rackCount: Int

    /// - Parameters:
    ///   - opponents: seats in the top bar.
    ///   - rackCount: pieces in the stash shown (it sets the number of rows).
    ///   - meter: the opening meter is showing.
    ///   - controls: false when no stash is drawn (a shared phone with nothing revealed, or a
    ///     phone holding no seat): the rug takes the room.
    public init(
        size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, opponents: Int, rackCount: Int, meter: Bool = false,
        controls: Bool = true
    ) {
        self.size = size
        self.safeTop = safeTop
        self.safeBottom = safeBottom
        self.rackCount = rackCount
        let width = size.width
        let arrangement = TableLayout.arrangement(for: size)
        self.arrangement = arrangement
        let roomy = arrangement != .phone

        // The top bar: Cat Tower's, so the two tables seat their cats alike.
        let base = TableLayout(size: size, safeTop: safeTop, safeBottom: safeBottom, opponents: max(opponents, 1))
        opponentsBar = base.opponentsBar
        catDiameter = base.catDiameter
        catLift = base.catLift
        nameDrop = base.nameDrop
        menuSide = base.menuSide
        // The paw menu sits inside the bar's top right corner, below the safe top on every
        // device: never up in the status bar's ear (Cat Tower's spot), where it hid partly under
        // the status bar. On a phone, three cats share the width left of it, as Cat Tower's do
        // when the paw is tucked.
        let bar = base.opponentsBar
        menuButton = CGPoint(x: base.menuButton.x, y: bar.maxY - base.menuSide / 2 - (roomy ? 6 : 2))
        if !roomy, base.opponentSlots.count >= 3 {
            let n = base.opponentSlots.count
            let span = width - TableLayout.menuReserve
            opponentSlots = base.opponentSlots.enumerated().map { i, slot in
                CGPoint(x: span * (CGFloat(i) + 0.5) / CGFloat(n), y: slot.y)
            }
        } else {
            opponentSlots = base.opponentSlots
        }

        // The stash. Phone: seven across, 48 pt at 393 wide. Roomy: fourteen across, bigger.
        let gap: CGFloat = roomy ? 6 : 4
        rackGap = gap
        let columns = roomy ? 14 : 7
        rackColumns = columns
        let side: CGFloat = roomy ? 24 : 8
        let fit = ((width - 2 * side - gap * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
        // 48 pt on the spec's 393 pt phone, a little more on a wider one, what fits on a narrower.
        let pieceW = roomy ? min(max(fit, 44), 64) : min(max(fit, 40), (48 * max(width / 393, 1)).rounded(.down))
        let piece = CGSize(width: pieceW, height: (pieceW * Self.pieceAspect).rounded())
        rackPiece = piece
        let needed = Int((Double(max(rackCount, 1)) / Double(columns)).rounded(.up))
        // Two rows of seven is the deal: a phone always shows two, so the rug doesn't jump on a draw.
        let rows = min(max(needed, roomy ? 1 : 2), Self.rackRowLimit)
        rackRows = rows
        let rackPad: CGFloat = 8
        let rackH = controls ? CGFloat(rows) * piece.height + CGFloat(rows - 1) * gap + 2 * rackPad : 0
        let rackY = safeBottom + (roomy ? 10 : 4)
        rack = CGRect(x: 0, y: rackY, width: width, height: rackH)

        // The action strip.
        let stripH: CGFloat = controls ? (roomy ? 72 : 60) : 0
        strip = CGRect(x: 0, y: rack.maxY, width: width, height: stripH)
        let hit: CGFloat = roomy ? 56 : Self.buttonHit
        let edge: CGFloat = roomy ? 24 : 8
        let mid = strip.midY
        func button(_ x: CGFloat) -> CGRect { CGRect(x: x, y: mid - hit / 2, width: hit, height: hit) }
        undo = controls ? button(edge) : .zero
        reset = controls ? button(edge + hit + 2) : .zero
        tidy = controls ? button(width - edge - hit) : .zero
        sortToy = controls ? button(width - edge - 2 * hit - 2) : .zero
        sortNumber = controls ? button(width - edge - 3 * hit - 4) : .zero
        // The turn button takes what is left between the two groups, centered on the screen.
        let leftEnd = edge + 2 * hit + 2, rightStart = width - edge - 3 * hit - 4
        // The turn button fills the gap between the two groups (three toggles on the right, two
        // buttons on the left, so on a phone that is a little left of the screen's middle).
        let turnH: CGFloat = roomy ? 60 : 52
        let turnW = min(rightStart - leftEnd - 14, roomy ? 260 : 176)
        let turnMid = roomy ? width / 2 : (leftEnd + rightStart) / 2
        turn = controls ? CGRect(x: turnMid - turnW / 2, y: mid - turnH / 2, width: turnW, height: turnH) : .zero
        let meterH: CGFloat = roomy ? 34 : 28
        let meterW: CGFloat = roomy ? 190 : 150
        self.meter = meter && controls
            ? CGRect(x: turnMid - meterW / 2 + meterH * 0.5, y: strip.maxY - 2, width: meterW, height: meterH)
            : .zero

        // The rug: everything between the strip (and the meter) and the opponents bar.
        let rugBottom = (meter && controls ? self.meter.maxY : strip.maxY) + (controls ? 6 : safeBottom + 12)
        let rugTop = opponentsBar.minY - (roomy ? 10 : 6)
        let rugSide: CGFloat = roomy ? 24 : 4
        let art = CGRect(x: rugSide, y: rugBottom, width: width - 2 * rugSide, height: max(rugTop - rugBottom, 60))
        rugArt = art
        // The rug's braided border is 24 pt wide at scale 1; sets may sit on its inner braid.
        rugBorderScale = roomy ? 2.4 : 1.5
        let border: CGFloat = roomy ? 26 : 14
        rug = art.insetBy(dx: border - 1, dy: border + 3)
        let poolSide: CGFloat = roomy ? 84 : 58
        pool = CGRect(x: rug.maxX - poolSide, y: rug.maxY - poolSide, width: poolSide, height: poolSide)

        // Rug pieces: 30 pt on a 393 pt phone, shrinking to 24 as the table fills (spec §5.7).
        let scale = roomy ? min(max(min(size.width, size.height) / 500, 1.3), 1.7) : min(max(width / 393, 0.94), 1.12)
        rugPieceMax = (30 * scale).rounded()
        rugPieceMin = (24 * scale).rounded()
    }

    // MARK: the stash

    /// Where each of `count` stash pieces sits (piece centers, before any sideways scroll), row
    /// by row from the top left, and how wide the rows are together. Up to three rows of
    /// `rackColumns`; past that the rows grow sideways and the stash scrolls.
    public func rackSlots(count: Int) -> (centers: [CGPoint], contentWidth: CGFloat) {
        guard count > 0, rack.height > 0 else { return ([], 0) }
        let perRow = max(rackColumns, Int((Double(count) / Double(rackRows)).rounded(.up)))
        let rowWidth = CGFloat(perRow) * rackPiece.width + CGFloat(perRow - 1) * rackGap
        let visible = CGFloat(rackColumns) * rackPiece.width + CGFloat(rackColumns - 1) * rackGap
        // Rows that fit are centered; rows that scroll start at the same left edge.
        let left = (size.width - visible) / 2
        let top = rack.maxY - 8 - rackPiece.height / 2
        let centers = (0..<count).map { i -> CGPoint in
            let row = i / perRow, column = i % perRow
            return CGPoint(
                x: left + rackPiece.width / 2 + CGFloat(column) * (rackPiece.width + rackGap),
                y: top - CGFloat(row) * (rackPiece.height + rackGap))
        }
        return (centers, rowWidth + 2 * left)
    }

    /// The stash slot nearest `point` (in the stash's own coordinates, sideways scroll already
    /// taken off) among `count + 1` places a dragged piece could land: 0 is before the first.
    public func rackSlot(at point: CGPoint, count: Int) -> Int {
        let slots = rackSlots(count: count + 1).centers
        guard !slots.isEmpty else { return 0 }
        var best = 0
        var bestDistance = CGFloat.infinity
        for (i, slot) in slots.enumerated() {
            // Rows count for more than columns: a finger between two rows picks the nearer row.
            let d = abs(slot.x - point.x) + abs(slot.y - point.y) * 3
            if d < bestDistance {
                best = i
                bestDistance = d
            }
        }
        return best
    }

    /// How far the stash can scroll sideways for `count` pieces (0 when they all fit).
    public func rackScrollLimit(count: Int) -> CGFloat {
        max(rackSlots(count: count).contentWidth - size.width, 0)
    }
}

/// The sets of a rug flowed into rows like words in a paragraph (tile game spec §5.1, §5.7).
/// Coordinates are in the rug's content space: x from the rug's left edge, y downward from its
/// top edge (the scene turns them over), so a scrolled rug only moves its container.
public struct RugFlow: Equatable, Sendable {
    public struct Placement: Equatable, Sendable {
        /// The set's box, a little larger than its pieces (room for its outline).
        public var frame: CGRect
        /// Piece centers, in set order.
        public var pieces: [CGPoint]
    }

    public let pieceSize: CGSize
    /// One per set, in the order given.
    public let sets: [Placement]
    /// The "new row" slot after the last set: where a dragged piece starts a set of its own.
    public let newSlot: CGRect
    public let contentHeight: CGFloat
    /// The rows don't fit the rug's height: it scrolls.
    public let scrolls: Bool

    /// Space around a set's pieces inside its box.
    public static let setPad: CGFloat = 3
    static let rowGap: CGFloat = 9
    static let setGap: CGFloat = 7
    /// Pieces of a set sit shoulder to shoulder.
    static let pieceGap: CGFloat = 1

    /// Flows sets of `lengths` pieces into `width`, as large as fits `height` between `maxPiece`
    /// and `minPiece` wide. A row never splits a set, so the widest set caps the piece size (a
    /// row of thirteen is 27 pt or less on a phone). `corner` is kept clear at the top right (the
    /// toy box). `zoom` asks for a piece width outright (a pinch): then the rug just scrolls.
    public static func fit(
        lengths: [Int], width: CGFloat, height: CGFloat, maxPiece: CGFloat, minPiece: CGFloat,
        corner: CGSize = .zero, zoom: CGFloat? = nil
    ) -> RugFlow {
        let longest = CGFloat(max(lengths.max() ?? 3, 3))
        // The widest piece at which the longest set still fits one row.
        let cap = ((width - 2 * setPad - (longest - 1) * pieceGap) / longest).rounded(.down)
        if let zoom {
            return flow(lengths, width: width, height: height, piece: min(zoom, max(cap, 12)), corner: corner)
        }
        var piece = min(maxPiece, cap)
        let floor = min(minPiece, cap)
        var best = flow(lengths, width: width, height: height, piece: piece, corner: corner)
        while best.scrolls, piece > floor {
            piece = max(piece - 1, floor)
            best = flow(lengths, width: width, height: height, piece: piece, corner: corner)
        }
        return best
    }

    static func flow(_ lengths: [Int], width: CGFloat, height: CGFloat, piece: CGFloat, corner: CGSize) -> RugFlow {
        let size = CGSize(width: piece, height: (piece * TilesLayout.pieceAspect).rounded())
        let rowH = size.height + 2 * setPad
        var placements: [Placement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        /// The width a row starting at `y` may use: rows beside the toy box stop short of it.
        func rowWidth(_ y: CGFloat) -> CGFloat { y < corner.height ? width - corner.width - 4 : width }
        func box(_ count: Int) -> CGFloat { CGFloat(count) * piece + CGFloat(max(count - 1, 0)) * pieceGap + 2 * setPad }
        func place(_ w: CGFloat) -> CGPoint {
            // Down a row when the set doesn't fit what is left of this one. A set too wide for a
            // row beside the toy box goes below it.
            while x > 0 ? x + w > rowWidth(y) : (w > rowWidth(y) && y < corner.height) {
                x = 0
                y += rowH + rowGap
            }
            let at = CGPoint(x: x, y: y)
            x += w + setGap
            return at
        }
        for count in lengths {
            let w = box(max(count, 1))
            let at = place(w)
            let frame = CGRect(x: at.x, y: at.y, width: w, height: rowH)
            let pieces = (0..<count).map { i in
                CGPoint(x: frame.minX + setPad + piece / 2 + CGFloat(i) * (piece + pieceGap), y: frame.midY)
            }
            placements.append(Placement(frame: frame, pieces: pieces))
        }
        let slotW = box(2)
        let at = place(slotW)
        let slot = CGRect(x: at.x, y: at.y, width: slotW, height: rowH)
        let content = slot.maxY
        return RugFlow(pieceSize: size, sets: placements, newSlot: slot, contentHeight: content, scrolls: content > height + 0.5)
    }

    /// The index of the set whose box holds `point` (content space), widened by `slop` so a
    /// finger between two rows still finds the nearer set.
    public func set(at point: CGPoint, slop: CGFloat = 4) -> Int? {
        var best: Int?
        var bestDistance = CGFloat.infinity
        for (i, placement) in sets.enumerated() {
            let frame = placement.frame.insetBy(dx: -slop, dy: -slop)
            guard frame.contains(point) else { continue }
            let d = abs(placement.frame.midX - point.x) + abs(placement.frame.midY - point.y)
            if d < bestDistance {
                best = i
                bestDistance = d
            }
        }
        return best
    }
}
