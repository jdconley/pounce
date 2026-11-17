import CoreGraphics
import Testing
@testable import PounceKit

/// Tuna Tiles on a TV across the room: the seats across the top, the board filling the room
/// under them, and along the bottom the toy box, the turn banner and the menu. No stash, no
/// controls. The web's TV table (`apps/play-web/src/table/tiles-layout.ts`) is the reference.
@Suite("TilesLayout, TV")
struct TilesLayoutTVTests {
    typealias G = TVGeometry

    /// The worst board: thirty sets of three.
    static let worst = Array(repeating: 3, count: 30)

    private func layout(_ f: Int, _ n: Int) -> TilesLayout {
        let frame = G.frames[f]
        return TilesLayout(tv: frame.size, insets: frame.insets, seats: n)
    }

    private func flow(_ l: TilesLayout, _ sets: [Int] = worst) -> RugFlow {
        RugFlow.fit(lengths: sets, width: l.rug.width, height: l.rug.height, maxPiece: l.rugPieceMax, minPiece: l.rugPieceMin)
    }

    /// A set's box on the screen (the flow's content space runs down from the rug's top).
    private func onScreen(_ r: CGRect, _ l: TilesLayout) -> CGRect {
        CGRect(x: l.rug.minX + r.minX, y: l.rug.maxY - r.maxY, width: r.width, height: r.height)
    }

    @Test(arguments: G.frames.indices, 2...4)
    func nothingPrivateAndEverySeatAcrossTheTop(_ f: Int, _ n: Int) {
        let l = layout(f, n)
        #expect(l.arrangement == .tv)
        #expect(l.controller == nil)
        #expect(l.rack == .zero)
        #expect(l.rackSlots(count: 14).centers.isEmpty)
        #expect(l.rackScrollLimit(count: 14) == 0)
        for r in [l.strip, l.undo, l.reset, l.turn, l.sortNumber, l.sortToy, l.tidy, l.meter, l.recap, l.switchBand, l.statusLine] {
            #expect(r == .zero)
        }
        #expect(l.seatFrames.count == n)
        #expect(l.opponentSlots.count == n)
    }

