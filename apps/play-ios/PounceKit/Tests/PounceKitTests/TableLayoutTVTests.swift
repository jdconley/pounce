import CoreGraphics
import Testing
@testable import PounceKit

/// Geometry both games' TV tests share.
enum TVGeometry {
    /// The frames a TV table is checked on: an Apple TV's 1920 x 1080 points with its TV-safe
    /// insets and without, 720p, 4K with the insets doubled, and a TV that overscans 54 points.
    static let frames: [(name: String, size: CGSize, insets: TVInsets)] = [
        ("1080 TV-safe", CGSize(width: 1920, height: 1080), .tvSafe),
        ("1080 full", CGSize(width: 1920, height: 1080), .zero),
        ("720 TV-safe", CGSize(width: 1280, height: 720), TVInsets.tvSafe.scaled(by: 2.0 / 3)),
        ("720 full", CGSize(width: 1280, height: 720), .zero),
        ("4K TV-safe", CGSize(width: 3840, height: 2160), TVInsets.tvSafe.scaled(by: 2)),
        ("1080 overscan", CGSize(width: 1920, height: 1080), TVInsets(all: 54)),
    ]
    /// The 1080 frames: what an Apple TV lays out for, with its insets and without.
    static let hd = [0, 1]

    static func safe(_ size: CGSize, _ i: TVInsets) -> CGRect {
        CGRect(x: i.left, y: i.bottom, width: size.width - i.left - i.right, height: size.height - i.top - i.bottom)
    }

    /// Inside `frame`, within half a point.
    static func inside(_ r: CGRect, _ frame: CGRect) -> Bool {
        r.minX >= frame.minX - 0.5 && r.minY >= frame.minY - 0.5 && r.maxX <= frame.maxX + 0.5 && r.maxY <= frame.maxY + 0.5
    }

    /// Two rects overlap when they share more than half a point each way.
    static func overlap(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxX, b.maxX) - max(a.minX, b.minX) > 0.5 && min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0.5
    }

    static func box(_ c: CGPoint, _ size: CGSize) -> CGRect {
        CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
    }

    static func circle(_ c: CGPoint, _ d: CGFloat) -> CGRect { box(c, CGSize(width: d, height: d)) }

    static func pairs<T>(_ xs: [T]) -> [(T, T)] {
        xs.indices.flatMap { i in xs[(i + 1)...].map { (xs[i], $0) } }
    }

    /// No pair of `a` and `b` overlaps.
    static func clear(_ a: [CGRect], _ b: [CGRect], _ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for x in a {
            for y in b where x != y {
                #expect(!overlap(x, y), "\(what): \(x) and \(y)", sourceLocation: sourceLocation)
            }
        }
    }

    static func doubled(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(b.minX - 2 * a.minX) <= 1 && abs(b.minY - 2 * a.minY) <= 1 && abs(b.width - 2 * a.width) <= 1
            && abs(b.height - 2 * a.height) <= 1
    }

    static func doubled(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(b.x - 2 * a.x) <= 1 && abs(b.y - 2 * a.y) <= 1 }
}

/// Cat Tower on a TV across the room: every seat around the table, the piles in the middle, each
/// seat's laid groups beside it, the tower down the left, the turn banner along the bottom and
/// the menu in the bottom-right corner. No hand, no trays. The web's TV table
/// (`apps/play-web/src/table/ct-layout.ts`, `tests/layout.test.ts`) is the reference, planned
/// here for two groups of twelve a seat (every phase lays down at most two; hits grow a run to
/// twelve) with every corner numeral whole.
@Suite("TableLayout, TV")
struct TableLayoutTVTests {
    typealias G = TVGeometry

    enum Table: CaseIterable { case full, sparse }

    /// The worst table, every seat down with two groups of twelve, or a sparse one: the first and
    /// last seats down with a phase's groups, nobody else.
    static func groups(_ n: Int, _ table: Table) -> [[Int]] {
        (0..<n).map { s in table == .full ? [12, 12] : (s == 0 || s == n - 1 ? [4, 4] : []) }
    }

    static let cases: [(Int, Int, Table)] = G.frames.indices.flatMap { f in
        (2...6).flatMap { n in Table.allCases.map { (f, n, $0) } }
    }

    private func layout(_ f: Int, _ n: Int) -> TableLayout {
        let frame = G.frames[f]
        return TableLayout(tv: frame.size, insets: frame.insets, seats: n)
    }

