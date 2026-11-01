import CoreGraphics
import Testing
@testable import PounceKit

private let sizes: [(CGSize, CGFloat, CGFloat)] = [
    (CGSize(width: 390, height: 844), 59, 34),
    (CGSize(width: 430, height: 932), 62, 34),
    (CGSize(width: 375, height: 667), 20, 0),
]

private func scene(_ size: CGSize) -> CGRect { CGRect(origin: .zero, size: size) }

private func cardRect(_ p: CGPoint, _ s: CGSize) -> CGRect {
    CGRect(x: p.x - s.width / 2, y: p.y - s.height / 2, width: s.width, height: s.height)
}

private func forEachLayout(_ body: (TableLayout, CGRect, Int) -> Void) {
    for (size, top, bottom) in sizes {
        for opp in 1...5 {
            body(TableLayout(size: size, safeTop: top, safeBottom: bottom, opponents: opp), scene(size), opp)
        }
    }
}

@Suite("TableLayout")
struct TableLayoutTests {
    @Test func cardSizeScalesAndClamps() {
        let a = TableLayout(size: CGSize(width: 390, height: 844), safeTop: 59, safeBottom: 34, opponents: 2)
        #expect(a.cardSize == CGSize(width: 64, height: 90))
        let b = TableLayout(size: CGSize(width: 430, height: 932), safeTop: 59, safeBottom: 34, opponents: 2)
        #expect(b.cardSize.width > 64 && b.cardSize.width <= 76)
        let tiny = TableLayout(size: CGSize(width: 300, height: 600), safeTop: 20, safeBottom: 0, opponents: 2)
        #expect(tiny.cardSize.width == 56)
        let huge = TableLayout(size: CGSize(width: 600, height: 900), safeTop: 20, safeBottom: 0, opponents: 2)
        #expect(huge.cardSize.width == 76)
        #expect(a.miniCardSize.width < a.cardSize.width)
    }

