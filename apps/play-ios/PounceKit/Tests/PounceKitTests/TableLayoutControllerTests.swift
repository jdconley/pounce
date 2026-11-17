import CoreGraphics
import Testing
@testable import PounceKit

/// A phone that is a controller for a TV table: only its own cards, the piles and room for the
/// SwiftUI chrome (the "Cards" | "Table" switch, the status line, the action row).
@Suite("TableLayout, controller")
struct TableLayoutControllerTests {
    /// iPhone SE, iPhone 17 Pro, iPhone 17 Pro Max, iPad portrait, iPad landscape, a 13-inch iPad
    /// portrait and landscape.
    static let screens: [(size: CGSize, top: CGFloat, bottom: CGFloat)] = [
        (CGSize(width: 375, height: 667), 20, 0), (CGSize(width: 402, height: 874), 62, 34),
        (CGSize(width: 440, height: 956), 62, 34), (CGSize(width: 820, height: 1180), 24, 20),
        (CGSize(width: 1180, height: 820), 24, 20), (CGSize(width: 1024, height: 1366), 24, 20),
        (CGSize(width: 1366, height: 1024), 24, 20),
    ]
    /// The chrome at the largest accessibility text size.
    static let tall = ControllerChrome(switchBand: 64, status: 56, actions: 96)

    /// Every hand a controller lays out: eleven cards with trays (before laying down), eleven
    /// without, a short hand without trays (after laying down) and with them.
    static let hands: [ControllerHand] = [
        .full, ControllerHand(short: false, trays: false), ControllerHand(short: true, trays: false),
        ControllerHand(short: true, trays: true),
    ]