    @Test(arguments: G.frames.indices, 2...4)
    func everythingIsInsideTheSafeFrame(_ f: Int, _ n: Int) {
        let l = layout(f, n)
        let safe = G.safe(G.frames[f].size, G.frames[f].insets)
        let laid = flow(l)
        #expect(!laid.scrolls)
        var rects = [l.rugArt, l.rug, l.pool, l.banner, l.bannerRoom, l.menuButtonFrame]
        rects += l.seatFrames + l.opponentSlots.map { G.circle($0, l.catDiameter) }
        for r in rects { #expect(G.inside(r, safe), "\(r) outside \(safe)") }
        // Every set, and every piece of it, lies on the rug.
        for set in laid.sets {
            #expect(G.inside(onScreen(set.frame, l), l.rug))
            for p in set.pieces {
                let piece = G.box(CGPoint(x: l.rug.minX + p.x, y: l.rug.maxY - p.y), laid.pieceSize)
                #expect(G.inside(piece, l.rug))
            }
        }
        #expect(G.inside(l.rug, l.rugArt))
    }

    @Test(arguments: G.frames.indices, 2...4)
    func seatsSetsTheToyBoxBannerAndMenuNeverOverlap(_ f: Int, _ n: Int) {
        let l = layout(f, n)
        let seats = l.seatFrames
        let cats = l.opponentSlots.map { G.circle($0, l.catDiameter) }
        let sets = flow(l).sets.map { onScreen($0.frame, l) }
        let menu = l.menuButtonFrame
        G.clear(seats, seats, "seats")
        for (cat, seat) in zip(cats, seats) { #expect(G.inside(cat, seat), "\(cat) outside \(seat)") }
        G.clear(sets, sets, "sets")
        G.clear(sets, seats + [l.pool, l.banner, menu], "a set")
        G.clear([l.banner], seats + [l.pool, menu, l.rugArt], "the banner")
        G.clear(seats, [l.rugArt, l.pool, menu], "a seat")
        G.clear([l.pool], [l.rugArt, menu], "the toy box")
        G.clear([l.bannerRoom], seats + sets + [l.pool, l.rugArt, menu], "the banner's room")
        #expect(G.inside(l.banner, l.bannerRoom))
        G.clear([menu], cats + [l.rugArt], "the menu")
    }

    @Test(arguments: G.hd, 2...4)
    func bigEnoughToReadFromTheCouch(_ f: Int, _ n: Int) {
        let l = layout(f, n)
        #expect(flow(l).pieceSize.width >= 52)
        #expect(l.catDiameter >= 132)
        #expect(l.banner.height >= 64)
        #expect(l.tvUnit == 1)
    }

    @Test(arguments: 2...4)
    func at4KEverythingIsTwiceTheSize(_ n: Int) {
        let a = layout(0, n), b = layout(4, n)
        #expect(b.tvUnit == 2 * a.tvUnit)
        #expect(abs(b.catDiameter - 2 * a.catDiameter) <= 1 && abs(b.menuSide - 2 * a.menuSide) <= 1)
        #expect(abs(b.rugPieceMax - 2 * a.rugPieceMax) <= 1 && abs(b.rugPieceMin - 2 * a.rugPieceMin) <= 1)
        let pairs: [(CGRect, CGRect)] = [
            (a.rugArt, b.rugArt), (a.rug, b.rug), (a.pool, b.pool), (a.banner, b.banner), (a.bannerRoom, b.bannerRoom),
            (a.menuButtonFrame, b.menuButtonFrame), (a.opponentsBar, b.opponentsBar),
        ] + Array(zip(a.seatFrames, b.seatFrames))
        for (x, y) in pairs { #expect(G.doubled(x, y), "\(x) vs \(y)") }
        for (x, y) in zip(a.opponentSlots, b.opponentSlots) { #expect(G.doubled(x, y)) }
        // The worst board's pieces at least double: the flow's gaps are fixed points, so a 4K
        // frame (never an Apple TV's, whose screen is 1920 x 1080 points) fits a set more a row.
        let p = flow(a).pieceSize.width, q = flow(b).pieceSize.width
        #expect(q >= 2 * p, "\(p) at 1080, \(q) at 4K")
    }

    @Test(arguments: 2...4)
    func aSeatIsAsWideAsItsRoomAllowsUpTo560(_ n: Int) {
        for r in layout(1, n).seatFrames {
            #expect(r.width >= 372 && r.width <= 560)
            if n <= 3 { #expect(r.width == 560) }
        }
    }

    /// Both games put the menu in the same corner, so it never moves between them.
    @Test(arguments: G.frames.indices)
    func bothGamesPutTheMenuInTheSameCorner(_ f: Int) {
        let frame = G.frames[f]
        let ct = TableLayout(tv: frame.size, insets: frame.insets, seats: 4)
        let tt = TilesLayout(tv: frame.size, insets: frame.insets, seats: 4)
        #expect(ct.menuButtonFrame == tt.menuButtonFrame)
        #expect(ct.menuButton == tt.menuButton && ct.menuSide == tt.menuSide)
        // Bottom right.
        let safe = G.safe(frame.size, frame.insets)
        #expect(ct.menuButtonFrame.midX > safe.midX && ct.menuButtonFrame.midY < safe.midY)
        // And the banner on the same line.
        #expect(ct.banner.minY == tt.banner.minY && ct.banner.height == tt.banner.height)
    }

    @Test func aNearEmptyBoardDrawsItsPiecesBigger() {
        let l = layout(0, 4)
        #expect(flow(l, [3, 4]).pieceSize.width > flow(l).pieceSize.width)
    }
}
