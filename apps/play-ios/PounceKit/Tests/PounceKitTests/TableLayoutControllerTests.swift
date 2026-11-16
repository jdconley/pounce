import CoreGraphics
import Testing
@testable import PounceKit

/// A phone that is a controller for a TV table: only its own cards, the piles and room for the
/// SwiftUI chrome (the "Cards" | "Table" switch, the status line, the action row).
@Suite("TableLayout, controller")
struct TableLayoutControllerTests {
    /// iPhone SE, iPhone 17 Pro, iPhone 17 Pro Max, iPad portrait, iPad landscape.
    static let screens: [(size: CGSize, top: CGFloat, bottom: CGFloat)] = [
        (CGSize(width: 375, height: 667), 20, 0), (CGSize(width: 402, height: 874), 62, 34),
        (CGSize(width: 440, height: 956), 62, 34), (CGSize(width: 820, height: 1180), 24, 20),
        (CGSize(width: 1180, height: 820), 24, 20),
    ]
    /// The chrome at the largest accessibility text size.
    static let tall = ControllerChrome(switchBand: 64, status: 56, actions: 96)

    private func layout(_ i: Int, _ chrome: ControllerChrome = .standard) -> TableLayout {
        let s = Self.screens[i]
        return TableLayout(size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: 3, controller: chrome)
    }

    @Test(arguments: screens.indices)
    func everySizeIsAController(_ i: Int) {
        let l = layout(i)
        #expect(l.arrangement == .controller)
        // A layout without the parameter is the table it always was.
        let s = Self.screens[i]
        let table = TableLayout(size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: 3)
        #expect(table.arrangement == TableLayout.arrangement(for: s.size))
        #expect(table.switchBand == .zero && table.statusLine == .zero && table.actionRow == .zero)
        #expect(l.roomy == table.roomy)
    }