    /// Every laid group's frame and its cards' boxes.
    private func laid(_ l: TableLayout, _ n: Int, _ table: Table) -> (groups: [CGRect], cards: [CGRect]) {
        let placed = (0..<n).flatMap { l.tvGroups(seat: $0, counts: Self.groups(n, table)[$0]) }
        return (placed.map(\.frame), placed.flatMap { g in g.cards.map { G.box($0, g.cardSize) } })
    }

    @Test(arguments: G.frames.indices, 2...6)
    func nothingPrivateAndEverySeatAroundTheTable(_ f: Int, _ n: Int) {
        let l = layout(f, n)
        #expect(l.arrangement == .tv)
        #expect(l.hand(count: 11, lifted: nil).isEmpty)
        #expect(l.hand(count: 11, gap: 3).isEmpty)
        #expect(l.trayFrames(count: 3).isEmpty)
        #expect(l.traysFrame == .zero)
        #expect(l.towerTab == .zero)
        #expect(l.sortButtonFrame == .zero)
        #expect(l.seatTagFrame == .zero)
        #expect(l.opponentsBar == .zero)
        #expect(l.switchBand == .zero && l.statusLine == .zero && l.actionRow == .zero)
        #expect(l.seatFrames.count == n)
        #expect(l.opponentSlots.count == n)
        #expect(l.fits)
        // A size alone never asks for a TV.
        #expect(TableLayout.arrangement(for: G.frames[f].size) != .tv)
    }

