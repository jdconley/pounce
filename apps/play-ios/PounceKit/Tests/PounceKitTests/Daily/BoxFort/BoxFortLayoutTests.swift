import CoreGraphics
import Testing
@testable import PounceKit

struct BoxFortLayoutTests {
    private func inside(_ inner: CGRect, _ outer: CGRect) -> Bool {
        outer.insetBy(dx: -0.5, dy: -0.5).contains(inner)
    }

    private func check(_ size: CGSize) -> BoxFortLayout {
        let layout = BoxFortLayout(size: size)
        let bounds = CGRect(origin: .zero, size: size)
        #expect(layout.rug.width == layout.rug.height, "the rug is square")
        #expect(abs(layout.rug.width - 8 * layout.cell) < 0.01)
        #expect(inside(layout.header, bounds) && inside(layout.rug, bounds))
        // The rug's border and fringe reach `fringe` spots past its spots; nothing sits on them.
        let drawn = layout.rug.insetBy(dx: -BoxFortLayout.fringe * layout.cell, dy: -BoxFortLayout.fringe * layout.cell)
        #expect(!layout.header.intersects(drawn), "the score row sits on the rug's fringe at \(size)")
        #expect(layout.slots.count == 3)
        for (i, slot) in layout.slots.enumerated() {
            #expect(inside(slot, bounds), "slot \(i) on screen at \(size)")
            #expect(!slot.intersects(drawn), "slot \(i) clear of the rug at \(size)")
            #expect(!slot.intersects(layout.header))
            // The longest piece (five boxes) fits its slot at tray scale.
            #expect(slot.width >= 5 * layout.trayCell && slot.height >= 5 * layout.trayCell)
        }
        // Slots meet edge to edge; a hair inside each, they never overlap.
        let inner = layout.slots.map { $0.insetBy(dx: 0.01, dy: 0.01) }
        #expect(!inner[0].intersects(inner[1]) && !inner[1].intersects(inner[2]))
        // Every row is in reach: a held piece floats above the finger, so filling the bottom row
        // puts the finger below the rug, and that has to be on screen.
        let lowest = layout.rug.maxY + BoxFortLayout.lift * layout.cell
        #expect(lowest <= size.height + 0.5, "the bottom row is out of reach at \(size)")
        return layout
    }

    @Test func iPhoneSEPortraitFits() {
        // iPhone SE (2nd and 3rd gen) 375 by 667, less the status bar and the host's top bar.
        let layout = check(CGSize(width: 375, height: 667 - 20 - 64))
        #expect(!layout.sideTray)
        #expect(layout.rug.width >= 300)
    }

    @Test func smallAndTallPhonesFit() {
        _ = check(CGSize(width: 320, height: 480))
        let big = check(CGSize(width: 440, height: 956 - 62 - 34 - 64))
        #expect(big.cell <= BoxFortLayout.maxCell)
    }

    @Test func iPadPortraitAndLandscape() {
        let portrait = check(CGSize(width: 820, height: 1180 - 24 - 64))
        #expect(!portrait.sideTray)
        let landscape = check(CGSize(width: 1180, height: 820 - 24 - 64))
        #expect(landscape.sideTray)
        #expect(landscape.slots.allSatisfy { $0.minX >= landscape.rug.maxX })
    }

    @Test func snapRoundsToNearestAndRefusesOffRug() {
        let layout = BoxFortLayout(size: CGSize(width: 400, height: 700))
        let c = layout.cell
        let rug = layout.rug.origin
        let sq2 = BoxFortCell(row: 2, col: 2)
        // A little off a cell rounds to it.
        let near = CGPoint(x: rug.x + 3 * c + 0.4 * c, y: rug.y + 5 * c - 0.4 * c)
        #expect(layout.snap(origin: near, size: sq2) == BoxFortCell(row: 5, col: 3))
        // Half a cell off the top or left still rounds onto the rug, more doesn't.
        #expect(layout.snap(origin: CGPoint(x: rug.x - 0.4 * c, y: rug.y - 0.4 * c), size: sq2) == BoxFortCell(row: 0, col: 0))
        #expect(layout.snap(origin: CGPoint(x: rug.x - 0.6 * c, y: rug.y), size: sq2) == nil)
        // Hanging off the bottom right.
        #expect(layout.snap(origin: CGPoint(x: rug.x + 6 * c, y: rug.y + 6 * c), size: sq2) == BoxFortCell(row: 6, col: 6))
        #expect(layout.snap(origin: CGPoint(x: rug.x + 6.6 * c, y: rug.y + 6 * c), size: sq2) == nil)
        #expect(layout.snap(origin: CGPoint(x: rug.x, y: rug.y + 6.6 * c), size: sq2) == nil)
    }

    @Test func theLiftedPieceSitsAboveTheFinger() {
        let layout = BoxFortLayout(size: CGSize(width: 375, height: 583))
        let finger = CGPoint(x: 180, y: 400)
        let size = BoxFortCell(row: 3, col: 1)
        let origin = layout.lifted(finger: finger, size: size)
        #expect(origin.y + 3 * layout.cell < finger.y)
        #expect(abs(origin.x + layout.cell / 2 - finger.x) < 0.01, "centered over the finger")
        // Snapping the lifted piece lands where it's drawn.
        if let cell = layout.snap(origin: origin, size: size) {
            let rect = layout.cellRect(row: cell.row, col: cell.col)
            #expect(abs(rect.minX - origin.x) <= layout.cell / 2 && abs(rect.minY - origin.y) <= layout.cell / 2)
        }
    }

    @Test func trayPiecesAreCenteredInTheirSlots() {
        let layout = BoxFortLayout(size: CGSize(width: 375, height: 583))
        let origin = layout.trayOrigin(slot: 1, size: BoxFortCell(row: 1, col: 4))
        let center = CGPoint(x: origin.x + 2 * layout.trayCell, y: origin.y + 0.5 * layout.trayCell)
        #expect(abs(center.x - layout.slots[1].midX) < 0.01 && abs(center.y - layout.slots[1].midY) < 0.01)
        #expect(layout.slot(at: CGPoint(x: layout.slots[2].midX, y: layout.slots[2].midY)) == 2)
        #expect(layout.slot(at: layout.rug.origin) == nil)
    }
}
