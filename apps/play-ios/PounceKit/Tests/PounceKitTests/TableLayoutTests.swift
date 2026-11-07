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
        // Laid cards never shrink below 41 pt wide (two-digit numerals keep an 11 pt cap).
        forEachLayout { l, _, _ in #expect(l.miniCardSize.width >= 41) }
        // A scene before its first size.
        #expect(TableLayout(size: .zero, safeTop: 0, safeBottom: 0, opponents: 1).laidRow(slot: 0, of: 2).height > 0)
    }

    @Test func smallTablesGetFullWidthLaidRows() {
        forEachLayout { l, _, _ in
            for total in 1...3 {
                for slot in 0..<total {
                    #expect(l.laidRow(slot: slot, of: total).width == l.laidZone.width)
                }
            }
            // Six seats never fit a row each: two columns, none cut short by the sort button.
            for slot in 0..<6 { #expect(l.laidRow(slot: slot, of: 6).width == (l.laidZone.width - 8) / 2) }
        }
    }

    @Test func everyPointInsideTheScene() {
        forEachLayout { l, s, opp in
            #expect(l.opponentSlots.count == opp)
            for p in l.opponentSlots { #expect(s.contains(p)) }
            #expect(s.contains(cardRect(l.deck, l.cardSize)))
            #expect(s.contains(cardRect(l.discard, l.cardSize)))
            #expect(s.contains(l.towerFrame))
            #expect(s.contains(l.towerTab))
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

    /// The tower folds down to a tab at the bottom of its edge, on the sort button's line,
    /// and opens up from there over the table.
    @Test func towerTabSitsAtTheFootOfTheTower() {
        forEachLayout { l, _, _ in
            #expect(l.towerTab.width >= 44 && l.towerTab.height >= 44)
            #expect(l.towerTab.minX >= 0 && l.towerTab.maxX < l.towerFrame.maxX + 8)
            #expect(abs(l.towerTab.midY - l.sortButton.y) < 0.001)
            #expect(l.towerTab.minY >= l.traysFrame.maxY)
            #expect(l.towerTab.minY < l.towerFrame.minY + 8)
            for n in 1...14 {
                for c in l.hand(count: n, lifted: n / 2) { #expect(!rotatedBounds(c, l.cardSize).intersects(l.towerTab)) }
            }
        }
    }

    /// Centered as if the tower weren't there: the laid zone, the piles and the rug's middle.
    @Test func tableIsCentered() {
        forEachLayout { l, s, _ in
            #expect(abs(l.laidZone.midX - s.midX) < 0.001)
            #expect(abs((l.deck.x + l.discard.x) / 2 - s.midX) < 0.001)
            #expect(abs(l.traysFrame.midX - s.midX) < 0.001)
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
                ("deck", deck), ("discard", discard), ("towerTab", l.towerTab),
                ("trays", l.traysFrame), ("bar", l.opponentsBar), ("sort", l.sortButtonFrame),
                ("seatTag", l.seatTagFrame),
            ]
            for (i, r) in rows.enumerated() { regions.append(("row\(i)", r)); #expect(l.laidZone.contains(r)) }
            #expect(l.laidZone.contains(deck) && l.laidZone.contains(discard))
            for i in 0..<regions.count { for j in (i + 1)..<regions.count {
                #expect(!regions[i].1.intersects(regions[j].1), "\(regions[i].0) overlaps \(regions[j].0)")
            } }
            #expect(l.seatTagFrame.maxX < l.sortButtonFrame.minX)
            #expect(l.seatTagFrame.minX > l.towerTab.maxX)
            for slot in l.opponentSlots {
                #expect(l.opponentsBar.contains(slot))
                #expect(!l.towerFrame.contains(slot))
            }
            // Five rows (two columns) and six reach down to the tab's line on the smallest
            // phones: they stop short of it.
            for total in [5, 6] {
                for slot in 0..<total { #expect(!l.laidRow(slot: slot, of: total).intersects(l.towerTab)) }
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

extension TableLayoutTests {
    @Test func gapLeavesTheDroppedCardsSlotEmpty() {
        forEachLayout { l, _, _ in
            for n in 1...11 {
                let full = l.hand(count: n + 1, lifted: nil)
                for gap in 0...n {
                    let open = l.hand(count: n, gap: gap)
                    #expect(open.count == n)
                    // The others sit exactly where they will once the card lands in the gap.
                    var landed = open
                    landed.insert(full[gap], at: gap)
                    #expect(landed == full)
                }
            }
        }
    }

    @Test func handSlotIsTheNearestSlot() {
        forEachLayout { l, _, _ in
            for n in 1...11 {
                let xs = l.hand(count: n, lifted: nil).map(\.position.x)
                for (i, x) in xs.enumerated() {
                    #expect(l.handSlot(x: x, count: n, current: nil) == i)
                    #expect(l.handSlot(x: x + 3, count: n, current: nil) == i)
                }
                // Past either end: the end slots.
                #expect(l.handSlot(x: -500, count: n, current: nil) == 0)
                #expect(l.handSlot(x: 5000, count: n, current: nil) == n - 1)
            }
        }
    }

    @Test func handSlotHoldsAcrossABoundaryUntilPastTheHysteresis() {
        let l = TableLayout(size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0, opponents: 3)
        let n = 11  // a full hand on the smallest phone
        let xs = l.hand(count: n, lifted: nil).map(\.position.x)
        let step = xs[1] - xs[0]
        let boundary = (xs[4] + xs[5]) / 2
        let margin = step * TableLayout.slotHysteresis
        // Just past halfway: still slot 4 while it is shown, slot 5 from scratch.
        #expect(l.handSlot(x: boundary + 1, count: n, current: 4) == 4)
        #expect(l.handSlot(x: boundary + 1, count: n, current: nil) == 5)
        #expect(l.handSlot(x: boundary + margin - 0.5, count: n, current: 4) == 4)
        #expect(l.handSlot(x: boundary + margin + 0.5, count: n, current: 4) == 5)
        // And back the other way from 5.
        #expect(l.handSlot(x: boundary - margin + 0.5, count: n, current: 5) == 5)
        #expect(l.handSlot(x: boundary - margin - 0.5, count: n, current: 5) == 4)
        // A fast swipe jumps straight to the far slot.
        #expect(l.handSlot(x: xs[9], count: n, current: 4) == 9)
        // A stale slot from a bigger fan doesn't stick.
        #expect(l.handSlot(x: xs[2], count: n, current: 40) == 2)
        #expect(l.handSlot(x: 0, count: 1, current: nil) == 0)
    }
}
