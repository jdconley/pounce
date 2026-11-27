import CoreGraphics

/// Pure geometry for Toy Tumble's table (spec §5.2, §5.6), in SpriteKit scene points (origin
/// bottom-left, y up), for the real view size.
///
/// `.play`, a phone or iPad in portrait, top to bottom: the rim band (your cat holding the next
/// toy on the left, the round and wins in the middle, the paw menu on the right), your box leaning
/// left with the junk meter against its right edge, the minis of every opponent on the right (a
/// column, or two when needed), and the trick tray along the bottom. On an iPad in landscape the
/// minis split to both sides of the box. At a table a TV shows (`chips`), the minis shrink to chips.
///
/// `.watching`: out of the round, every box big in a grid. `.tv`: every box in one row filling the
/// screen, names and meters under them.
public struct TumbleLayout: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case play, watching, tv }

    public static let columns = 12
    public static let rows = 18
    public static let trays = 6
    public static let buttonHit: CGFloat = 44
    /// The chest's walls and rim around a mini's cells, in cells on each side.
    public static let wall: CGFloat = 0.7
    /// Your own box's walls, thinner, so its cells stay 20 pt on an iPhone SE.
    public static let ownWall: CGFloat = 0.35

    public let size: CGSize
    public let mode: Mode
    public let roomy: Bool
    /// Your box (`.play`); in the other modes, `boxes[0]` if any.
    public let box: CGRect
    public let cell: CGFloat
    /// Above your box: the cat and the next toy, then the round and wins.
    public let rim: CGRect
    public let menuButton: CGPoint
    /// The junk meter, a column against the box's right edge.
    public let meter: CGRect
    /// Every other box (or chip), in the order asked for; in `.watching` and `.tv` every box.
    public let minis: [CGRect]
    /// The box part of each mini (the rest is its name strip, below it).
    public let miniBoxes: [CGRect]
    public let miniCell: CGFloat
    public let chips: Bool
    public let tray: CGRect
    public let slots: [CGRect]
    /// The height of one line of a mini's name strip.
    public let labelHeight: CGFloat

    /// The safe frame everything fits inside.
    public let safe: CGRect

    /// - `others`: opponents' minis (`.play`), or every box (`.watching`, `.tv`).
    /// - `chips`: a TV shows this table: minis become chips.
    /// - `textScale`: 1, up to 1.4 at the accessibility text sizes; it grows the name strips.
    public init(
        size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, safeLeft: CGFloat = 0, safeRight: CGFloat = 0, others: Int,
        mode: Mode = .play, chips: Bool = false, textScale: CGFloat = 1
    ) {
        self.size = size
        self.mode = mode
        let w = size.width
        let h = size.height
        let tv = mode == .tv
        roomy = tv || min(w, h) >= 640
        let pad: CGFloat = tv ? 60 : (roomy ? 20 : 6)
        safe = CGRect(x: safeLeft + pad, y: safeBottom + (tv ? 40 : 6), width: w - safeLeft - safeRight - pad * 2,
                      height: h - safeTop - safeBottom - (tv ? 80 : 10))
        let gap: CGFloat = tv ? 36 : (roomy ? 14 : 6)
        let scale = min(max(textScale, 1), 1.4)
        labelHeight = (tv ? 34 : (roomy ? 18 : 13)) * scale
        self.chips = chips && mode == .play

        let rimH: CGFloat = tv ? 90 : (roomy ? 74 : 50 + 6 * (scale - 1) / 0.4)
        let topRim = CGRect(x: safe.minX, y: safe.maxY - rimH, width: safe.width, height: rimH)

        if mode != .play {
            rim = topRim
            menuButton = CGPoint(x: safe.maxX - Self.buttonHit / 2, y: topRim.midY)
            tray = .zero
            slots = []
            meter = .zero
            let area = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: topRim.minY - gap - safe.minY)
            let grid = Self.grid(count: max(others, 1), in: area, gap: gap, label: labelHeight * (tv ? 2.2 : 1.6), oneRow: tv)
            minis = grid.items
            miniBoxes = grid.boxes
            miniCell = grid.cell
            cell = grid.cell
            box = grid.boxes.first ?? .zero
            return
        }

        let trayH: CGFloat = roomy ? 76 : 50
        let trayRect = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: trayH)
        tray = trayRect
        let slotSide = min(trayH - 6, (tray.width - CGFloat(Self.trays - 1) * gap) / CGFloat(Self.trays))
        let slotsW = slotSide * CGFloat(Self.trays) + gap * CGFloat(Self.trays - 1)
        slots = (0..<Self.trays).map { i in
            CGRect(x: trayRect.minX + (trayRect.width - slotsW) / 2 + CGFloat(i) * (slotSide + gap), y: trayRect.midY - slotSide / 2,
                   width: slotSide, height: slotSide)
        }
        let roomTop = topRim.minY - gap
        let playBottom = tray.maxY + gap
        let roomH = roomTop - playBottom
        let landscapeSplit = roomy && w > h && others > 0
        let meterPart: CGFloat = 0.6
        // The minis' share of the width: enough for a readable column, more on a roomy screen.
        let minisW: CGFloat = others == 0 ? 0 : (self.chips ? (roomy ? 200 : 84) : max(roomy ? 0.3 * safe.width : 0.22 * safe.width, 80))
        let walls = Self.ownWall * 2
        let cellW = (safe.width - minisW - gap * (others == 0 ? 1 : 2)) / (CGFloat(Self.columns) + walls + meterPart)
        let cellH = roomH / (CGFloat(Self.rows) + walls)
        cell = floor(min(cellW, cellH, tv ? 60 : (roomy ? 48 : 40)))
        let boxW = cell * CGFloat(Self.columns)
        let boxH = cell * CGFloat(Self.rows)
        let meterW = max(cell * meterPart, 8)
        let wallW = cell * Self.ownWall
        // A tall phone has height to spare once the width sets the cells: the box sits on the
        // tray, in thumb reach, and the rim with your cat comes down with it.
        let spare = max(0, roomH - (boxH + wallW))
        let playTop = roomTop - spare
        let playH = playTop - playBottom
        rim = CGRect(x: safe.minX, y: playTop + gap, width: safe.width, height: rimH)
        menuButton = CGPoint(x: safe.maxX - Self.buttonHit / 2, y: rim.midY)
        let boxX: CGFloat
        if landscapeSplit {
            boxX = safe.midX - (boxW + wallW * 2 + meterW + gap) / 2 + wallW
        } else {
            boxX = safe.minX + wallW
        }
        box = CGRect(x: boxX, y: playTop - wallW - boxH, width: boxW, height: boxH)
        meter = CGRect(x: box.maxX + wallW + 2, y: box.minY, width: meterW, height: box.height)

        guard others > 0 else {
            minis = []
            miniBoxes = []
            miniCell = 0
            return
        }
        if self.chips {
            let area = CGRect(x: meter.maxX + gap, y: playBottom, width: safe.maxX - meter.maxX - gap, height: playH)
            let chipH = min(max(labelHeight * 2.6, 40), (area.height - gap * CGFloat(others - 1)) / CGFloat(others))
            minis = (0..<others).map { i in
                CGRect(x: area.minX, y: area.maxY - CGFloat(i + 1) * chipH - CGFloat(i) * gap, width: area.width, height: chipH)
            }
            miniBoxes = minis
            miniCell = 0
            return
        }
        if landscapeSplit {
            let leftN = (others + 1) / 2
            let left = CGRect(x: safe.minX, y: playBottom, width: box.minX - gap - safe.minX, height: playH)
            let right = CGRect(x: meter.maxX + gap, y: playBottom, width: safe.maxX - meter.maxX - gap, height: playH)
            let a = Self.grid(count: leftN, in: left, gap: gap, label: labelHeight, maxColumns: 2)
            let b = Self.grid(count: others - leftN, in: right, gap: gap, label: labelHeight, maxColumns: 2)
            let c = others - leftN > 0 ? min(a.cell, b.cell) : a.cell
            let a2 = Self.grid(count: leftN, in: left, gap: gap, label: labelHeight, maxColumns: 2, cell: c)
            let b2 = Self.grid(count: others - leftN, in: right, gap: gap, label: labelHeight, maxColumns: 2, cell: c)
            minis = a2.items + b2.items
            miniBoxes = a2.boxes + b2.boxes
            miniCell = c
            return
        }
        let area = CGRect(x: meter.maxX + gap, y: playBottom, width: safe.maxX - meter.maxX - gap, height: playH)
        let g = Self.grid(count: others, in: area, gap: gap, label: labelHeight, maxColumns: 2, top: true)
        minis = g.items
        miniBoxes = g.boxes
        miniCell = g.cell
    }

    /// The best grid of `count` boxes (12 by 18 cells, a name strip under each) in `area`.
    static func grid(
        count: Int, in area: CGRect, gap: CGFloat, label: CGFloat, maxColumns: Int = 6, oneRow: Bool = false, top: Bool = false,
        cell fixed: CGFloat? = nil
    ) -> (items: [CGRect], boxes: [CGRect], cell: CGFloat) {
        guard count > 0, area.width > 0, area.height > 0 else { return ([], [], 0) }
        var best: (cols: Int, cell: CGFloat) = (1, 0)
        let options = oneRow ? [count] : Array(1...min(maxColumns, count))
        for cols in options {
            let rowsN = (count + cols - 1) / cols
            let byW = (area.width - gap * CGFloat(cols - 1)) / CGFloat(cols) / (CGFloat(columns) + wall * 2)
            let byH = ((area.height - gap * CGFloat(rowsN - 1)) / CGFloat(rowsN) - label) / (CGFloat(rows) + wall * 2)
            let c = floor(min(byW, byH) * 2) / 2
            if c > best.cell { best = (cols, c) }
        }
        let cell = fixed.map { min($0, best.cell) } ?? best.cell
        let cols = best.cols
        let rowsN = (count + cols - 1) / cols
        let inset = cell * wall
        let bw = cell * CGFloat(columns) + inset * 2
        let bh = cell * CGFloat(rows)
        let itemH = bh + inset * 2 + label
        let gridW = bw * CGFloat(cols) + gap * CGFloat(cols - 1)
        let gridH = itemH * CGFloat(rowsN) + gap * CGFloat(rowsN - 1)
        let x0 = area.minX + (area.width - gridW) / 2
        let y0 = top ? area.maxY : area.maxY - (area.height - gridH) / 2
        var items: [CGRect] = []
        var boxes: [CGRect] = []
        for i in 0..<count {
            let row = i / cols
            let col = i % cols
            // A short last row is centred.
            let inRow = row == rowsN - 1 ? count - row * cols : cols
            let rowW = bw * CGFloat(inRow) + gap * CGFloat(inRow - 1)
            let x = (inRow < cols ? area.minX + (area.width - rowW) / 2 : x0) + CGFloat(col) * (bw + gap)
            let y = y0 - CGFloat(row + 1) * itemH - CGFloat(row) * gap
            items.append(CGRect(x: x, y: y, width: bw, height: itemH))
            boxes.append(CGRect(x: x + inset, y: y + label + inset, width: bw - inset * 2, height: bh))
        }
        return (items, boxes, cell)
    }

    /// A tipped box (out of the round) leans this far about the middle of its foot and shrinks to this.
    public static let tipAngle: CGFloat = 0.05
    public static let tipScale: CGFloat = 0.88

    /// A tipped box drawn at `rect` stays inside `rect` widened by `margin` on each side.
    public static func tipFits(_ rect: CGRect, margin: CGFloat) -> Bool {
        let shrink = rect.width * (1 - tipScale) / 2
        let lean = rect.height * tipScale * sin(tipAngle) + rect.width * tipScale / 2 * (1 - cos(tipAngle))
        return lean <= shrink + margin
    }

    /// A cell's rect inside a box drawn at `rect` (x 0 to 11 left to right, y 0 at the bottom).
    public static func cellRect(_ x: Int, _ y: Int, in rect: CGRect) -> CGRect {
        let c = rect.width / CGFloat(columns)
        return CGRect(x: rect.minX + CGFloat(x) * c, y: rect.minY + CGFloat(y) * c, width: c, height: c)
    }

    /// The column a point over a box is in, clamped.
    public static func column(at x: CGFloat, in rect: CGRect) -> Int {
        let c = rect.width / CGFloat(columns)
        return min(max(Int(((x - rect.minX) / c).rounded(.down)), 0), columns - 1)
    }
}