    @Test func everyPointInsideTheScene() {
        forEachLayout { l, s, opp in
            #expect(l.opponentSlots.count == opp)
            for p in l.opponentSlots { #expect(s.contains(p)) }
            #expect(s.contains(cardRect(l.deck, l.cardSize)))
            #expect(s.contains(cardRect(l.discard, l.cardSize)))
            #expect(s.contains(l.towerFrame))
            #expect(s.contains(l.traysFrame))
            for i in 0..<10 { #expect(s.contains(l.shelf(i))) }
            for tray in l.trayFrames(count: 3) { #expect(s.contains(tray)) }
            let total = opp + 1
            for slot in 0..<total { #expect(s.contains(l.laidRow(slot: slot, of: total))) }
            for n in 1...14 {
                for c in l.hand(count: n, lifted: nil) { #expect(s.contains(c.position)) }
            }
        }
    }

    @Test func opponentSlotsEvenlySpacedLeftToRight() {
        forEachLayout { l, _, _ in
            let xs = l.opponentSlots.map(\.x)
            #expect(xs == xs.sorted())
            let gaps = zip(xs.dropFirst(), xs).map { $0 - $1 }
            for g in gaps { #expect(abs(g - gaps[0]) < 0.001) }
            let ys = Set(l.opponentSlots.map(\.y))
            #expect(ys.count == 1)
        }
    }

    @Test func handStaysWithinWidthSymmetricAndFanned() {
        forEachLayout { l, s, _ in
            for n in 1...14 {
                let hand = l.hand(count: n, lifted: nil)
                #expect(hand.count == n)
                for c in hand {
                    #expect(abs(c.rotation) <= 0.35)
                    let r = rotatedBounds(c, l.cardSize)
                    #expect(r.minX >= 0 && r.maxX <= s.width)
                }
                for (a, b) in zip(hand, hand.dropFirst()) { #expect(a.z < b.z) }
                for i in 0..<n {
                    let a = hand[i], b = hand[n - 1 - i]
                    #expect(abs((a.position.x - s.midX) + (b.position.x - s.midX)) < 0.001)
                    #expect(abs(a.position.y - b.position.y) < 0.001)
                    #expect(abs(a.rotation + b.rotation) < 0.001)
                }
                #expect(hand.map(\.position.x) == hand.map(\.position.x).sorted())
            }
            #expect(l.hand(count: 0, lifted: nil).isEmpty)
        }
    }

    @Test func handClearsSafeBottomAndTrays() {
        forEachLayout { l, _, _ in
            for n in 1...14 {
                for c in l.hand(count: n, lifted: nil) {
                    let corners = rotatedBounds(c, l.cardSize)
                    #expect(corners.minY >= l.safeBottom - 0.01)
                    #expect(corners.maxY <= l.traysFrame.minY + 0.01)
                }
            }
        }
    }

    @Test func liftedCardRises() {
        forEachLayout { l, _, _ in
            for n in 1...14 {
                let base = l.hand(count: n, lifted: nil)
                for i in 0..<n {
                    let up = l.hand(count: n, lifted: i)
                    #expect(up[i].position.y - base[i].position.y >= 24)
                    for j in 0..<n where j != i { #expect(up[j] == base[j]) }
                    for (a, b) in zip(up, up.dropFirst()) { #expect(a.z < b.z) }
                }
                // Out-of-range lift is ignored.
                #expect(l.hand(count: n, lifted: n) == base)
                #expect(l.hand(count: n, lifted: -1) == base)
            }
        }
    }

    @Test func trayFramesDoNotOverlap() {
        forEachLayout { l, _, _ in
            #expect(l.trayFrames(count: 0).isEmpty)
            for count in 1...4 {
                let frames = l.trayFrames(count: count)
                #expect(frames.count == count)
                for f in frames { #expect(l.traysFrame.contains(f)); #expect(f.height > 0) }
                for i in 0..<count { for j in (i + 1)..<count where j < count {
                    #expect(!frames[i].intersects(frames[j]))
                    #expect(frames[i].minX < frames[j].minX)
                } }
            }
            #expect(l.traysFrame.height == 64)
        }
    }

    @Test func towerShelvesRiseAndTowerHugsLeftEdge() {
        forEachLayout { l, _, _ in
            let ys = (0..<10).map { l.shelf($0).y }
            for (a, b) in zip(ys, ys.dropFirst()) { #expect(a < b) }
            #expect(l.towerFrame.minX == 0)
            #expect(l.towerFrame.width == 44)
            for i in 0..<10 { #expect(l.towerFrame.contains(l.shelf(i))) }
            #expect(l.towerFrame.maxY <= l.opponentsBar.minY)
            #expect(l.towerFrame.minY >= l.traysFrame.maxY)
        }
    }

    @Test func regionsDoNotOverlap() {
        forEachLayout { l, _, opp in
            let deck = cardRect(l.deck, l.cardSize), discard = cardRect(l.discard, l.cardSize)
            #expect(!deck.intersects(discard))
            #expect(l.deck.x < l.discard.x)
            let total = opp + 1
            let rows = (0..<total).map { l.laidRow(slot: $0, of: total) }
            var regions: [(String, CGRect)] = [
                ("deck", deck), ("discard", discard), ("tower", l.towerFrame),
                ("trays", l.traysFrame), ("bar", l.opponentsBar),
            ]
            for (i, r) in rows.enumerated() { regions.append(("row\(i)", r)); #expect(l.laidZone.contains(r)) }
            #expect(l.laidZone.contains(deck) && l.laidZone.contains(discard))
            for i in 0..<regions.count { for j in (i + 1)..<regions.count {
                #expect(!regions[i].1.intersects(regions[j].1), "\(regions[i].0) overlaps \(regions[j].0)")
            } }
            for slot in l.opponentSlots {
                #expect(l.opponentsBar.contains(slot))
                #expect(!l.towerFrame.contains(slot))
            }
        }
    }
}

private func rotatedBounds(_ c: CardPlacement, _ s: CGSize) -> CGRect {
    let hw = s.width / 2, hh = s.height / 2
    let cs = cos(c.rotation), sn = sin(c.rotation)
    let xs = [-hw, hw].flatMap { x in [-hh, hh].map { y in c.position.x + x * cs - y * sn } }
    let ys = [-hw, hw].flatMap { x in [-hh, hh].map { y in c.position.y + x * sn + y * cs } }
    return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
}
