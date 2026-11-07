import CoreGraphics
import Testing
@testable import PounceKit

/// iPad windows: full screen in both orientations, Split View halves and a Stage Manager window.
private let roomy: [(CGSize, CGFloat, CGFloat)] = [
    (CGSize(width: 1024, height: 1366), 24, 20),  // iPad Pro 13", portrait
    (CGSize(width: 1366, height: 1024), 24, 20),  // landscape
    (CGSize(width: 744, height: 1133), 24, 20),  // iPad mini, portrait
    (CGSize(width: 1133, height: 744), 24, 20),  // landscape
    (CGSize(width: 834, height: 1194), 24, 20),  // iPad Pro 11"
    (CGSize(width: 1194, height: 834), 24, 20),
    (CGSize(width: 678, height: 1024), 24, 20),  // half a 13" in landscape (Split View)
    (CGSize(width: 900, height: 700), 0, 0),  // a Stage Manager window
]

private func cardRect(_ p: CGPoint, _ s: CGSize) -> CGRect {
    CGRect(x: p.x - s.width / 2, y: p.y - s.height / 2, width: s.width, height: s.height)
}

private func rotatedBounds(_ c: CardPlacement, _ s: CGSize) -> CGRect {
    let hw = s.width / 2, hh = s.height / 2
    let cs = cos(c.rotation), sn = sin(c.rotation)
    let xs = [-hw, hw].flatMap { x in [-hh, hh].map { y in c.position.x + x * cs - y * sn } }
    let ys = [-hw, hw].flatMap { x in [-hh, hh].map { y in c.position.y + x * sn + y * cs } }
    return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
}

private func forEachRoomy(_ body: (TableLayout, CGRect, Int) -> Void) {
    for (size, top, bottom) in roomy {
        for opp in 1...5 {
            body(TableLayout(size: size, safeTop: top, safeBottom: bottom, opponents: opp), CGRect(origin: .zero, size: size), opp)
        }
    }
}

@Suite("TableLayout, roomy")
struct TableLayoutRoomyTests {
    @Test func arrangementFollowsTheSpace() {
        #expect(TableLayout.arrangement(for: CGSize(width: 390, height: 844)) == .phone)
        #expect(TableLayout.arrangement(for: CGSize(width: 440, height: 956)) == .phone)
        #expect(TableLayout.arrangement(for: CGSize(width: 600, height: 900)) == .phone)
        // A narrow Split View column is a phone-shaped table.
        #expect(TableLayout.arrangement(for: CGSize(width: 507, height: 1366)) == .phone)
        #expect(TableLayout.arrangement(for: CGSize(width: 1024, height: 1366)) == .tall)
        #expect(TableLayout.arrangement(for: CGSize(width: 678, height: 1024)) == .tall)
        #expect(TableLayout.arrangement(for: CGSize(width: 1366, height: 1024)) == .wide)
        #expect(TableLayout.arrangement(for: CGSize(width: 1133, height: 744)) == .wide)
    }

    @Test func cardsAreBiggerAndCapped() {
        forEachRoomy { l, _, _ in
            #expect(l.cardSize.width >= 72 && l.cardSize.width <= 104)
            #expect(l.miniCardSize.width >= 47)
            #expect(l.catDiameter > 62)
        }
        let pro = TableLayout(size: CGSize(width: 1366, height: 1024), safeTop: 24, safeBottom: 20, opponents: 1)
        #expect(pro.cardSize.width == 102)
    }

    @Test func everythingInsideTheScene() {
        forEachRoomy { l, s, opp in
            #expect(l.opponentSlots.count == opp)
            for p in l.opponentSlots { #expect(l.opponentsBar.contains(p)) }
            #expect(s.contains(cardRect(l.deck, l.cardSize)) && s.contains(cardRect(l.discard, l.cardSize)))
            #expect(s.contains(l.towerFrame) && s.contains(l.traysFrame) && s.contains(l.towerTab))
            #expect(s.contains(l.sortButtonFrame) && s.contains(l.seatTagFrame))
            for n in 1...14 {
                for c in l.hand(count: n, lifted: nil) {
                    let r = rotatedBounds(c, l.cardSize)
                    #expect(r.minX >= 0 && r.maxX <= s.width)
                    #expect(r.minY >= l.safeBottom - 0.01)
                    #expect(r.maxY <= l.traysFrame.minY + 0.01)
                }
            }
        }
    }

    @Test func regionsDoNotOverlap() {
        forEachRoomy { l, _, opp in
            let deck = cardRect(l.deck, l.cardSize), discard = cardRect(l.discard, l.cardSize)
            for total in [opp + 1, 6] {
                let rows = (0..<total).map { l.laidRow(slot: $0, of: total) }
                var regions: [(String, CGRect)] = [
                    ("deck", deck), ("discard", discard), ("towerTab", l.towerTab), ("trays", l.traysFrame),
                    ("bar", l.opponentsBar), ("sort", l.sortButtonFrame), ("seatTag", l.seatTagFrame),
                ]
                for (i, r) in rows.enumerated() {
                    regions.append(("row\(i)", r))
                    #expect(l.laidZone.contains(r), "row \(i) of \(total) outside the zone at \(l.size)")
                    #expect(r.width >= 240)
                }
                for i in 0..<regions.count { for j in (i + 1)..<regions.count {
                    #expect(!regions[i].1.intersects(regions[j].1), "\(regions[i].0) overlaps \(regions[j].0) at \(l.size), \(total) seats")
                } }
            }
            #expect(l.seatTagFrame.minX > l.towerTab.maxX)
            #expect(abs(l.laidZone.midX - l.size.width / 2) < 0.001)
            #expect(abs((l.deck.x + l.discard.x) / 2 - l.size.width / 2) < 0.001)
            for n in 1...14 {
                for c in l.hand(count: n, lifted: n / 2) { #expect(!rotatedBounds(c, l.cardSize).intersects(l.towerTab)) }
            }
        }
    }

    @Test func fanAndTraysStayAComfortableWidth() {
        forEachRoomy { l, s, _ in
            let twelve = l.hand(count: 12, lifted: nil)
            let span = twelve.last!.position.x - twelve.first!.position.x
            #expect(span <= l.cardSize.width * 0.72 * 11 + 0.01)
            #expect(l.traysFrame.width <= 820)
            #expect(abs(l.traysFrame.midX - s.midX) < 0.01)
        }
    }

    @Test func seatsCurveAlongTheFarSide() {
        let l = TableLayout(size: CGSize(width: 1366, height: 1024), safeTop: 24, safeBottom: 20, opponents: 5)
        let xs = l.opponentSlots.map(\.x)
        #expect(xs == xs.sorted())
        #expect(l.opponentSlots[2].y > l.opponentSlots[0].y)
        #expect(abs(l.opponentSlots[0].y - l.opponentSlots[4].y) < 0.001)
        #expect(xs.first! > l.towerFrame.maxX)
    }

    @Test func wideTablesSeatLaidRowsBesideThePiles() {
        for size in [CGSize(width: 1366, height: 1024), CGSize(width: 1133, height: 744)] {
            let l = TableLayout(size: size, safeTop: 24, safeBottom: 20, opponents: 5)
            #expect(l.arrangement == .wide)
            let deck = cardRect(l.deck, l.cardSize), discard = cardRect(l.discard, l.cardSize)
            for slot in 0..<6 {
                let r = l.laidRow(slot: slot, of: 6)
                #expect(slot % 2 == 0 ? r.maxX < deck.minX : r.minX > discard.maxX)
            }
            // The tower runs the whole left edge.
            #expect(l.towerFrame.minY < l.traysFrame.minY)
        }
    }
}