/// Which seats get a box on a Toy Tumble table, as the web's TV and player draw them.
public enum TumbleSeating {
    /// Seats playing this round: a seat that left the game, or sits this round out as Away, gets
    /// no box (it stays on the standings). `mine` is left out while this device plays its own box.
    public static func boxes(_ view: TumbleView, mine: Int?, watching: Bool) -> [Int] {
        (0..<view.seats).filter { s in
            !(view.left.indices.contains(s) && view.left[s]) && !(view.away.indices.contains(s) && view.away[s])
                && (watching || s != mine)
        }
    }
}

/// Toy Tumble's look that every client shares (spec §3): which of the four toy colours each shape
/// wears. Four colours across nine shapes, so no shape-to-colour mapping can echo the classic
/// game's: the long 4-cell toy is never cyan, the square never yellow, the T never purple (and
/// the L never orange).
public enum TumbleLook {
    public static func suit(_ toy: TumbleToy) -> TileSuit {
        switch toy {
        case .i3, .t4, .u5: .fish
        case .v3, .l4: .bell
        case .i4, .j4: .feather
        case .o4, .p5: .mouse
        }
    }

    /// A settled cell's look: its toy's colour, or nil for junk and empty cells.
    public static func suit(cell: Int) -> TileSuit? { TumbleToy(cell: cell).map(suit) }
}