    private func layout(_ i: Int, _ chrome: ControllerChrome = .standard, _ hand: ControllerHand = .full) -> TableLayout {
        let s = Self.screens[i]
        return TableLayout(size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: 3, controller: chrome, hand: hand)
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
        #expect(table.pileSize == table.cardSize && table.chromeOverflow == 0 && table.fits)
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
            for hand in Self.hands {
                let l = layout(i, chrome, hand)
                #expect(l.fits, "\(l.size) \(hand): \(l.chromeOverflow) pt over")
                expectNothingOverlaps(l, cards: hand.short ? ControllerHand.shortMax : 11)
            }
        }
    }

    @Test(arguments: screens.indices)
    func topToBottom(_ i: Int) {
        let l = layout(i)
        let pileTop = l.deck.y + l.pileSize.height / 2
        let pileBottom = l.deck.y - l.pileSize.height / 2
        #expect(l.switchBand.maxY <= l.size.height - l.safeTop + 0.01)
        #expect(l.statusLine.maxY <= l.switchBand.minY + 0.01)
        #expect(pileTop <= l.statusLine.minY)
        #expect(l.deck.y == l.discard.y && l.deck.x < l.discard.x)
        // The switch band and the status line hug the top.
        #expect(abs(l.switchBand.maxY - (l.size.height - l.safeTop)) < 0.01)
        #expect(l.controllerSideBySide == (TableLayout.arrangement(for: l.size) == .wide))
        if l.controllerSideBySide {
            // A landscape iPad: the piles in the left half of the trays' width, the action row in
            // the right half beside them, level with them; all of it over the trays.
            #expect(l.traysFrame.maxY <= pileBottom && l.traysFrame.maxY <= l.actionRow.minY)
            #expect(l.discard.x + l.pileSize.width / 2 < l.actionRow.minX)
            #expect(abs(l.actionRow.midY - l.deck.y) < 0.5)
            #expect(abs((l.deck.x + l.discard.x) / 2 - (l.traysFrame.minX + l.traysFrame.width / 4)) < 12)
            #expect(l.actionRow.maxX <= l.traysFrame.maxX + 0.01)
        } else {
            #expect(l.actionRow.maxY <= pileBottom)
            #expect(l.traysFrame.maxY <= l.actionRow.minY)
            #expect(l.deck.x < l.size.width / 2 && l.discard.x > l.size.width / 2)
            #expect(abs((l.deck.x + l.discard.x) / 2 - l.size.width / 2) < 0.01)
            // The action row sits on the trays.
            #expect(l.actionRow.minY - l.traysFrame.maxY <= TableLayout.sortButtonHit + 16)
        }
    }

    /// No dead band: the hand, trays and action row sit together at the bottom, and the piles
    /// grow into the room above them, then sit in its middle, so the gap from the action row up to
    /// the piles is the same as the gap above them. In the two usual hands (eleven cards before
    /// laying down, a short hand after) that gap is at most a sixth of the safe height; in any
    /// other, the piles are as big as they get.
    @Test(arguments: screens.indices)
    func thePilesFillTheRoomBetweenTheStatusLineAndTheActionRow(_ i: Int) {
        for chrome in [ControllerChrome.standard, Self.tall] {
            for hand in Self.hands {
                let l = layout(i, chrome, hand)
                // Side by side, the room starts on the trays (the action row is beside the piles).
                let floor = l.controllerSideBySide ? l.traysFrame.maxY + 6 : l.actionRow.maxY
                let below = (l.deck.y - l.pileSize.height / 2) - floor
                let above = l.statusLine.minY - (l.deck.y + l.pileSize.height / 2)
                let safeHeight = l.size.height - l.safeTop - l.safeBottom
                #expect(below >= 8 && above >= 8, "\(l.size) \(hand): \(above) above, \(below) below")
                #expect(abs(above - below) < 0.5, "\(l.size) \(hand): \(above) above, \(below) below")
                let usual = hand == .full || hand == ControllerHand(short: true, trays: false)
                let pairWidth = l.controllerSideBySide ? l.traysFrame.width / 2 - 12 : l.size.width - 16
                let atMost = l.pileSize.width >= min((l.cardSize.width * 1.5).rounded(.down), pairWidth / 2 - 24)
                #expect(below <= safeHeight / 6 || (!usual && atMost),
                        "\(l.size) \(hand): \(below) pt between the action row and the piles")
                // Piles give way to the hand only down to three quarters of a hand card.
                #expect(l.pileSize.width >= (l.cardSize.width * 0.75).rounded(.down))
                #expect(l.pileSize.height == (l.pileSize.width * 90 / 64).rounded())
            }
        }
    }

    /// The hand, the trays and the action row are one block at the bottom: the trays on the hand
    /// (none: no strip at all), the action row on them, and the sort button at the action row's
    /// right end, on its line.
    @Test(arguments: screens.indices)
    func theHandTheTraysAndTheActionRowAreOneBlock(_ i: Int) {
        for hand in Self.hands {
            let l = layout(i, .standard, hand)
            let handTop = l.hand(count: 11, lifted: nil).map { rotatedBounds($0, l.cardSize).maxY }.max() ?? 0
            // On the hand; with no trays, as high over it as a picked card rises.
            let reserve = hand.trays ? 12 : 40
            #expect(l.traysFrame.minY - handTop <= CGFloat(reserve), "\(l.size) \(hand): trays float \(l.traysFrame.minY - handTop) over the hand")
            // A picked card (any of eleven, or of a short hand) stays clear of the action row and the sort button.
            let n = hand.short ? ControllerHand.shortMax : 11
            for k in 0..<n {
                let r = rotatedBounds(l.hand(count: n, lifted: k)[k], l.cardSize)
                #expect(!overlaps(r, l.actionRow) && !overlaps(r, l.sortButtonFrame),
                        "\(l.size) \(hand): picked card \(k) of \(n) \(r) reaches the action row \(l.actionRow)")
            }
            if !hand.trays { #expect(l.traysFrame.height == 0) }
            let sort = l.sortButtonFrame
            if l.controllerSideBySide {
                // At the trays' trailing edge (or the fan's, if wider): beside the trays, or with
                // none, beside the hand's top.
                // The fan the hand is sized for: eleven cards, or a short hand's eight.
                let n = hand.short ? ControllerHand.shortMax : 11
                let handTopY = l.hand(count: n, lifted: nil).map(\.position.y).max() ?? 0
                let fanRight = l.hand(count: n, lifted: nil).map { rotatedBounds($0, l.cardSize).maxX }.max() ?? 0
                let edge = max(hand.trays ? l.traysFrame.maxX : 0, fanRight)
                #expect(sort.minX >= edge - 0.5 && sort.minX - edge <= 12, "\(l.size) \(hand): sort \(sort) vs edge \(edge)")
                if hand.trays {
                    #expect(abs(sort.midY - l.traysFrame.midY) < 0.5)
                } else {
                    #expect(sort.minY >= handTopY - 0.01 && sort.minY - handTopY <= l.cardSize.height)
                }
            } else {
                #expect(l.actionRow.minY - l.traysFrame.maxY <= 8)
                #expect(sort.minX >= l.actionRow.maxX && sort.maxX <= l.traysFrame.maxX + 0.01)
                #expect(sort.minY >= l.actionRow.minY - 0.01 && sort.maxY <= l.actionRow.maxY + 0.01)
                // Clear of the last chip by a margin (wider on an iPad).
                #expect(sort.minX - l.actionRow.maxX >= (l.roomy ? 16 : 4) - 0.01)
            }
            #expect(l.seatTagFrame == .zero, "the status line names the player on a controller")
        }
    }

    @Test(arguments: screens.indices)
    func theMinimumsHold(_ i: Int) {
        for chrome in [ControllerChrome.standard, Self.tall] {
            let l = layout(i, chrome)
            #expect(l.cardSize.width >= 64, "\(l.size): cards \(l.cardSize.width) wide")
            #expect(l.pileSize.width >= 44)
            #expect(l.menuButtonFrame.width >= 44 && l.menuButtonFrame.height >= 44)
            #expect(l.sortButtonFrame.width >= 44 && l.sortButtonFrame.height >= 44)
            #expect(l.switchBand.height >= max(chrome.switchBand, 44))
            #expect(l.statusLine.height >= chrome.status)
            #expect(l.actionRow.height >= chrome.actions)
            if l.controllerSideBySide {
                // Half the trays' width, beside the piles.
                #expect(l.actionRow.width >= l.traysFrame.width / 2 - 12 - 0.01)
            } else {
                // The row is the trays' width less the sort button at its end.
                let reserve = TableLayout.sortButtonHit + (l.roomy ? 16 : 4)
                #expect(abs(l.actionRow.width + reserve - l.traysFrame.width) < 0.01)
                #expect(l.actionRow.width >= min(l.size.width - 48, 560) - reserve)
            }
            for tray in l.trayFrames(count: 3) { #expect(tray.width >= 44 && tray.height >= 44) }
        }
    }

    @Test(arguments: screens.indices)
    func theCardsAreBiggerThanOnTheTable(_ i: Int) {
        let s = Self.screens[i]
        let table = TableLayout(size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: 3)
        let l = layout(i)
        // A good fifth bigger at least (the width caps eleven cards).
        #expect(l.cardSize.width >= table.cardSize.width * 1.15, "\(s.size): \(l.cardSize.width) vs \(table.cardSize.width)")
        // Eleven cards still fan: each shows its corner.
        let hand = l.hand(count: 11, lifted: nil)
        #expect(hand[1].position.x - hand[0].position.x >= max(24, l.cardSize.width * TableLayout.stripRatio - 0.01))
    }

    /// A short hand (after laying down) is drawn bigger still, and eight of them still fan.
    @Test(arguments: screens.indices)
    func aShortHandIsBiggerStill(_ i: Int) {
        let s = Self.screens[i]
        let table = TableLayout(size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: 3)
        let full = layout(i)
        for hand in [ControllerHand(short: true, trays: false), ControllerHand(short: true, trays: true)] {
            let l = layout(i, .standard, hand)
            // A fifth bigger on a phone; a squat iPad window has less height to give.
            #expect(l.cardSize.width >= full.cardSize.width * (l.roomy ? 1.1 : 1.15), "\(s.size): \(l.cardSize.width) vs \(full.cardSize.width)")
            #expect(l.cardSize.width >= table.cardSize.width * 1.3)
            let fan = l.hand(count: ControllerHand.shortMax, lifted: nil)
            #expect(fan[1].position.x - fan[0].position.x >= l.cardSize.width * TableLayout.stripRatio - 0.01)
        }
        // Trays or not, a hand of one size: the cards only change between short and full.
        #expect(layout(i, .standard, ControllerHand(short: false, trays: false)).cardSize == full.cardSize)
    }

    @Test func anSEAtTheLargestTextSizeStillFits() {
        let l = layout(0, Self.tall)
        #expect(l.cardSize.width >= 64)
        #expect(l.switchBand.height == 64 && l.statusLine.height == 56 && l.actionRow.height == 96)
        let pileBottom = l.deck.y - l.pileSize.height / 2
        #expect(l.actionRow.maxY <= pileBottom)
        #expect(l.fits)
        // The chrome grew, so the cards are no bigger than with the standard chrome.
        #expect(l.cardSize.width <= layout(0).cardSize.width)
    }

    /// Tall chrome takes room from the piles first (down to three quarters of a hand card), then
    /// from the hand, down to its floor, then from the piles again.
    @Test func tallChromeShrinksThePilesThenTheHandThenThePiles() {
        let size = CGSize(width: 375, height: 667)
        func l(_ chrome: ControllerChrome) -> TableLayout {
            TableLayout(size: size, safeTop: 20, safeBottom: 0, opponents: 3, controller: chrome)
        }
        let roomy = l(.standard)
        let tall = l(ControllerChrome(switchBand: 80, status: 80, actions: 140))
        #expect(tall.cardSize.width == roomy.cardSize.width)
        #expect(tall.pileSize.width < roomy.pileSize.width && tall.pileSize.width >= (tall.cardSize.width * 0.75).rounded(.down))
        #expect(tall.fits)
        expectNothingOverlaps(tall)
        let squeezed = l(ControllerChrome(switchBand: 80, status: 80, actions: 210))
        #expect(squeezed.cardSize.width < roomy.cardSize.width)
        #expect(squeezed.cardSize.width == TableLayout.controllerCardMin)
        #expect(squeezed.pileSize.width < squeezed.cardSize.width && squeezed.pileSize.width >= 44)
        #expect(squeezed.fits)
        expectNothingOverlaps(squeezed)
    }

    /// Chrome too tall for the screen (the largest text, a status line that wraps): the layout
    /// says by how much, and with that much taken off the chrome everything fits again.
    @Test func chromeTooTallSaysByHowMuch() {
        let size = CGSize(width: 375, height: 667)
        let over = ControllerChrome(switchBand: 80, status: 112, actions: 210)
        let l = TableLayout(size: size, safeTop: 20, safeBottom: 0, opponents: 3, controller: over)
        #expect(!l.fits)
        #expect(l.chromeOverflow > 0)
        #expect(l.cardSize.width == TableLayout.controllerCardMin && l.pileSize.width == 44)
        // Everything but the piles still stays clear.
        #expect(l.actionRow.minY >= l.traysFrame.maxY && l.statusLine.minY >= l.actionRow.maxY)
        var capped = over
        capped.status -= l.chromeOverflow.rounded(.up)
        let again = TableLayout(size: size, safeTop: 20, safeBottom: 0, opponents: 3, controller: capped)
        #expect(again.fits)
        expectNothingOverlaps(again)
    }
}

