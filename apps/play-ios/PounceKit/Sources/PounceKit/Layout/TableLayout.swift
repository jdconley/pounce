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

/// The SwiftUI chrome a controller layout leaves room for (heights in points). The shell measures
/// it (it grows with Dynamic Type) and passes it in; the cards shrink to make room, never below
/// their minimum.
public struct ControllerChrome: Equatable, Sendable {
    /// The strip under the safe top holding the "Cards" | "Table" switch, with the paw menu at its
    /// right end. Never under 44 (the paw's touch target).
    public var switchBand: CGFloat
    /// The status line under the switch ("Your turn", "Ava's turn").
    public var status: CGFloat
    /// Cat Tower's action row between the piles and the trays (the hit list, Confirm, Lay down).
    public var actions: CGFloat

    public init(switchBand: CGFloat = 44, status: CGFloat = 28, actions: CGFloat = 52) {
        self.switchBand = switchBand
        self.status = status
        self.actions = actions
    }

    /// The chrome at the default text size.
    public static let standard = ControllerChrome()
}

/// What a controller's hand needs room for. The scene decides `short` with some slack (it goes
/// short at six cards or fewer and back at nine or more), so the cards don't change size with
/// every draw and discard.
public struct ControllerHand: Equatable, Sendable {
    /// At most `shortMax` cards: they are drawn bigger.
    public var short: Bool
    /// The lay-down trays show over the hand (before laying down).
    public var trays: Bool

    public init(short: Bool = false, trays: Bool = true) {
        self.short = short
        self.trays = trays
    }

    /// Eleven cards, with trays: the biggest a hand gets.
    public static let full = ControllerHand()
    /// The most cards a short hand's size is made for.
    public static let shortMax = 8
}

/// Pure geometry for the table, in SpriteKit scene points (origin bottom-left, y up).
/// The scene uses `.resizeFill`, so this is computed for the real view size.
///
/// Bands, top to bottom: opponents bar (96 pt, below the safe top), the rug with the
/// deck left and discard right of center, laid-down rows around the piles, phase trays
/// (64 pt) above the hand, and the fanned hand (above the safe bottom). The table is centered;
/// the cat tower folds down to a tab (`towerTab`) at the left end of the sort button's line
/// and opens over the table's left edge (`towerFrame`, between the opponents bar and the
/// trays) only for a look. No two hit-test regions (opponent slots, deck, discard, trays, laid
/// rows, tower tab) overlap; the open tower lies over the laid zone's left edge.
///
/// A roomy view (both sides at least `roomyMinSide`, an iPad window) gets its own
/// `Arrangement` instead of a stretched phone table: bigger cards sized from the shorter
/// side, the opponents seated along an arc across the far side, the piles in the middle of
/// the rug, a hand fan and trays of a comfortable width centered at the bottom. `.tall`
/// keeps the name pill and sort button above the trays' right end; `.wide` (landscape)
/// moves them beside the trays, opens the tower down the whole left edge from a tab in the
/// bottom-left corner, and seats laid
/// rows in columns left and right of the piles when a row per seat doesn't fit above and
/// below them.
///
/// A controller (a phone whose table is on a TV) asks for `.controller` by passing its chrome;
/// it is never chosen from the size. Top to bottom: the switch band (the paw menu at its right
/// end), the status line, the deck and discard (`pileSize`, centred in the room between the
/// status line and the action row), then one block at the bottom: the action row with the sort
/// button at its right end, the trays (none after laying down: `ControllerHand.trays`), and the
/// hand, large (bigger still when short: `ControllerHand.short`). No name pill: the status line
/// names the player. The table around the hand
/// is absent: `opponentsBar`, `towerFrame`, `towerTab` and `laidZone` are `.zero`,
/// `opponentSlots` is empty and `laidRow` is `.zero`.
public struct TableLayout: Sendable {
    /// How the table is arranged for the space it has.
    public enum Arrangement: Sendable, Equatable {
        /// A phone-sized view: the original table.
        case phone
        /// Roomy and portrait-shaped.
        case tall
        /// Roomy and landscape-shaped.
        case wide
        /// A phone or iPad whose table is on a TV: only its own cards (asked for, never chosen
        /// from the size).
        case controller
    }

