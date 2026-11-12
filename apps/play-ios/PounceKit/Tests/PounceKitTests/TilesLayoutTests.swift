import CoreGraphics
import Testing
@testable import PounceKit

@Suite struct TilesLayoutTests {
    /// iPhone SE, iPhone 17 Pro, iPhone 17 Pro Max, iPad portrait, iPad landscape.
    static let screens: [(size: CGSize, top: CGFloat, bottom: CGFloat)] = [
        (CGSize(width: 375, height: 667), 20, 0), (CGSize(width: 402, height: 874), 62, 34),
        (CGSize(width: 440, height: 956), 62, 34), (CGSize(width: 834, height: 1210), 24, 20),
        (CGSize(width: 1210, height: 834), 24, 20),
    ]

    private func layout(_ i: Int, rack: Int = 14, opponents: Int = 3, meter: Bool = false, controls: Bool = true) -> TilesLayout {
        let s = Self.screens[i]
        return TilesLayout(size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: opponents, rackCount: rack, meter: meter, controls: controls)
    }

    @Test(arguments: screens.indices)
    func theBandsStackWithoutOverlapping(_ i: Int) {
        for meter in [false, true] {
            let l = layout(i, meter: meter)
            #expect(l.rack.minY >= Self.screens[i].bottom)
            #expect(l.strip.minY >= l.rack.maxY - 0.5)
            #expect(l.rugArt.minY >= l.strip.maxY)
            if meter { #expect(l.rugArt.minY >= l.meter.maxY) } else { #expect(l.meter == .zero) }
            #expect(l.rugArt.maxY <= l.opponentsBar.minY)
            #expect(l.rugArt.contains(l.rug))
            #expect(l.rug.contains(l.pool))
            #expect(l.rug.height > 180, "the rug is too short to play on: \(l.rug.height)")
            #expect(l.rugArt.minX >= 0 && l.rugArt.maxX <= l.size.width)
        }
    }

    /// The paw menu is below the safe top (never under the status bar) and clear of every cat.
    @Test(arguments: screens.indices)
    func thePawMenuIsBelowTheStatusBarAndClearOfTheCats(_ i: Int) {
        let s = Self.screens[i]
        for n in 1...3 {
            let l = layout(i, opponents: n)
            let paw = CGRect(
                x: l.menuButton.x - l.menuSide / 2, y: l.menuButton.y - l.menuSide / 2, width: l.menuSide, height: l.menuSide)
            #expect(paw.maxY <= s.size.height - s.top, "\(s.size) \(n) cats: the paw reaches into the status bar")
            #expect(paw.maxX <= s.size.width && paw.minX >= 0)
            let d = l.catDiameter
            for (j, slot) in l.opponentSlots.enumerated() {
                let cat = CGRect(x: slot.x - d / 2, y: slot.y + l.catLift - d / 2, width: d, height: d)
                let shared = paw.intersection(cat)
                #expect(shared.isNull || shared.width * shared.height <= 12, "\(s.size) \(n) cats, slot \(j): \(shared)")
            }
        }
    }

    @Test(arguments: screens.indices)
    func everyControlIsOnScreenBigEnoughAndClearOfTheOthers(_ i: Int) {
        let l = layout(i, meter: true)
        let controls = [l.undo, l.reset, l.turn, l.sortNumber, l.sortToy, l.tidy]
        for (a, frame) in controls.enumerated() {
            #expect(frame.width >= 44 && frame.height >= 44, "control \(a) is under 44 pt")
            #expect(frame.minX >= 0 && frame.maxX <= l.size.width)
            #expect(l.strip.insetBy(dx: 0, dy: -1).contains(frame))
            for (b, other) in controls.enumerated() where b > a {
                #expect(!frame.intersects(other), "controls \(a) and \(b) overlap")
            }
        }
        // A big target, in the middle of the gap between the two groups of buttons.
        #expect(l.turn.width >= 110)
        #expect(abs((l.turn.minX - l.reset.maxX) - (l.sortNumber.minX - l.turn.maxX)) < 1 || l.arrangement != .phone)
    }

    @Test func aPhonesStashIsTwoRowsOfSevenAt48Points() {
        // 393 pt wide is the spec's phone.
        let l = TilesLayout(size: CGSize(width: 393, height: 852), safeTop: 59, safeBottom: 34, opponents: 3, rackCount: 14)
        #expect(l.rackColumns == 7)
        #expect(l.rackRows == 2)
        #expect(l.rackPiece.width == 48)
        let slots = l.rackSlots(count: 14)
        #expect(slots.centers.count == 14)
        #expect(Set(slots.centers.map(\.y)).count == 2)
        #expect(slots.centers.prefix(7).allSatisfy { $0.y == slots.centers[0].y })
        // Everything on screen, nothing to scroll.
        #expect(slots.centers.allSatisfy { $0.x - 24 >= 0 && $0.x + 24 <= 393 })
        #expect(l.rackScrollLimit(count: 14) == 0)
        // Pieces don't touch.
        #expect(slots.centers[1].x - slots.centers[0].x >= 48)
        // The stash sits inside its band.
        #expect(slots.centers.allSatisfy { l.rack.contains($0) })
    }

    @Test func aThirdRowComesAtFifteenAndPastTwentyOneTheStashScrolls() {
        func phone(_ count: Int) -> TilesLayout {
            TilesLayout(size: CGSize(width: 393, height: 852), safeTop: 59, safeBottom: 34, opponents: 3, rackCount: count)
        }
        #expect(phone(3).rackRows == 2, "a phone keeps two rows, so the rug doesn't jump on a draw")
        #expect(phone(14).rackRows == 2)
        #expect(phone(15).rackRows == 3)
        #expect(phone(21).rackRows == 3)
        #expect(phone(21).rackScrollLimit(count: 21) == 0)
        let big = phone(26)
        #expect(big.rackRows == 3)
        #expect(big.rackScrollLimit(count: 26) > 0)
        let slots = big.rackSlots(count: 26).centers
        #expect(Set(slots.map(\.y)).count == 3)
        // Nine to a row, so the rows run off the right edge.
        #expect(slots[8].y == slots[0].y)
        #expect(slots[9].y < slots[0].y)
        #expect(slots[8].x > 393)
        // A taller stash leaves a shorter rug.
        #expect(phone(15).rug.height < phone(14).rug.height)
    }

    @Test func theSlotUnderAFingerIsTheNearestPlace() {
        let l = TilesLayout(size: CGSize(width: 393, height: 852), safeTop: 59, safeBottom: 34, opponents: 3, rackCount: 9)
        let places = l.rackSlots(count: 10).centers
        for (i, place) in places.enumerated() {
            #expect(l.rackSlot(at: place, count: 9) == i)
            #expect(l.rackSlot(at: CGPoint(x: place.x + 5, y: place.y - 6), count: 9) == i)
        }
        #expect(l.rackSlot(at: CGPoint(x: -50, y: places[0].y), count: 9) == 0)
        #expect(l.rackSlot(at: .zero, count: 0) == 0)
    }

    @Test func withNoSeatHereTheRugTakesTheRoom() {
        let with = layout(1), without = layout(1, controls: false)
        #expect(without.rack.height == 0)
        #expect(without.strip.height == 0)
        #expect(without.turn == .zero)
        #expect(without.rug.height > with.rug.height + 100)
        #expect(without.rackSlots(count: 5).centers.isEmpty)
    }

    @Test func aRoomyScreenGetsFourteenAcrossAndBiggerPieces() {
        let pad = layout(4)
        #expect(pad.arrangement == .wide)
        #expect(pad.rackColumns == 14)
        #expect(pad.rackRows == 1)
        #expect(pad.rackPiece.width > 48)
        #expect(pad.rugPieceMax > 30)
        #expect(layout(3, rack: 20).rackRows == 2)
    }
}

@Suite struct RugFlowTests {
    private func fit(_ lengths: [Int], width: CGFloat = 355, height: CGFloat = 430, corner: CGSize = CGSize(width: 60, height: 52), zoom: CGFloat? = nil) -> RugFlow {
        RugFlow.fit(lengths: lengths, width: width, height: height, maxPiece: 30, minPiece: 24, corner: corner, zoom: zoom)
    }

