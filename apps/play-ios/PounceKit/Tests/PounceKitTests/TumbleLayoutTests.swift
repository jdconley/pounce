import CoreGraphics
import Testing
@testable import PounceKit

/// Toy Tumble fits every screen AGENTS.md lists (iOS plan, Task 4; Review Focus 3): iPhone SE, a
/// large iPhone, iPad portrait and landscape, at 2 and 6 players and the largest text size.
@Suite struct TumbleLayoutTests {
    struct Screen: CustomStringConvertible, Sendable {
        var name: String
        var size: CGSize
        var top: CGFloat
        var bottom: CGFloat
        var phone: Bool
        var description: String { name }
    }

    static let screens = [
        Screen(name: "SE", size: CGSize(width: 375, height: 667), top: 20, bottom: 0, phone: true),
        Screen(name: "Pro Max", size: CGSize(width: 440, height: 956), top: 62, bottom: 34, phone: true),
        Screen(name: "iPad portrait", size: CGSize(width: 1024, height: 1366), top: 24, bottom: 20, phone: false),
        Screen(name: "iPad landscape", size: CGSize(width: 1366, height: 1024), top: 24, bottom: 20, phone: false),
    ]

    static let cases: [(Screen, Int, CGFloat, Bool)] = screens.flatMap { s in
        [1, 5].flatMap { others in [1.0, 1.4].flatMap { text in [false, true].map { (s, others, CGFloat(text), $0) } } }
    }

    private func overlaps(_ rects: [CGRect]) -> (Int, Int)? {
        for i in rects.indices { for j in rects.indices where j > i && rects[i].insetBy(dx: 0.5, dy: 0.5).intersects(rects[j]) { return (i, j) } }
        return nil
    }

    @Test(arguments: cases) func everythingFits(_ c: (Screen, Int, CGFloat, Bool)) {
        let (s, others, text, chips) = c
        let l = TumbleLayout(size: s.size, safeTop: s.top, safeBottom: s.bottom, others: others, chips: chips, textScale: text)
        let label = "\(s.name) others=\(others) text=\(text) chips=\(chips)"
        if s.phone { #expect(l.cell >= 20, "\(label): cell \(l.cell)") }
        #expect(l.box.width == l.cell * 12)
        #expect(l.box.height == l.cell * 18)
        #expect(l.minis.count == others, "\(label)")
        if !chips { #expect(l.miniCell >= 2.5, "\(label): mini cell \(l.miniCell)") }
        let menu = CGRect(x: l.menuButton.x - 22, y: l.menuButton.y - 22, width: 44, height: 44)
        let all = [l.box, l.meter, l.tray] + l.minis
        #expect(overlaps(all) == nil, "\(label): \(String(describing: overlaps(all)))")
        for r in all + [menu] + l.slots {
            #expect(l.safe.insetBy(dx: -0.5, dy: -0.5).contains(r), "\(label): \(r) outside \(l.safe)")
        }
        for r in [l.box, l.meter] + l.minis { #expect(!r.intersects(l.rim), "\(label): \(r) under the rim") }
        #expect(overlaps(l.slots) == nil)
        #expect(l.slots.count == 6)
        #expect(l.slots.allSatisfy { $0.width >= 36 }, "\(label): trick slots")
    }

    @Test func theBoxLeansLeftOnAPhoneAndSitsBetweenTheMinisOnAnIPadInLandscape() {
        let phone = TumbleLayout(size: CGSize(width: 390, height: 844), safeTop: 47, safeBottom: 34, others: 3)
        #expect(phone.box.minX < phone.minis[0].minX)
        let pad = TumbleLayout(size: CGSize(width: 1366, height: 1024), safeTop: 24, safeBottom: 20, others: 4)
        #expect(pad.minis.contains { $0.maxX < pad.box.minX })
        #expect(pad.minis.contains { $0.minX > pad.meter.maxX })
    }

    /// A tall phone: the box sits on the tray (thumb reach), and the rim comes down with it.
    @Test func aTallPhonesBoxSitsOnTheTray() {
        let l = TumbleLayout(size: CGSize(width: 440, height: 956), safeTop: 62, safeBottom: 34, others: 3)
        #expect(l.box.minY - l.tray.maxY <= 7)
        #expect(l.rim.minY - l.box.maxY <= l.cell + 7)
        #expect(l.minis.allSatisfy { $0.maxY <= l.rim.minY })
    }

    @Test func theTVPutsUpToSixBoxesInOneRowAndTwoAreBigger() {
        let six = TumbleLayout(size: CGSize(width: 1920, height: 1080), safeTop: 0, safeBottom: 0, others: 6, mode: .tv)
        #expect(six.minis.count == 6)
        #expect(Set(six.minis.map(\.minY)).count == 1)
        #expect(overlaps(six.minis) == nil)
        #expect(six.minis.allSatisfy { six.safe.contains($0) })
        let two = TumbleLayout(size: CGSize(width: 1920, height: 1080), safeTop: 0, safeBottom: 0, others: 2, mode: .tv)
        #expect(two.miniCell > six.miniCell)
    }

    @Test func watchingShowsEveryBoxBig() {
        let l = TumbleLayout(size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0, others: 6, mode: .watching)
        #expect(l.minis.count == 6)
        #expect(overlaps(l.minis) == nil)
        #expect(l.miniCell >= 5)
    }

    @Test func theColoursNeverEchoTheClassicGame() {
        #expect(TumbleLook.suit(.i4) != .fish)  // never cyan
        #expect(TumbleLook.suit(.o4) != .bell)  // never yellow
        #expect(TumbleLook.suit(.t4) != .mouse)  // never purple
        #expect(TumbleLook.suit(.l4) != .feather)  // never orange
        #expect(Set(TumbleToy.allCases.map(TumbleLook.suit)).count == 4)
        #expect(TumbleLook.suit(cell: Tumble.junk) == nil)
        #expect(TumbleLook.suit(cell: 0) == nil)
    }

    @Test func cellsAndColumns() {
        let r = CGRect(x: 10, y: 20, width: 240, height: 360)
        #expect(TumbleLayout.cellRect(0, 0, in: r) == CGRect(x: 10, y: 20, width: 20, height: 20))
        #expect(TumbleLayout.cellRect(11, 17, in: r).maxY == 380)
        #expect(TumbleLayout.column(at: 5, in: r) == 0)
        #expect(TumbleLayout.column(at: 125, in: r) == 5)
        #expect(TumbleLayout.column(at: 900, in: r) == 11)
    }
}