    /// The shorter side a view needs for a roomy arrangement.
    public static let roomyMinSide: CGFloat = 640

    /// The arrangement a table (not a controller) gets for `size`: never `.controller`.
    public static func arrangement(for size: CGSize) -> Arrangement {
        guard min(size.width, size.height) >= roomyMinSide else { return .phone }
        return size.width > size.height * 1.1 ? .wide : .tall
    }

    public static let opponentsBarHeight: CGFloat = 96
    public static let traysHeight: CGFloat = 64
    public static let towerWidth: CGFloat = 44
    /// The sort button's touch target (drawn 36 pt) at the right, just above the trays.
    public static let sortButtonHit: CGFloat = 44
    public static let shelfCount = 10

    public let size: CGSize
    public let safeTop: CGFloat
    public let safeBottom: CGFloat
    public let arrangement: Arrangement
    public let cardSize: CGSize
    public let miniCardSize: CGSize
    /// The widest an opponent's cat ring gets.
    public let catDiameter: CGFloat
    /// How far above its slot an opponent's cat sits, and how far below it its name pill.
    public let catLift: CGFloat
    public let nameDrop: CGFloat
    /// The tower's mini cat heads.
    public let towerHeadSize: CGFloat

    /// Strip across the top holding the opponent slots.
    public let opponentsBar: CGRect
    /// Opponent avatar centers, evenly spaced, left to right.
    public let opponentSlots: [CGPoint]
    /// Centers of the draw pile and the discard pile.
    public let deck: CGPoint
    public let discard: CGPoint
    /// The cat tower when it is open: over the left edge of the table.
    public let towerFrame: CGRect
    /// The folded tower: a tab at the tower's foot (the tap target that opens it).
    public let towerTab: CGRect
    public let traysFrame: CGRect
    /// Rect all laid-down rows live in (centered, between bar and trays).
    public let laidZone: CGRect
    /// Sort button center; laid rows stop short of its touch target (and the seat's name pill).
    public let sortButton: CGPoint
    /// The paw menu button, top right: its center and drawn side. On a phone with a tall safe
    /// top (a notch or island) it sits in the status bar's right ear, above the cats; with a
    /// short one it is tucked into the opponents bar's corner, and from three cats up the cats
    /// move over to leave that corner free (`menuReserve`).
    public let menuButton: CGPoint
    public let menuSide: CGFloat
    /// The smallest touch target a table button gets.
    public static let buttonHit: CGFloat = 44
    /// Width kept free at the bar's right end for a tucked menu button.
    public static let menuReserve: CGFloat = 48

    /// A controller's strips for the SwiftUI chrome (`.zero` on a table): the switch band under
    /// the safe top (the paw menu at its right end, the switch centred clear of it), the status
    /// line under it, and the action row on the trays (or the hand), the trays' width less the sort
    /// button at its right end.
    public let switchBand: CGRect
    public let statusLine: CGRect
    public let actionRow: CGRect
    /// A controller's hand cards are never narrower than this on a phone (72 on an iPad).
    public static let controllerCardMin: CGFloat = 64
    /// The deck's and the discard's size: `cardSize` on a table. A controller's grow into the
    /// room it has (up to 1.5 hand cards) and shrink to three quarters of a hand card before the
    /// hand gives way, then, once the hand is at its floor, toward `miniCardSize` (never under 44).
    public let pileSize: CGSize
    /// How many points too tall the chrome is for this size (0 when it fits; always 0 on a
    /// table). When it isn't 0 the piles overlap the action row or the status line: the shell
    /// takes that much off its chrome (truncating the status line, say) and lays out again.
    public let chromeOverflow: CGFloat
    /// Everything fits without overlapping.
    public var fits: Bool { chromeOverflow == 0 }