    private func checkNoOverlap(_ flow: RugFlow, width: CGFloat, corner: CGSize, _ label: String) {
        let boxes = flow.sets.map(\.frame) + [flow.newSlot]
        for (a, box) in boxes.enumerated() {
            #expect(box.minX >= -0.5 && box.maxX <= width + 0.5, "\(label): box \(a) leaves the rug")
            #expect(box.minY >= -0.5, "\(label)")
            // The toy box's corner is kept clear.
            let cornerRect = CGRect(x: width - corner.width, y: 0, width: corner.width, height: corner.height)
            #expect(!box.insetBy(dx: 1, dy: 1).intersects(cornerRect), "\(label): box \(a) is under the toy box")
            for (b, other) in boxes.enumerated() where b > a {
                #expect(!box.insetBy(dx: 0.5, dy: 0.5).intersects(other), "\(label): boxes \(a) and \(b) overlap")
            }
        }
    }

    @Test func aSmallTableIsDrawnAtThirtyPoints() {
        let flow = fit([3, 4, 3])
        #expect(flow.pieceSize.width == 30)
        #expect(flow.pieceSize.height == 36)
        #expect(!flow.scrolls)
        #expect(flow.sets.count == 3)
        // Left to right like words, pieces shoulder to shoulder inside their set's box. The
        // third set doesn't fit beside the toy box, so it starts the next row.
        #expect(flow.sets.map(\.frame.minY) == [0, 0, 51])
        #expect(flow.sets[1].frame.minX > flow.sets[0].frame.maxX)
        #expect(flow.sets[2].frame.minX == 0)
        for (set, count) in zip(flow.sets, [3, 4, 3]) {
            #expect(set.pieces.count == count)
            #expect(set.pieces.allSatisfy { set.frame.contains($0) })
            #expect(set.pieces[1].x - set.pieces[0].x == 31)
        }
        checkNoOverlap(flow, width: 355, corner: CGSize(width: 60, height: 52), "small")
    }

