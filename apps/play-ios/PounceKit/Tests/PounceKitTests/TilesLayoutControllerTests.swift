import CoreGraphics
import Testing
@testable import PounceKit

/// A phone that is a controller for a TV table. Off turn: just the rack, large, under the switch
/// and the status line. On its turn: the full table, under the switch.
@Suite struct TilesLayoutControllerTests {
    /// iPhone SE, iPhone 17 Pro, iPhone 17 Pro Max, iPad portrait, iPad landscape.
    static let screens: [(size: CGSize, top: CGFloat, bottom: CGFloat)] = [
        (CGSize(width: 375, height: 667), 20, 0), (CGSize(width: 402, height: 874), 62, 34),
        (CGSize(width: 440, height: 956), 62, 34), (CGSize(width: 820, height: 1180), 24, 20),
        (CGSize(width: 1180, height: 820), 24, 20),
    ]
    /// 14 is the deal; 21 fills the stash's row limit on a phone; 22 and 28 are ordinary racks
    /// later in a game; 40 scrolls even on an iPad's off-turn rack.
    static let counts = [14, TilesLayout.rackRowLimit * 7, 22, 28, 40]
    static let tall = ControllerChrome(switchBand: 64, status: 56, actions: 96)

    private func rackOnly(_ i: Int, _ count: Int, _ chrome: ControllerChrome = .standard) -> TilesLayout {
        let s = Self.screens[i]
        return TilesLayout(
            size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: 3, rackCount: count, controller: .rackOnly(chrome))
    }

    private func table(_ i: Int, _ count: Int, controller: TilesLayout.Controller? = nil, meter: Bool = false) -> TilesLayout {
        let s = Self.screens[i]
        return TilesLayout(
            size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: 3, rackCount: count, meter: meter, controller: controller)
    }

    // MARK: off turn: the rack alone