    /// The view is big enough for a roomy table (an iPad window), whatever the arrangement.
    public var roomy: Bool { Self.arrangement(for: size) != .phone }

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
    /// The widest a full-width laid row gets (roomy tables keep rows near the piles).
    private let rowMaxWidth: CGFloat

    private static let handSidePad: CGFloat = 4
    private static let handBottomPad: CGFloat = 4
    private static let liftHeight: CGFloat = 30
    private static let designWidth: CGFloat = 390

    /// - Parameter controller: the chrome of a controller (a phone whose table is on a TV); nil
    ///   for a table.
    ///   - hand: a controller's hand: short or not, with trays or not (ignored on a table).
    public init(
        size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, opponents: Int, controller: ControllerChrome? = nil,
        hand: ControllerHand = .full
    ) {
        if let controller {
            self = Self(controller: controller, hand: hand, size: size, safeTop: safeTop, safeBottom: safeBottom)
            return
        }
        switchBand = .zero
        statusLine = .zero
        actionRow = .zero
        chromeOverflow = 0
        self.size = size
        self.safeTop = safeTop
        self.safeBottom = safeBottom
        let width = size.width
        let arrangement = Self.arrangement(for: size)
        self.arrangement = arrangement
        let roomy = arrangement != .phone

        // Cards: 64 x 90 at 390 pt wide, scaled with the width, 56...76 wide. Roomy: a tenth of
        // the shorter side, 72...104 wide.
        let cardW = roomy
            ? min(max((min(width, size.height) * 0.1).rounded(), 72), 104)
            : min(max(64 * width / Self.designWidth, 56), 76)
        let card = CGSize(width: cardW, height: (cardW * 90 / 64).rounded())
        cardSize = card
        pileSize = card
        // Laid cards: 0.66 of a hand card (41 pt wide on a 375 pt phone), the smallest at which
        // the compact face's two-digit numerals keep an 11 pt cap height.
        miniCardSize = CGSize(width: (cardW * 0.66).rounded(), height: (card.height * 0.66).rounded())

        // Opponents bar and slots. Roomy: a taller bar, the seats spread no wider than a table's
        // far side and curved along it (the middle seats a little further away).
        let barH = roomy ? min(max((cardW * 1.35).rounded(), arrangement == .wide ? 112 : 120), 140) : Self.opponentsBarHeight
        let bar = CGRect(x: 0, y: size.height - safeTop - barH, width: width, height: barH)
        opponentsBar = bar
        let n = min(max(opponents, 1), 6)  // 6: every seat, on a phone that holds none
        let towerW: CGFloat = roomy ? 56 : Self.towerWidth
        let menuSide: CGFloat = roomy ? 44 : 32
        self.menuSide = menuSide
        let inEar = safeTop >= 44
        menuButton = CGPoint(
            x: width - menuSide / 2 - (roomy ? 16 : 10),
            y: inEar ? bar.maxY + menuSide / 2 - 6 : bar.maxY - menuSide / 2 - (roomy ? 6 : 0))
        if roomy {
            let lo = towerW + 16, hi = width - 72  // clear of the tower and the menu button
            let spacing = min((hi - lo) / CGFloat(n), 260)
            let first = (lo + hi) / 2 - spacing * CGFloat(n - 1) / 2
            let half = max(spacing * CGFloat(n - 1) / 2, 1)
            let arc: CGFloat = arrangement == .wide ? 18 : 12
            opponentSlots = (0..<n).map { i in
                let x = first + spacing * CGFloat(i)
                let u = (x - (lo + hi) / 2) / half
                return CGPoint(x: x, y: bar.midY - 4 + arc * (0.5 - u * u))
            }
            catDiameter = (barH * 0.62).rounded()
            catLift = 10
            nameDrop = barH / 2 - 16
            towerHeadSize = 32
        } else {
            // Three or more cats reach the corner a tucked menu button sits in: they share the
            // width left of it, so the button never lies over the last cat.
            let span = !inEar && n >= 3 ? width - Self.menuReserve : width
            opponentSlots = (0..<n).map { CGPoint(x: span * (CGFloat($0) + 0.5) / CGFloat(n), y: bar.midY) }
            catDiameter = 62
            catLift = 8
            nameDrop = barH / 2 - 12
            towerHeadSize = 26
        }

        // Hand fan: a circular arc of radius `fanRadius` centered below the hand. The
        // outermost card sits fully inside the width once its rotated corners are counted.
        // Roomy: the fan is as wide as a dozen cards at their full step, at most.
        let handHalf = roomy
            ? min(width / 2 - Self.handSidePad, (cardW + cardW * 0.72 * 11) / 2)
            : width / 2 - Self.handSidePad
        let radius = roomy ? handHalf * 3 : width * 1.5
        fanRadius = radius
        let fan = Self.fan(card: card, half: handHalf, radius: radius)
        handSpan = fan.span
        let baseY = safeBottom + (roomy ? 12 : Self.handBottomPad) + fan.rise
        handBaseY = baseY
        let handTop = baseY + card.height / 2 + 4

        // Trays sit just above the hand. Roomy: centered, no wider than the fan (wide: with
        // room left for the name pill and right for the sort button beside them).
        let trays: CGRect
        switch arrangement {
        case .phone, .controller:  // a controller never comes this way
            trays = CGRect(x: 8, y: handTop + 6, width: width - 16, height: Self.traysHeight)
            sortButton = CGPoint(x: width - 26, y: trays.maxY + 24)
        case .tall:
            let w = min(width - 32, max(handHalf * 2 + 40, 560), 820)
            trays = CGRect(x: (width - w) / 2, y: handTop + 8, width: w, height: min(max((cardW * 0.84).rounded(), 72), 88))
            sortButton = CGPoint(x: trays.maxX - 22, y: trays.maxY + 28)
        case .wide:
            let w = max(min(max(handHalf * 2 + 40, 560), 820, width - 2 * (towerW + Self.seatTagWidth + 24)), 240)
            trays = CGRect(x: (width - w) / 2, y: handTop + 8, width: w, height: min(max((cardW * 0.84).rounded(), 72), 88))
            sortButton = CGPoint(x: trays.maxX + 12 + Self.sortButtonHit / 2, y: trays.midY)
        }
        traysFrame = trays

        // Tower: left edge, from above the trays to below the opponents bar (wide: from the
        // bottom, since the trays and the hand stay in the middle). It opens over the table, so
        // nothing is laid out around it. Folded, it is a tab at its foot: at the left end of the
        // sort button's line, mirroring the button (wide: in the bottom-left corner).
        let towerBottom = arrangement == .wide ? safeBottom + 12 : trays.maxY + 6
        towerFrame = CGRect(x: 0, y: towerBottom, width: towerW, height: bar.minY - 4 - towerBottom)
        let tab = Self.sortButtonHit
        switch arrangement {
        case .phone, .controller:
            towerTab = CGRect(x: width - sortButton.x - tab / 2, y: sortButton.y - tab / 2, width: tab, height: tab)
        case .tall:
            towerTab = CGRect(x: trays.minX, y: sortButton.y - tab / 2, width: tab, height: tab)
        case .wide:
            towerTab = CGRect(x: 16, y: towerBottom, width: tab, height: tab)
        }

        // Laid zone: centered, between the bar and the trays (tall: and above the name pill's
        // strip).
        let zone: CGRect
        switch arrangement {
        case .phone, .controller:
            zone = CGRect(x: 8, y: towerBottom, width: width - 16, height: bar.minY - 8 - towerBottom)
        case .tall, .wide:
            let zoneMinY = arrangement == .tall ? sortButton.y + Self.sortButtonHit / 2 + 6 : trays.maxY + 12
            zone = CGRect(x: 16, y: zoneMinY, width: width - 32, height: bar.minY - 8 - zoneMinY)
        }
        laidZone = zone

        // Rows: two columns; rows above and below the piles hug them.
        let gap: CGFloat = 8
        let rowH = miniCardSize.height + 8
        rowHeight = rowH
        rowGap = gap
        columnGap = 8
        columnWidth = (zone.width - 8) / 2
        rowMaxWidth = roomy ? 760 : .infinity

        // Pile height is fixed by the largest table (3 laid rows: 1 above, 2 below) so the
        // piles never jump between player counts. Centered, unless that puts the lowest row
        // beside the sort button: then raised as far as it takes (or fits). Roomy: the middle
        // of the zone (the sort button is never beside a row).
        let stack = 3 * rowH + 4 * gap + card.height
        let clearOfSort = zone.maxY - stack + gap - (sortButton.y + Self.sortButtonHit / 2) - 1
        let slack = max(min((zone.height - stack) / 2, clearOfSort), 0)
        let pilesY = roomy ? zone.midY : zone.maxY - slack - rowH - gap - card.height / 2
        let pileOffset = card.width / 2 + (roomy ? 12 : 8)
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

    /// A controller: only its own cards (see the type's notes). The hand comes first: its cards
    /// are as big as eleven can fan with each card's corner still showing (`stripRatio`), or, for a
    /// short hand (`ControllerHand.short`), bigger still. The trays (when there are any) sit on the
    /// hand, the action row on them with the sort button at its right end, and the piles take the
    /// room left between it and the status line, centred in it. Tall chrome shrinks the piles
    /// first (down to three quarters of a hand card), then the hand to its floor, then the piles to
    /// a touch target (`pileSize`, `chromeOverflow`).
    private init(controller chrome: ControllerChrome, hand: ControllerHand, size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) {
        self.size = size
        self.safeTop = safeTop
        self.safeBottom = safeBottom
        arrangement = .controller
        let width = size.width
        let roomy = Self.arrangement(for: size) != .phone
        let side: CGFloat = roomy ? 16 : 8
        let gap: CGFloat = roomy ? 12 : 8  // between the status line, the piles and the action row

        // The chrome's strips, under the safe top.
        let top = Self.controllerTop(size: size, safeTop: safeTop, chrome: chrome)
        let actionsH = max(chrome.actions, Self.sortButtonHit)
        switchBand = top.switchBand
        statusLine = top.statusLine
        menuSide = roomy ? 44 : 32
        menuButton = top.menuButton

        let bottomPad: CGFloat = roomy ? 12 : Self.handBottomPad
        let traysPad: CGFloat = roomy ? 8 : 6
        let floor: CGFloat = roomy ? 72 : Self.controllerCardMin
        func card(_ w: CGFloat) -> CGSize { CGSize(width: w, height: (w * 90 / 64).rounded()) }
        func handHalf(_ w: CGFloat) -> CGFloat {
            roomy ? min(width / 2 - Self.handSidePad, (w + w * 0.72 * 11) / 2) : width / 2 - Self.handSidePad
        }
        func radius(_ w: CGFloat) -> CGFloat { roomy ? handHalf(w) * 3 : width * 1.5 }
        /// The step between neighbouring cards in a fan of `n` cards `w` wide.
        func step(_ w: CGFloat, _ n: Int) -> CGFloat {
            let fan = Self.fan(card: card(w), half: handHalf(w), radius: radius(w))
            return min(w * 0.72, 2 * fan.span / CGFloat(n - 1))
        }
        /// The widest card at most `cap` for which a fan of `n` shows `stripRatio` of each face.
        func widest(_ n: Int, cap: CGFloat) -> CGFloat {
            var w = cap.rounded(.down)
            while w > floor, step(w, n) < w * Self.stripRatio { w -= 1 }
            return w
        }
        // An eleven-card hand, never past a fifth of the safe height tall (a squat screen).
        let safeH = size.height - safeTop - safeBottom
        let fullCap = min(roomy ? 140 : 120, (safeH / 5.5 * 64 / 90).rounded(.down))
        let full = max(widest(11, cap: fullCap), floor)
        // A short hand (eight cards at most): a third bigger, as far as eight can still fan and
        // within two ninths of the safe height.
        let shortCap = min((full * 4 / 3).rounded(.down), (safeH / 4.5 * 64 / 90).rounded(.down))
        let preferred = hand.short ? max(widest(ControllerHand.shortMax, cap: shortCap), full) : full

        func traysHeight(_ w: CGFloat) -> CGFloat {
            hand.trays ? min(max((w * 0.84).rounded(), 64), roomy ? 120 : 88) : 0
        }
        /// The top of the action row with hand cards `w` wide.
        func actionTop(_ w: CGFloat) -> CGFloat {
            let c = card(w)
            let handTop = safeBottom + bottomPad + Self.fan(card: c, half: handHalf(w), radius: radius(w)).rise + c.height / 2 + 4
            let trays = hand.trays ? traysPad + traysHeight(w) : 0
            return handTop + trays + 6 + actionsH
        }
        /// The height left for the piles, with a gap above and below them.
        func pileRoom(_ w: CGFloat) -> CGFloat { top.statusLine.minY - gap - actionTop(w) - gap }
        // Tall chrome: the piles give way to three quarters of a hand card, then the hand shrinks.
        var cardW = preferred
        while cardW > floor, pileRoom(cardW) < card((cardW * 0.75).rounded(.down)).height { cardW -= 1 }
        let c = card(cardW)
        cardSize = c
        miniCardSize = CGSize(width: (cardW * 0.66).rounded(), height: (c.height * 0.66).rounded())

        // The piles: as big as the room allows, up to 1.5 hand cards and no wider than two fit
        // side by side; short of room, down to a laid card's size (44 pt at least, a touch
        // target); short even of that, `chromeOverflow` says by how much.
        let room = pileRoom(cardW)
        let pileGap: CGFloat = roomy ? 12 : 8  // from the middle to each pile's inner edge
        let pileMin = max(miniCardSize.width, Self.buttonHit)
        let pileMax = max(min((cardW * 1.5).rounded(.down), ((width - 2 * side) / 2 - pileGap).rounded(.down)), pileMin)
        var fitting = (room * 64 / 90).rounded(.down)
        while fitting > pileMin, card(fitting).height > room { fitting -= 1 }
        let pile = card(min(max(fitting, pileMin), pileMax))
        pileSize = pile
        chromeOverflow = max(pile.height - room, 0)
        var leftover = max(room - pile.height, 0)
        // Trays take up to half of what is left, up to 88 tall on a phone (120 roomy).
        let trayGrow = hand.trays
            ? min((leftover / 2).rounded(.down), max((roomy ? 120 : 88) - traysHeight(cardW), 0)) : 0
        leftover -= trayGrow

        // The hand, at the bottom.
        let half = handHalf(cardW)
        fanRadius = radius(cardW)
        let fan = Self.fan(card: c, half: half, radius: fanRadius)
        handSpan = fan.span
        handBaseY = safeBottom + bottomPad + fan.rise
        let handTop = handBaseY + c.height / 2 + 4

        // The trays on it (none: an empty strip), then the action row with the sort button at its
        // right end.
        let traysW = roomy ? min(width - 32, max(half * 2 + 40, 560), 820) : width - 2 * side
        let traysX = (width - traysW) / 2
        let trays = hand.trays
            ? CGRect(x: traysX, y: handTop + traysPad, width: traysW, height: traysHeight(cardW) + trayGrow)
            : CGRect(x: traysX, y: handTop, width: traysW, height: 0)
        traysFrame = trays
        let actionY = trays.maxY + 6
        let sortW = Self.sortButtonHit + 4
        actionRow = CGRect(x: traysX, y: actionY, width: traysW - sortW, height: actionsH)
        // The sort button on the action row's bottom line, at its right end.
        sortButton = CGPoint(x: traysX + traysW - Self.sortButtonHit / 2, y: actionY + min(actionsH, 52) / 2)

        // The piles in the middle of the room between the action row and the status line.
        let pilesY = actionY + actionsH + gap + leftover / 2 + pile.height / 2
        let pileOffset = pile.width / 2 + pileGap
        deck = CGPoint(x: width / 2 - pileOffset, y: pilesY)
        discard = CGPoint(x: width / 2 + pileOffset, y: pilesY)

        // No table around the hand.
        opponentsBar = .zero
        opponentSlots = []
        towerFrame = .zero
        towerTab = .zero
        laidZone = .zero
        catDiameter = roomy ? 74 : 62
        catLift = roomy ? 10 : 8
        nameDrop = roomy ? 44 : 36
        towerHeadSize = roomy ? 32 : 26
        rowHeight = miniCardSize.height + 8
        columnWidth = 0
        columnGap = 8
        rowGap = 8
        rowsAboveCapacity = 0
        rowsBelowCapacity = 0
        rowMaxWidth = .infinity
    }

    /// The share of each card's face a controller's fan shows at least (its corner number).
    public static let stripRatio: CGFloat = 0.34

    /// A controller's switch band and status line, under the safe top and a side margin, and the
    /// paw menu's center at the band's right end (its 44 pt target inside the band). Shared with
    /// the tile game's controller.
    static func controllerTop(size: CGSize, safeTop: CGFloat, chrome: ControllerChrome)
        -> (switchBand: CGRect, statusLine: CGRect, menuButton: CGPoint)
    {
        let side: CGFloat = arrangement(for: size) != .phone ? 16 : 8
        let switchH = max(chrome.switchBand, buttonHit)
        let band = CGRect(x: side, y: size.height - safeTop - switchH, width: size.width - 2 * side, height: switchH)
        let status = CGRect(x: side, y: band.minY - max(chrome.status, 0), width: band.width, height: max(chrome.status, 0))
        return (band, status, CGPoint(x: band.maxX - buttonHit / 2, y: band.midY))
    }

    /// A fan of `card`s whose outermost card reaches `half` from the middle (rotated corners
    /// counted) on an arc of `radius`: how far the outermost card's center is from the middle,
    /// and how far the middle card's center sits above the fan's lowest point.
    private static func fan(card: CGSize, half: CGFloat, radius: CGFloat) -> (span: CGFloat, rise: CGFloat) {
        var edge = half - card.width / 2
        for _ in 0..<6 {
            let t = edge / radius
            edge = half - (card.width / 2 * cos(t) + card.height / 2 * sin(t))
        }
        let tMax = edge / radius
        let drop = edge * edge / (2 * radius)
        let edgeHalfHeight = card.height / 2 * cos(tMax) + card.width / 2 * sin(tMax)
        return (edge, drop + edgeHalfHeight)
    }

    /// The menu button's touch target.
    public var menuButtonFrame: CGRect {
        let d = max(menuSide, Self.buttonHit)
        return CGRect(x: menuButton.x - d / 2, y: menuButton.y - d / 2, width: d, height: d)
    }

    /// The distance between neighboring cats in the top bar (the whole width for one).
    public var opponentSpacing: CGFloat {
        opponentSlots.count > 1 ? opponentSlots[1].x - opponentSlots[0].x : size.width
    }

    /// A cat's ring in the top bar: `catDiameter`, less when the bar is crowded.
    public var opponentDiameter: CGFloat { min(catDiameter, opponentSpacing - 12) }

    /// The touch target of the cat in slot `index` of the top bar (at least 44 pt).
    public func opponentFrame(_ index: Int) -> CGRect {
        guard opponentSlots.indices.contains(index) else { return .zero }
        let d = max(opponentDiameter, Self.buttonHit)
        let c = opponentSlots[index]
        return CGRect(x: c.x - d / 2, y: c.y + catLift - d / 2, width: d, height: d)
    }

    /// Which of two overlapping touch targets a tap at `p` belongs to: the one whose center is
    /// nearer. True when `p` is the menu button's rather than the cat's in slot `index`.
    public func menuWins(at p: CGPoint, overCat index: Int) -> Bool {
        guard opponentSlots.indices.contains(index) else { return true }
        let cat = CGPoint(x: opponentSlots[index].x, y: opponentSlots[index].y + catLift)
        return hypot(p.x - menuButton.x, p.y - menuButton.y) <= hypot(p.x - cat.x, p.y - cat.y)
    }

    public var sortButtonFrame: CGRect {
        let d = Self.sortButtonHit
        return CGRect(x: sortButton.x - d / 2, y: sortButton.y - d / 2, width: d, height: d)
    }

    /// The widest the bottom seat's name pill gets.
    public static let seatTagWidth: CGFloat = 150
    public static let seatTagHeight: CGFloat = 26

    /// Where the bottom seat's name pill may sit (it is right-aligned in here): just left of
    /// the sort button, on its line (wide: just left of the trays). Laid rows stop short of it too.
    public var seatTagFrame: CGRect {
        // A controller names the player in its status line.
        guard arrangement != .controller else { return .zero }
        let right = arrangement == .wide ? traysFrame.minX - 8 : sortButtonFrame.minX - 4
        return CGRect(
            x: right - Self.seatTagWidth, y: sortButton.y - Self.seatTagHeight / 2,
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

    /// The columns left and right of the piles (wide tables), if `rows` rows fit in them.
    private func sideColumns(rows: Int) -> [CGRect]? {
        let pilesHalf = discard.x - laidZone.midX + cardSize.width / 2
        let w = laidZone.width / 2 - pilesHalf - 20
        guard w >= 240, CGFloat(rows) * (rowHeight + rowGap) - rowGap <= laidZone.height else { return nil }
        return [
            CGRect(x: laidZone.minX, y: laidZone.minY, width: w, height: laidZone.height),
            CGRect(x: laidZone.maxX - w, y: laidZone.minY, width: w, height: laidZone.height),
        ]
    }

    /// Distance between neighboring card centers in a fan of `count`.
    private func handStep(count: Int) -> CGFloat {
        count > 1 ? min(cardSize.width * 0.72, 2 * handSpan / CGFloat(count - 1)) : 0
    }

    /// Laid-down row for seat `slot` of `total` seats. When a row per seat fits above and below
    /// the piles, each row spans the zone (seats top to bottom, the upper half above the
    /// piles). Otherwise two columns; rows above the piles fill from the top, rows below from
    /// the piles down, and a lone last row is centered.
    ///
    /// Wide (landscape) tables that can't give each seat a full row put the rows in a column
    /// on each side of the piles instead, seats alternating left and right, top to bottom.
    public func laidRow(slot: Int, of total: Int) -> CGRect {
        guard arrangement != .controller else { return .zero }  // a controller lays nothing out
        let total = max(total, 1)
        let slot = min(max(slot, 0), total - 1)
        let r: Int, rowsAbove: Int, x: CGFloat, width: CGFloat
        if total <= rowsAboveCapacity + rowsBelowCapacity {
            rowsAbove = max(total - rowsBelowCapacity, min(rowsAboveCapacity, total / 2))
            r = slot
            width = min(laidZone.width, rowMaxWidth)
            x = width < laidZone.width ? laidZone.midX - width / 2 : laidZone.minX
        } else if arrangement == .wide, let side = sideColumns(rows: (total + 1) / 2) {
            let rows = (total + 1) / 2
            let column = side[slot % 2]
            let midY = deck.y + (CGFloat(rows - 1) / 2 - CGFloat(slot / 2)) * (rowHeight + rowGap)
            return CGRect(x: column.minX, y: midY - rowHeight / 2, width: column.width, height: rowHeight)
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
        if row.intersects(towerTab) {
            let left = towerTab.maxX + 4
            row = CGRect(x: left, y: row.minY, width: max(row.maxX - left, 0), height: row.height)
        }
        return row
    }
}