    @Test func aRowOfThirteenFitsOneRowAtTwentySevenPointsOrLess() {
        let flow = fit([13, 3, 4])
        #expect(flow.pieceSize.width <= 27)
        #expect(flow.pieceSize.width >= 24)
        let row = flow.sets[0]
        #expect(row.frame.width <= 355)
        #expect(Set(row.pieces.map(\.y)).count == 1)
        // Too wide to sit beside the toy box: it goes below it.
        #expect(row.frame.minY >= 52)
        checkNoOverlap(flow, width: 355, corner: CGSize(width: 60, height: 52), "thirteen")
    }

    @Test func aFullTableShrinksToFitAndOnlyThenScrolls() {
        // 25 sets, 80 pieces: the late demo table.
        let late = Array(repeating: [3, 3, 4, 3], count: 6).flatMap { $0 } + [3]
        #expect(late.count == 25)
        let flow = fit(late)
        #expect(flow.pieceSize.width >= 24 && flow.pieceSize.width <= 30)
        #expect(!flow.scrolls, "25 sets should fit a phone's rug")
        checkNoOverlap(flow, width: 355, corner: CGSize(width: 60, height: 52), "late")
        // On a short rug the same table bottoms out at 24 pt and scrolls.
        let short = fit(late, height: 200)
        #expect(short.pieceSize.width == 24)
        #expect(short.scrolls)
        #expect(short.contentHeight > 200)
        checkNoOverlap(short, width: 355, corner: CGSize(width: 60, height: 52), "short")
    }

    @Test func piecesNeverShrinkBelowTheMinimumOrGrowPastTheMaximum() {
        var rng = TilesDraftTests.Rng(state: 5)
        for _ in 0..<200 {
            let lengths = (0..<Int.random(in: 0...34, using: &rng)).map { _ in Int.random(in: 1...13, using: &rng) }
            let width = CGFloat.random(in: 330...420, using: &rng)
            let height = CGFloat.random(in: 200...520, using: &rng)
            let flow = RugFlow.fit(lengths: lengths, width: width, height: height, maxPiece: 30, minPiece: 24, corner: CGSize(width: 60, height: 52))
            #expect(flow.sets.count == lengths.count)
            #expect(flow.pieceSize.width <= 30)
            // Only a set too long for a row at 24 pt takes the size lower.
            let longest = CGFloat(max(lengths.max() ?? 3, 3))
            let cap = ((width - 6 - (longest - 1)) / longest).rounded(.down)
            #expect(flow.pieceSize.width >= min(24, cap))
            #expect(flow.scrolls == (flow.contentHeight > height + 0.5))
            if flow.scrolls { #expect(flow.pieceSize.width == min(24, cap)) }
            checkNoOverlap(flow, width: width, corner: CGSize(width: 60, height: 52), "\(lengths)")
        }
    }

    @Test func theNewSlotFollowsTheLastSet() {
        let empty = fit([])
        #expect(empty.sets.isEmpty)
        #expect(empty.newSlot.minX == 0 && empty.newSlot.minY == 0)
        let flow = fit([3, 3])
        #expect(flow.newSlot.minX > flow.sets[1].frame.maxX)
        #expect(flow.newSlot.minY == flow.sets[1].frame.minY)
        #expect(flow.contentHeight == flow.newSlot.maxY)
    }

    @Test func zoomAsksForASizeAndTheRugScrolls() {
        let late = Array(repeating: 3, count: 25)
        let zoomed = fit(late, zoom: 48)
        #expect(zoomed.pieceSize.width == 48)
        #expect(zoomed.scrolls)
        checkNoOverlap(zoomed, width: 355, corner: CGSize(width: 60, height: 52), "zoomed")
        // A row of thirteen caps the zoom at what fits a row.
        #expect(fit([13], zoom: 48).pieceSize.width <= 27)
    }

    @Test func findsTheSetUnderAPoint() {
        let flow = fit([3, 4, 3, 5, 3])
        for (i, set) in flow.sets.enumerated() {
            #expect(flow.set(at: CGPoint(x: set.frame.midX, y: set.frame.midY)) == i)
            #expect(flow.set(at: CGPoint(x: set.frame.minX - 2, y: set.frame.midY)) == i)
        }
        #expect(flow.set(at: CGPoint(x: 340, y: 400)) == nil)
        // Between two sets side by side, the nearer one wins.
        let a = flow.sets[0].frame, b = flow.sets[1].frame
        #expect(flow.set(at: CGPoint(x: a.maxX + 1, y: a.midY), slop: 6) == 0)
        #expect(flow.set(at: CGPoint(x: b.minX - 1, y: b.midY), slop: 6) == 1)
    }
}