    @Test(arguments: cases)
    func everythingIsInsideTheSafeFrame(_ f: Int, _ n: Int, _ table: Table) {
        let l = layout(f, n)
        let safe = G.safe(G.frames[f].size, G.frames[f].insets)
        let laid = laid(l, n, table)
        var rects = [l.towerFrame, l.rug, G.box(l.deck, l.pileSize), G.box(l.discard, l.pileSize), l.banner, l.bannerRoom, l.menuButtonFrame]
        rects += l.seatFrames + l.opponentSlots.map { G.circle($0, l.catDiameter) } + laid.groups + laid.cards
        rects += (0..<n).map { l.laidRow(slot: $0, of: n) }
        for r in rects { #expect(G.inside(r, safe), "\(r) outside \(safe)") }
        // The tower's shelves stay in it.
        for i in 0..<TableLayout.shelfCount { #expect(l.towerFrame.contains(l.shelf(i))) }
    }

    @Test(arguments: cases)
    func seatsGroupsPilesTowerBannerAndMenuNeverOverlap(_ f: Int, _ n: Int, _ table: Table) {
        let l = layout(f, n)
        let seats = l.seatFrames
        let cats = l.opponentSlots.map { G.circle($0, l.catDiameter) }
        let piles = [G.box(l.deck, l.pileSize), G.box(l.discard, l.pileSize)]
        let groups = laid(l, n, table).groups
        let menu = l.menuButtonFrame
        #expect(menu.width >= 44)
        G.clear(seats, seats, "seats")
        // Each cat sits inside its own seat.
        for (cat, seat) in zip(cats, seats) { #expect(G.inside(cat, seat), "\(cat) outside \(seat)") }
        G.clear(groups, groups, "groups")
        G.clear(groups, piles + seats + [l.towerFrame, l.banner, menu], "a group")
        G.clear([l.banner], piles + seats + [l.towerFrame, menu], "the banner")
        G.clear(seats, piles + [l.towerFrame, menu], "a seat")
        G.clear(piles, [l.towerFrame, menu], "a pile")
        G.clear([l.towerFrame], [menu], "the tower")
        // The rug under the piles keeps clear of the seats, the groups, the banner and the menu.
        G.clear([l.rug], seats + groups + [l.banner, menu], "the rug")
        for p in piles { #expect(G.inside(p, l.rug)) }
        // A long name's banner, as wide as it may grow, keeps clear of everything.
        G.clear([l.bannerRoom], piles + groups + seats + [l.towerFrame, l.rug, menu], "the banner's room")
        #expect(G.inside(l.banner, l.bannerRoom))
        // The menu's corner is free of every cat.
        G.clear([menu], cats, "the menu")
    }

    @Test(arguments: G.hd, 2...6)
    func bigEnoughToReadFromTheCouch(_ f: Int, _ n: Int) {
        let l = layout(f, n)
        #expect(l.cardSize.width >= 112)
        #expect(l.pileSize == l.cardSize)
        #expect(l.catDiameter >= 132)
        #expect(l.opponentDiameter == l.catDiameter)
        #expect(l.banner.height >= 64)
        #expect(l.tvUnit == 1)
    }

    @Test(arguments: 2...6)
    func at4KEverythingIsTwiceTheSize(_ n: Int) {
        let a = layout(0, n), b = layout(4, n)
        #expect(b.tvUnit == 2 * a.tvUnit)
        #expect(abs(b.cardSize.width - 2 * a.cardSize.width) <= 1 && abs(b.miniCardSize.height - 2 * a.miniCardSize.height) <= 1)
        #expect(abs(b.catDiameter - 2 * a.catDiameter) <= 1 && abs(b.menuSide - 2 * a.menuSide) <= 1)
        let pairs: [(CGRect, CGRect)] = [
            (a.towerFrame, b.towerFrame), (a.rug, b.rug), (a.banner, b.banner), (a.bannerRoom, b.bannerRoom),
            (a.menuButtonFrame, b.menuButtonFrame), (a.laidZone, b.laidZone),
        ] + Array(zip(a.seatFrames, b.seatFrames)) + (0..<n).map { (a.laidRow(slot: $0, of: n), b.laidRow(slot: $0, of: n)) }
        for (x, y) in pairs { #expect(G.doubled(x, y), "\(x) vs \(y)") }
        for (x, y) in zip([a.deck, a.discard] + a.opponentSlots, [b.deck, b.discard] + b.opponentSlots) {
            #expect(G.doubled(x, y), "\(x) vs \(y)")
        }
        let counts = Self.groups(n, .full)
        for s in 0..<n {
            for (x, y) in zip(a.tvGroups(seat: s, counts: counts[s]), b.tvGroups(seat: s, counts: counts[s])) {
                #expect(G.doubled(x.frame, y.frame))
                for (p, q) in zip(x.cards, y.cards) { #expect(G.doubled(p, q)) }
            }
        }
    }

    /// The visible cards of a placed group, left to right.
    static func visible(_ g: TVLaidGroup) -> [CGPoint] { zip(g.cards, g.shown).filter(\.1).map(\.0) }

    /// Every pair of group sizes a seat can have down (a phase's two groups, hits growing each to
    /// twelve), and one group alone.
    static let pairs: [[Int]] = (1...12).flatMap { a in [[a]] + (1...12).map { [a, $0] } }

    /// The table is planned for every seat down with two groups of up to twelve, so laying down and
    /// hitting never move anything: each seat's groups stay in its own place, at the planned size,
    /// and no card covers the corner numeral of the card under it.
    @Test(arguments: G.frames.indices, 2...6)
    func everySeatsGroupsFitAtThePlannedSize(_ f: Int, _ n: Int) {
        let l = layout(f, n)
        // The groups' frames reach at most their 4-point outline past the area.
        let outline = 4 * l.tvUnit + 0.5
        for s in 0..<n {
            let area = l.laidRow(slot: s, of: n)
            for counts in Self.pairs {
                let groups = l.tvGroups(seat: s, counts: counts)
                #expect(groups.map(\.cards.count) == counts)
                G.clear(groups.map(\.frame), groups.map(\.frame), "\(counts) groups")
                for g in groups {
                    #expect(G.inside(g.frame, area.insetBy(dx: -outline, dy: -outline)), "\(counts): \(g.frame) outside \(area)")
                    #expect(abs(g.cardSize.width - l.miniCardSize.width) <= 0.5, "\(counts) shrinks its cards")
                    let shown = Self.visible(g)
                    for (a, b) in zip(shown, shown.dropFirst()) {
                        #expect(b.x - a.x >= g.cardSize.width * 48 / 64 - 0.01, "a card covers its neighbour's numeral")
                    }
                    for p in shown { #expect(G.inside(G.box(p, g.cardSize), g.frame)) }
                }
            }
        }
    }

    /// The plan's rule: nothing that matters is under 28 pt at 1080p. A laid card's corner
    /// numeral is `laidNumeralRatio` of its width (the compact face's two-digit index, 30 pt on
    /// the 64 pt face), measured on every visible card of every seat's groups (two of up to twelve
    /// a seat), inside the TV-safe insets and without them; long groups fold to keep it.
    @Test(arguments: G.hd, 2...6)
    func laidNumeralsAreAtLeast28Points(_ f: Int, _ n: Int) {
        let l = layout(f, n)
        #expect(l.tvLaidNumeral >= 28)
        for s in 0..<n {
            for counts in Self.pairs {
                for g in l.tvGroups(seat: s, counts: counts) where g.shown.contains(true) {
                    #expect(g.cardSize.width * TableLayout.laidNumeralRatio >= 28, "\(n) seats, \(counts)")
                }
            }
        }
    }

    /// A fold is the phone's: the first cards and the last, so a run keeps both ends (the cards a
    /// hit extends), the rest under the last card, and a "+n" badge on the seam before it.
    @Test(arguments: [0, 1, 2], 2...6)
    func aFoldKeepsBothEnds(_ f: Int, _ n: Int) {
        let l = layout(f, n)
        for s in 0..<n {
            for counts in Self.pairs {
                for g in l.tvGroups(seat: s, counts: counts) {
                    let count = g.cards.count
                    let shown = g.shown.filter { $0 }.count
                    #expect(g.folded == count - shown)
                    #expect(g.shown.first == true && g.shown.last == true, "\(counts): an end is folded away")
                    // The first `shown - 1` cards, then the last.
                    #expect(g.shown == (0..<count).map { $0 < shown - 1 || $0 == count - 1 })
                    #expect(count < 2 || shown >= 2)
                    if g.folded > 0 {
                        let last = g.cards[count - 1]
                        for j in 0..<count where !g.shown[j] { #expect(g.cards[j] == last) }
                        #expect(g.frame.contains(g.badge))
                        #expect(abs(g.badge.x - (last.x - g.cardSize.width / 2)) < 0.01)
                        #expect(g.badge.y < last.y)  // low on the cards, under the corner numerals
                    }
                }
            }
        }
    }

    @Test func roomForTwelveFoldsNothing() {
        // Two seats have the room for two unfolded groups of twelve.
        let l = layout(0, 2)
        for s in 0..<2 { #expect(l.tvGroups(seat: s, counts: [12, 12]).allSatisfy { $0.folded == 0 }) }
        // A phase's groups never fold as they are laid down, at any seat count, but for a run of
        // nine at a six-seat table's top seats (376 points of room; nine need 420): it hides one.
        for n in 2...6 {
            let m = layout(0, n)
            for s in 0..<n {
                for phase in [[3, 3], [3, 4], [4, 4], [7], [8], [9], [5, 2], [5, 3]] {
                    let most = n == 6 && phase == [9] ? 1 : 0
                    #expect(m.tvGroups(seat: s, counts: phase).allSatisfy { $0.folded <= most }, "\(n) seats: \(phase) folds")
                }
            }
        }
    }

    @Test func sixSeatsFoldTwoGroupsOfTwelve() {
        let l = layout(0, 6)
        let folded = (0..<6).flatMap { l.tvGroups(seat: $0, counts: [12, 12]) }.filter { $0.folded > 0 }
        #expect(!folded.isEmpty)
    }

    @Test(arguments: 2...6)
    func aSeatIsAsWideAsItsRoomAllowsUpTo560(_ n: Int) {
        let l = layout(1, n)
        for r in l.seatFrames {
            #expect(r.width >= 372 && r.width <= 560)
        }
        // Three seats across have the room for 560 each.
        if n == 3 || n == 4 { for r in l.seatFrames where r.maxY > 900 { #expect(r.width == 560) } }
    }

    @Test func aSeatWithNothingDownHasNoGroups() {
        let l = layout(0, 4)
        #expect(l.tvGroups(seat: 1, counts: []).isEmpty)
        #expect(l.tvGroups(seat: 9, counts: [3]).isEmpty)
        #expect(l.laidRow(slot: 2, of: 4) != .zero)
    }

    /// A scene not sized yet lays out without crashing, and with nothing not a number.
    @Test func aFrameNotSizedYet() {
        let l = TableLayout(tv: .zero, insets: .tvSafe, seats: 6)
        let t = TilesLayout(tv: .zero, insets: .tvSafe, seats: 4)
        #expect(l.tvUnit.isFinite && t.tvUnit.isFinite)
        #expect(!l.deck.x.isNaN && !l.banner.minX.isNaN && !t.rug.minX.isNaN)
        _ = l.tvGroups(seat: 0, counts: [12, 12])
    }

    @Test func theLaidZoneHoldsEverySeatsGroups() {
        let l = layout(0, 6)
        for s in 0..<6 { #expect(l.laidZone.contains(l.laidRow(slot: s, of: 6))) }
    }
}
