import CoreGraphics

/// Pure geometry for Birdwatch's table (design §5.2), in SpriteKit scene points (origin
/// bottom-left, y up), for the real view size.
///
/// A phone or iPad, top to bottom: the top band (the paw menu at its left), the window (every
/// other seat's cat on an arc around it, the sill in its middle with the trump badge and the bid
/// chip on its top corners), the score strip, and the hand: one row of cards, or two when one
/// row would hide their numerals. The phase panels (bid, put back, trump) sit on the sill, which
/// is empty while they are up.
///
/// `.handOnly` is a phone at a table a TV shows: the top band with a status line under it, the
/// sill's room for the panels, and the hand, bigger. No cats, no strip.
///
/// `.tv` is the TV across the room (1920 by 1080 points): every seat on the arc (seat 0 at the
/// bottom, then in play order to its left), the sill in the middle, the score strip along the
/// bottom with the turn banner over it. No hand, no controls.
public struct BirdLayout: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case table, handOnly, tv }

    /// A card is this much taller than it is wide.
    public static let cardAspect: CGFloat = 1.42
    public static let buttonHit: CGFloat = 44
    /// The least of a card's width that shows when cards overlap in the hand: its numeral and toy.
    public static let minPeek: CGFloat = 0.4
    /// A cat's name tag (and its bid sign) hang this much of the cat's side below it.
    public static let nameDrop: CGFloat = 0.32

    public let size: CGSize
    public let mode: Mode
    public let roomy: Bool
    public let topBand: CGRect
    public let menuButton: CGPoint
    public let statusLine: CGRect
    /// The cats, in the order asked for (`barSeats`, or every seat on a TV).
    public let seatSpots: [CGPoint]
    public let catSide: CGFloat
    public let window: CGRect
    public let sill: CGRect
    public let sillCard: CGSize
    public let trumpBadge: CGPoint
    public let bidChip: CGPoint
    public let strip: CGRect
    public let hand: CGRect
    public let cardSize: CGSize
    /// TV only: the turn banner's middle.
    public let banner: CGPoint

    /// `others` is how many cats sit around the window (every seat on a TV). `handCount` sizes the
    /// hand's band (one row or two).
    public init(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, others: Int, handCount: Int, mode: Mode = .table) {
        self.size = size
        self.mode = mode
        let w = size.width
        let h = size.height
        roomy = mode == .tv || min(w, h) >= 640
        let top = h - safeTop
        let bottom = safeBottom

        if mode == .tv {
            topBand = .zero
            menuButton = CGPoint(x: w - 90, y: h - 70)
            statusLine = .zero
            catSide = 150
            cardSize = .zero
            hand = .zero
            strip = CGRect(x: 160, y: bottom + 40, width: w - 320, height: 92)
            banner = CGPoint(x: w / 2, y: strip.maxY + 46)
            window = CGRect(x: 60, y: strip.maxY + 90, width: w - 120, height: top - strip.maxY - 120)
            sillCard = CGSize(width: 150, height: 150 * Self.cardAspect)
            sill = window.insetBy(dx: window.width * 0.27, dy: window.height * 0.2)
            seatSpots = Self.arc(count: others, in: window, cat: catSide, full: true)
        } else {
            let band: CGFloat = roomy ? 70 : 52
            topBand = CGRect(x: 0, y: top - band, width: w, height: band)
            menuButton = CGPoint(x: (roomy ? 44 : 30), y: topBand.midY)
            banner = .zero
            let maxCard: CGFloat = mode == .handOnly ? (roomy ? 120 : 84) : (roomy ? 96 : 66)
            let cw = min(maxCard, max(50, w * (mode == .handOnly ? 0.2 : 0.165)))
            cardSize = CGSize(width: cw, height: (cw * Self.cardAspect).rounded())
            let rows = Self.rows(count: handCount, width: w - 16, card: cw)
            let handHeight = cardSize.height + (rows == 2 ? cardSize.height * 0.5 : 0) + 22
            hand = CGRect(x: 8, y: bottom + 6, width: w - 16, height: handHeight)
            if mode == .handOnly {
                statusLine = CGRect(x: 16, y: topBand.minY - 34, width: w - 32, height: 30)
                strip = .zero
                catSide = 0
                seatSpots = []
                window = CGRect(x: 0, y: hand.maxY + 8, width: w, height: statusLine.minY - hand.maxY - 16)
                sill = window.insetBy(dx: 16, dy: 8)
                sillCard = CGSize(width: cw * 0.8, height: cw * 0.8 * Self.cardAspect)
            } else {
                statusLine = .zero
                let stripHeight: CGFloat = roomy ? 52 : 40
                strip = CGRect(x: 12, y: hand.maxY + 8, width: w - 24, height: stripHeight)
                window = CGRect(x: 0, y: strip.maxY + 6, width: w, height: max(topBand.minY - strip.maxY - 6, 120))
                catSide = min(roomy ? 110 : 70, max(48, min(w * 0.17, window.height * 0.22)))
                seatSpots = Self.arc(count: others, in: window, cat: catSide, full: false)
                // The sill is a wide band along the window's bottom, under every cat and its tag.
                var sillTop = window.minY + 10 + (roomy ? 460 : 320)
                for spot in seatSpots { sillTop = min(sillTop, spot.y - catSide * (0.5 + Self.nameDrop) - 4) }
                let sw = min(window.width - 28, roomy ? 760 : 420)
                sill = CGRect(x: window.midX - sw / 2, y: window.minY + 10, width: sw, height: max(sillTop - window.minY - 10, 110))
                let sc = min(cw * 0.95, sill.height * 0.44 / Self.cardAspect, sill.width * 0.2)
                sillCard = CGSize(width: sc, height: sc * Self.cardAspect)
            }
        }
        trumpBadge = CGPoint(x: sill.maxX - (roomy ? 34 : 22), y: sill.maxY - (roomy ? 34 : 22))
        bidChip = CGPoint(x: sill.minX + (roomy ? 48 : 34), y: sill.maxY - (roomy ? 34 : 22))
    }

    /// Cats on the window's arc. A table puts them from the left edge over the top to the right
    /// (play goes left from the bottom seat); a TV puts every seat around, seat 0 at the bottom.
    static func arc(count: Int, in window: CGRect, cat: CGFloat, full: Bool) -> [CGPoint] {
        guard count > 0 else { return [] }
        let cx = window.midX
        let rx = window.width / 2 - cat * 0.62 - 6
        if full {
            let cy = window.midY
            let ry = window.height / 2 - cat * 0.55
            return (0..<count).map { i in
                let a = (270 - Double(i) * 360 / Double(count)) * .pi / 180
                return CGPoint(x: cx + CGFloat(cos(a)) * rx, y: cy + CGFloat(sin(a)) * ry)
            }
        }
        // The cats ride the window's top half, from its middle up and over; the sill is below them.
        let cy = window.minY + window.height * 0.52
        let ry = window.maxY - cat * 0.62 - cy
        if count == 1 { return [CGPoint(x: cx, y: cy + ry)] }
        return (0..<count).map { i in
            let a = (180 - Double(i) * 180 / Double(count - 1)) * .pi / 180
            return CGPoint(x: cx + CGFloat(cos(a)) * rx, y: cy + CGFloat(sin(a)) * ry)
        }
    }

    /// One row unless it would show less than `minPeek` of each card.
    static func rows(count: Int, width: CGFloat, card: CGFloat) -> Int {
        guard count > 1 else { return 1 }
        let step = (width - card) / CGFloat(count - 1)
        return step >= card * minPeek ? 1 : 2
    }

    public func handRows(count: Int) -> Int { Self.rows(count: count, width: hand.width, card: cardSize.width) }

    /// Each card's middle in the hand, left to right (two rows: the first half behind, higher).
    public func handSlots(count: Int) -> [CGPoint] {
        guard count > 0, cardSize.width > 0 else { return [] }
        let cw = cardSize.width
        let rows = Self.rows(count: count, width: hand.width, card: cw)
        func row(_ n: Int, y: CGFloat) -> [CGPoint] {
            guard n > 0 else { return [] }
            let step = n > 1 ? min((hand.width - cw) / CGFloat(n - 1), cw * 0.92) : 0
            let span = cw + step * CGFloat(n - 1)
            let x0 = hand.midX - span / 2 + cw / 2
            return (0..<n).map { CGPoint(x: x0 + step * CGFloat($0), y: y) }
        }
        let low = hand.minY + cardSize.height / 2 + 4
        if rows == 1 { return row(count, y: low) }
        let back = (count + 1) / 2
        return row(back, y: low + cardSize.height * 0.5) + row(count - back, y: low)
    }

    /// The visible strip of each card in a row of `count` (its full width when it doesn't overlap).
    public func peek(count: Int) -> CGFloat {
        let rows = Self.rows(count: count, width: hand.width, card: cardSize.width)
        let n = rows == 1 ? count : (count + 1) / 2
        guard n > 1 else { return cardSize.width }
        return min((hand.width - cardSize.width) / CGFloat(n - 1), cardSize.width * 0.92)
    }

    /// Where a card played by the cat at `spot` lands on the sill: toward its cat. `nil` is the
    /// bottom seat (this phone's hand).
    public func sillSpot(toward spot: CGPoint?) -> CGPoint {
        let c = CGPoint(x: sill.midX, y: sill.midY)
        let dx = sill.width / 2 - sillCard.width * 0.62
        let dy = sill.height / 2 - sillCard.height * 0.56
        guard let spot else { return CGPoint(x: c.x, y: c.y - dy) }
        let angle = atan2(spot.y - c.y, spot.x - c.x)
        return CGPoint(x: c.x + cos(angle) * dx, y: c.y + sin(angle) * dy)
    }
}