    @Test(arguments: screens.indices)
    func theTableAroundTheHandIsGone(_ i: Int) {
        let l = layout(i)
        #expect(l.opponentsBar == .zero)
        #expect(l.opponentSlots.isEmpty)
        #expect(l.towerFrame == .zero)
        #expect(l.towerTab == .zero)
        #expect(l.laidZone == .zero)
        for slot in 0..<4 { #expect(l.laidRow(slot: slot, of: 4) == .zero) }
    }

    @Test(arguments: screens.indices)
    func everythingIsInsideTheSafeArea(_ i: Int) {
        for chrome in [ControllerChrome.standard, Self.tall] {
            let l = layout(i, chrome)
            let safe = safeArea(l)
            for (name, frame) in frames(l) {
                #expect(safe.insetBy(dx: -0.01, dy: -0.01).contains(frame), "\(l.size) \(name) \(frame) is outside \(safe)")
            }
            #expect(l.switchBand.contains(l.menuButtonFrame), "\(l.size): the paw is not in the switch band")
            for n in 1...11 {
                for (k, c) in l.hand(count: n, lifted: nil).enumerated() {
                    let r = rotatedBounds(c, l.cardSize)
                    #expect(safe.insetBy(dx: -0.01, dy: -0.01).contains(r), "\(l.size) card \(k) of \(n): \(r)")
                }
            }
        }
    }

    @Test(arguments: screens.indices)
    func nothingOverlaps(_ i: Int) {
        for chrome in [ControllerChrome.standard, Self.tall] {
            let l = layout(i, chrome)
            let all = frames(l)
            for (a, (nameA, frameA)) in all.enumerated() {
                for (nameB, frameB) in all[(a + 1)...] {
                    // The paw sits at the switch band's right end.
                    if Set([nameA, nameB]) == ["switch", "menu"] { continue }
                    #expect(!overlaps(frameA, frameB), "\(l.size): \(nameA) \(frameA) overlaps \(nameB) \(frameB)")
                }
            }
            for n in 1...11 {
                for c in l.hand(count: n, lifted: nil) {
                    let r = rotatedBounds(c, l.cardSize)
                    for (name, frame) in all {
                        #expect(!overlaps(r, frame), "\(l.size): a card of \(n) overlaps \(name)")
                    }
                }
            }
            // The trays don't overlap each other either.
            let trays = l.trayFrames(count: 3)
            for (a, b) in zip(trays, trays.dropFirst()) { #expect(!overlaps(a, b)) }
        }
    }

    @Test(arguments: screens.indices)
    func topToBottom(_ i: Int) {
        let l = layout(i)
        let pileTop = l.deck.y + l.cardSize.height / 2
        let pileBottom = l.deck.y - l.cardSize.height / 2
        #expect(l.switchBand.maxY <= l.size.height - l.safeTop + 0.01)
        #expect(l.statusLine.maxY <= l.switchBand.minY + 0.01)
        #expect(pileTop <= l.statusLine.minY)
        #expect(l.actionRow.maxY <= pileBottom)
        #expect(l.traysFrame.maxY <= l.actionRow.minY)
        #expect(l.deck.y == l.discard.y && l.deck.x < l.size.width / 2 && l.discard.x > l.size.width / 2)
        #expect(abs((l.deck.x + l.discard.x) / 2 - l.size.width / 2) < 0.01)
        // The switch band and the status line hug the top; the action row sits on the trays.
        #expect(abs(l.switchBand.maxY - (l.size.height - l.safeTop)) < 0.01)
        #expect(l.actionRow.minY - l.traysFrame.maxY <= TableLayout.sortButtonHit + 16)
    }

    @Test(arguments: screens.indices)
    func theMinimumsHold(_ i: Int) {
        for chrome in [ControllerChrome.standard, Self.tall] {
            let l = layout(i, chrome)
            #expect(l.cardSize.width >= 64, "\(l.size): cards \(l.cardSize.width) wide")
            #expect(l.menuButtonFrame.width >= 44 && l.menuButtonFrame.height >= 44)
            #expect(l.sortButtonFrame.width >= 44 && l.sortButtonFrame.height >= 44)
            #expect(l.switchBand.height >= max(chrome.switchBand, 44))
            #expect(l.statusLine.height >= chrome.status)
            #expect(l.actionRow.height >= chrome.actions)
            #expect(l.actionRow.width >= l.size.width - 48)
            for tray in l.trayFrames(count: 3) { #expect(tray.width >= 44 && tray.height >= 44) }
        }
    }

    @Test(arguments: screens.indices)
    func theCardsAreBiggerThanOnTheTable(_ i: Int) {
        let s = Self.screens[i]
        let table = TableLayout(size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: 3)
        let l = layout(i)
        #expect(l.cardSize.width > table.cardSize.width, "\(s.size): \(l.cardSize.width) vs \(table.cardSize.width)")
        // Eleven cards still fan: each shows a strip of its face.
        let hand = l.hand(count: 11, lifted: nil)
        #expect(hand[1].position.x - hand[0].position.x >= 24)
    }

    @Test func anSEAtTheLargestTextSizeStillFits() {
        let l = layout(0, Self.tall)
        #expect(l.cardSize.width >= 64)
        #expect(l.switchBand.height == 64 && l.statusLine.height == 56 && l.actionRow.height == 96)
        let pileBottom = l.deck.y - l.cardSize.height / 2
        #expect(l.actionRow.maxY <= pileBottom)
        // The chrome grew, so the cards are no bigger than with the standard chrome.
        #expect(l.cardSize.width <= layout(0).cardSize.width)
    }

    @Test func tallChromeShrinksTheCardsWhenItMustButNeverBelowTheMinimum() {
        // A short window: the chrome takes most of it.
        let huge = ControllerChrome(switchBand: 80, status: 80, actions: 140)
        let roomy = TableLayout(size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0, opponents: 3, controller: .standard)
        let squeezed = TableLayout(size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0, opponents: 3, controller: huge)
        #expect(squeezed.cardSize.width < roomy.cardSize.width)
        #expect(squeezed.cardSize.width >= 64)
        #expect(squeezed.actionRow.maxY <= squeezed.deck.y - squeezed.cardSize.height / 2)
    }
}

// MARK: helpers

private func safeArea(_ l: TableLayout) -> CGRect {
    CGRect(x: 0, y: l.safeBottom, width: l.size.width, height: l.size.height - l.safeTop - l.safeBottom)
}

private func cardRect(_ p: CGPoint, _ s: CGSize) -> CGRect {
    CGRect(x: p.x - s.width / 2, y: p.y - s.height / 2, width: s.width, height: s.height)
}

/// Every frame a controller shows, named.
private func frames(_ l: TableLayout) -> [(String, CGRect)] {
    [
        ("switch", l.switchBand), ("menu", l.menuButtonFrame), ("status", l.statusLine),
        ("deck", cardRect(l.deck, l.cardSize)), ("discard", cardRect(l.discard, l.cardSize)),
        ("actions", l.actionRow), ("sort", l.sortButtonFrame), ("seat tag", l.seatTagFrame),
        ("trays", l.traysFrame),
    ]
}

/// Shares some area (touching edges don't count).
private func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
    let r = a.intersection(b)
    return !r.isNull && r.width > 0.01 && r.height > 0.01
}

private func rotatedBounds(_ c: CardPlacement, _ s: CGSize) -> CGRect {
    let hw = s.width / 2, hh = s.height / 2
    let cs = cos(c.rotation), sn = sin(c.rotation)
    let xs = [-hw, hw].flatMap { x in [-hh, hh].map { y in c.position.x + x * cs - y * sn } }
    let ys = [-hw, hw].flatMap { x in [-hh, hh].map { y in c.position.y + x * sn + y * cs } }
    return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
}