    @Test(arguments: screens.indices)
    func offTurnIsTheRackAlone(_ i: Int) {
        let l = rackOnly(i, 14)
        #expect(l.arrangement == .controller)
        #expect(l.controller == .rackOnly(.standard))
        #expect(l.opponentsBar == .zero && l.opponentSlots.isEmpty)
        #expect(l.rugArt == .zero && l.rug == .zero && l.pool == .zero)
        #expect(l.strip == .zero && l.meter == .zero && l.recap == .zero)
        for control in [l.undo, l.reset, l.turn, l.tidy] { #expect(control == .zero) }
        // The stash keeps its two sort toggles.
        #expect(l.sortNumber != .zero && l.sortToy != .zero)
        // A layout without the parameter is the table it always was.
        let plain = table(i, 14)
        #expect(plain.controller == nil && plain.switchBand == .zero && plain.statusLine == .zero)
        #expect(plain.arrangement == TableLayout.arrangement(for: Self.screens[i].size))
        #expect(l.roomy == plain.roomy)
    }

    @Test(arguments: screens.indices, counts)
    func theRackIsInsideTheSafeAreaAndClearOfTheChrome(_ i: Int, _ count: Int) {
        for chrome in [ControllerChrome.standard, Self.tall] {
            let l = rackOnly(i, count, chrome)
            let safe = safeArea(l)
            let menu = menuFrame(l)
            let frames = [
                ("switch", l.switchBand), ("status", l.statusLine), ("menu", menu), ("rack", l.rack),
                ("sort number", l.sortNumber), ("sort toy", l.sortToy),
            ]
            for (name, frame) in frames {
                #expect(safe.insetBy(dx: -0.01, dy: -0.01).contains(frame), "\(l.size) \(count): \(name) \(frame) outside \(safe)")
            }
            #expect(l.switchBand.contains(menu))
            for (a, first) in frames.enumerated() where first.0 != "menu" {
                for second in frames[(a + 1)...] where second.0 != "menu" {
                    #expect(!overlaps(first.1, second.1), "\(l.size) \(count): \(first.0) \(first.1) overlaps \(second.0) \(second.1)")
                }
            }
            // The sort toggles sit over the stash's right end, under the status line, full size.
            for toggle in [l.sortNumber, l.sortToy] {
                #expect(toggle.minY >= l.rack.maxY && toggle.maxY <= l.statusLine.minY)
                #expect(toggle.width >= 44 && toggle.height >= 44)
            }
            #expect(l.sortNumber.maxX < l.sortToy.minX)
            let pieces = l.rackSlots(count: count).centers.map { pieceRect($0, l.rackPiece) }
            #expect(pieces.count == count)
            let scrolls = l.rackScrollLimit(count: count) > 0
            for (a, piece) in pieces.enumerated() {
                // A scrolling stash runs off the right edge (it scrolls sideways), never up or down.
                let inside = scrolls
                    ? piece.minY >= l.rack.minY && piece.maxY <= l.rack.maxY && piece.minX >= 0
                    : l.rack.contains(piece) && safe.contains(piece)
                #expect(inside, "\(l.size) \(count): piece \(a) \(piece) outside the rack \(l.rack)")
                for other in pieces[(a + 1)...] { #expect(!overlaps(piece, other)) }
            }
            // The deal and a full phone stash: all of it on screen, nothing to scroll.
            if count <= TilesLayout.rackRowLimit * 7 { #expect(!scrolls, "\(l.size) \(count)") }
            if !scrolls, let last = pieces.map(\.maxX).max() {
                #expect(abs(l.sortToy.maxX - last) < 0.5, "\(l.size) \(count): the toggles end at \(l.sortToy.maxX), the rows at \(last)")
            }
            // It scrolls only when the rows are full at no smaller than the table stash's size,
            // as many to a row as fit at that size.
            if scrolls {
                let stash = table(i, count).rackPiece.width
                #expect(l.rackPiece.width >= stash, "\(l.size) \(count)")
                let gap: CGFloat = l.roomy ? 6 : 4, side: CGFloat = l.roomy ? 24 : 8
                #expect(CGFloat(l.rackColumns + 1) * (stash + gap) - gap > l.size.width - 2 * side, "\(l.size) \(count): room for another column")
                #expect(l.rackRows == TilesLayout.rackRowLimit)
            }
            #expect(l.rackRows <= TilesLayout.rackRowLimit)
            #expect(menu.width >= 44 && menu.height >= 44)
            #expect(l.switchBand.height >= max(chrome.switchBand, 44) && l.statusLine.height >= chrome.status)
        }
    }

    @Test(arguments: screens.indices, counts)
    func thePiecesAreAtLeastAsBigAsOnTheTable(_ i: Int, _ count: Int) {
        let l = rackOnly(i, count), plain = table(i, count)
        #expect(l.rackPiece.width >= plain.rackPiece.width, "\(l.size) \(count): \(l.rackPiece.width) vs \(plain.rackPiece.width)")
        #expect(l.rackPiece.height == (l.rackPiece.width * TilesLayout.pieceAspect).rounded())
        // The deal's fourteen are bigger than a phone stash's 48 pt.
        if count == 14 { #expect(l.rackPiece.width > 48, "\(l.size): \(l.rackPiece.width)") }
    }

    @Test(arguments: screens.indices)
    func theRackIsCentredInTheRoomLeft(_ i: Int) {
        let l = rackOnly(i, 14)
        let room = (l.statusLine.minY + l.safeBottom) / 2
        // The stash and its toggles, together.
        let group = l.rack.union(l.sortNumber).union(l.sortToy)
        #expect(abs(group.midY - room) <= 8, "\(l.size): stash at \(group.midY), room's middle \(room)")
        let xs = l.rackSlots(count: 14).centers.map(\.x)
        #expect(abs((xs.min()! + xs.max()!) / 2 - l.size.width / 2) < 0.5)
    }

    @Test func anSEAtTheLargestTextSizeStillFits() {
        for count in Self.counts {
            let l = rackOnly(0, count, Self.tall)
            #expect(l.rack.maxY <= l.statusLine.minY)
            #expect(l.rack.minY >= l.safeBottom)
            if count <= TilesLayout.rackRowLimit * 7 { #expect(l.rackScrollLimit(count: count) == 0) }
            #expect(l.rackPiece.width >= table(0, count).rackPiece.width)
        }
    }

    // MARK: on turn: the full table under the switch

    @Test(arguments: screens.indices)
    func onTurnTheTableSitsUnderTheSwitch(_ i: Int) {
        for meter in [false, true] {
            let l = table(i, 14, controller: .fullTable(.standard), meter: meter)
            let plain = table(i, 14, meter: meter)
            let safe = safeArea(l)
            #expect(l.arrangement == plain.arrangement)
            #expect(l.controller == .fullTable(.standard))
            #expect(l.statusLine == .zero)
            #expect(abs(l.switchBand.maxY - (l.size.height - l.safeTop)) < 0.01)
            #expect(l.switchBand.height >= 44)
            #expect(safe.contains(l.switchBand))
            #expect(l.switchBand.contains(menuFrame(l)))
            // The table below it is today's, pushed down by the band.
            #expect(l.opponentsBar.maxY <= l.switchBand.minY + 0.01)
            #expect(abs(l.opponentsBar.maxY - (plain.opponentsBar.maxY - l.switchBand.height)) < 0.01)
            #expect(l.rack == plain.rack && l.strip == plain.strip && l.turn == plain.turn && l.rackPiece == plain.rackPiece)
            #expect(l.rugArt.maxY <= l.opponentsBar.minY && l.rugArt.minY >= l.strip.maxY)
            #expect(l.rug.height > 150, "\(l.size): the rug is too short to play on: \(l.rug.height)")
            // The toy box stays in the bar's corner, under the band, in the paw's old place (the
            // paw is up in the band now): no hole where the paw was.
            #expect(!overlaps(l.pool, l.switchBand) && l.pool.maxY <= l.switchBand.minY)
            #expect(l.pool.minY >= l.rugArt.maxY)
            #expect(abs(l.pool.midX - plain.menuButton.x) < 0.5)
            let pawDrop = plain.opponentsBar.maxY - plain.menuButton.y, boxDrop = l.opponentsBar.maxY - l.pool.midY
            #expect(abs(boxDrop - pawDrop) <= 2.01, "\(l.size): the toy box is \(boxDrop) under the bar's top, the paw was \(pawDrop)")
            #expect(!overlaps(l.pool, menuFrame(l)))
            for (j, slot) in l.opponentSlots.enumerated() {
                #expect(l.opponentsBar.contains(slot), "slot \(j)")
            }
        }
    }

    @Test func anSEOnTurnAtTheLargestTextSize() {
        let l = table(0, 14, controller: .fullTable(Self.tall))
        #expect(l.switchBand.height == 64)
        #expect(l.opponentsBar.maxY <= l.switchBand.minY + 0.01)
        #expect(l.rug.height > 100)
    }
}

// MARK: helpers

private func safeArea(_ l: TilesLayout) -> CGRect {
    CGRect(x: 0, y: l.safeBottom, width: l.size.width, height: l.size.height - l.safeTop - l.safeBottom)
}

private func menuFrame(_ l: TilesLayout) -> CGRect {
    let d = max(l.menuSide, TilesLayout.buttonHit)
    return CGRect(x: l.menuButton.x - d / 2, y: l.menuButton.y - d / 2, width: d, height: d)
}

private func pieceRect(_ c: CGPoint, _ s: CGSize) -> CGRect {
    CGRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height)
}

private func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
    let r = a.intersection(b)
    return !r.isNull && r.width > 0.01 && r.height > 0.01
}