/// Nothing a controller shows overlaps, but the paw in its band and the fanned cards with each
/// other; every frame and card inside the safe area.
private func expectNothingOverlaps(_ l: TableLayout, cards: Int = 11) {
    let all = frames(l)
    let safe = safeArea(l).insetBy(dx: -0.01, dy: -0.01)
    for (a, (nameA, frameA)) in all.enumerated() {
        #expect(safe.contains(frameA), "\(l.size): \(nameA) \(frameA) outside the safe area")
        for (nameB, frameB) in all[(a + 1)...] {
            // The paw sits at the switch band's right end.
            if Set([nameA, nameB]) == ["switch", "menu"] { continue }
            #expect(!overlaps(frameA, frameB), "\(l.size): \(nameA) \(frameA) overlaps \(nameB) \(frameB)")
        }
    }
    for n in 1...cards {
        // Resting, and with each card in turn picked up (lifted out of the fan).
        for lifted in [nil] + Array(0..<n) {
            for (k, c) in l.hand(count: n, lifted: lifted).enumerated() where lifted == nil || k == lifted {
                let r = rotatedBounds(c, l.cardSize)
                #expect(safe.contains(r))
                // A lifted card rises over the trays, as on the table; never into anything else.
                for (name, frame) in all where !(lifted != nil && name == "trays") {
                    #expect(!overlaps(r, frame), "\(l.size): card \(k) of \(n) (lifted \(String(describing: lifted))) overlaps \(name)")
                }
            }
        }
    }
    let trays = l.trayFrames(count: 3)
    for (a, b) in zip(trays, trays.dropFirst()) { #expect(!overlaps(a, b)) }
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
        ("deck", cardRect(l.deck, l.pileSize)), ("discard", cardRect(l.discard, l.pileSize)),
        ("actions", l.actionRow), ("sort", l.sortButtonFrame), ("seat tag", l.seatTagFrame),
        ("trays", l.traysFrame),
    ].filter { $0.1.width > 0 && $0.1.height > 0 }
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
