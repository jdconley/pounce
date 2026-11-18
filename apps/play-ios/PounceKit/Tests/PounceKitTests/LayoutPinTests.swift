import CoreGraphics
import Foundation
import Testing
@testable import PounceKit

/// Pins every iPhone and iPad arrangement of both games, byte for byte: every stored value of a
/// sample of layouts (private ones too) and what their methods place, against
/// `Fixtures/layout/pin.txt`, recorded before the TV arrangement was added. A change to a phone or
/// iPad table shows up here as a diff of that file. To record it again on purpose, run the suite
/// with `POUNCE_RECORD_LAYOUT_PIN=1` and review the file's diff.
@Suite("Layout, pinned")
struct LayoutPinTests {
    /// iPhone SE, iPhone 17 Pro, iPhone 17 Pro Max (and sideways), iPad portrait and landscape, a
    /// 13-inch iPad portrait and landscape.
    static let screens: [(size: CGSize, top: CGFloat, bottom: CGFloat)] = [
        (CGSize(width: 375, height: 667), 20, 0), (CGSize(width: 402, height: 874), 62, 34),
        (CGSize(width: 440, height: 956), 62, 34), (CGSize(width: 956, height: 440), 0, 21),
        (CGSize(width: 820, height: 1180), 24, 20), (CGSize(width: 1180, height: 820), 24, 20),
        (CGSize(width: 1024, height: 1366), 24, 20), (CGSize(width: 1366, height: 1024), 24, 20),
    ]

    static func dump() -> String {
        var out = ""
        let tall = ControllerChrome(switchBand: 64, status: 56, actions: 96)
        for s in screens {
            let tag = "\(Int(s.size.width))x\(Int(s.size.height))"
            for opponents in [1, 3, 5] {
                let l = TableLayout(size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: opponents)
                out += table(l, "table \(tag) opponents \(opponents)")
            }
            for chrome in [ControllerChrome.standard, tall] {
                for hand in [ControllerHand.full, ControllerHand(short: true, trays: false)] {
                    let l = TableLayout(size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: 3, controller: chrome, hand: hand)
                    out += table(l, "controller \(tag) \(chrome.switchBand) short \(hand.short) trays \(hand.trays)")
                }
            }
            for (opponents, rack, meter, controls) in [(1, 14, true, true), (3, 30, false, true), (3, 14, false, false)] {
                let l = TilesLayout(
                    size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: opponents, rackCount: rack,
                    meter: meter, controls: controls)
                out += tiles(l, "tiles \(tag) opponents \(opponents) rack \(rack) meter \(meter) controls \(controls)")
            }
            for controller in [TilesLayout.Controller.rackOnly(.standard), .rackOnly(tall), .fullTable(.standard)] {
                for rack in [14, 40] {
                    let l = TilesLayout(
                        size: s.size, safeTop: s.top, safeBottom: s.bottom, opponents: 3, rackCount: rack,
                        controller: controller)
                    out += tiles(l, "tiles controller \(tag) \(controller) rack \(rack)")
                }
            }
        }
        return out
    }

    private static func table(_ l: TableLayout, _ name: String) -> String {
        var out = "== \(name)\n" + stored(l)
        out += "hand11 \(l.hand(count: 11, lifted: 3).map { "\(f($0.position)) \(f($0.rotation)) \(f($0.z))" })\n"
        out += "gap \(l.hand(count: 6, gap: 2).map { f($0.position) })\n"
        out += "slot \(l.handSlot(x: l.size.width * 0.3, count: 8, current: 2))\n"
        out += "trays \(l.trayFrames(count: 3).map(f))\n"
        out += "rows \((0..<6).map { l.laidRow(slot: $0, of: 6) }.map(f)) \((0..<3).map { l.laidRow(slot: $0, of: 3) }.map(f))\n"
        out += "shelves \((0..<10).map { f(l.shelf($0)) })\n"
        out += "cats \(l.opponentSlots.indices.map { f(l.opponentFrame($0)) }) \(f(l.opponentDiameter)) \(f(l.opponentSpacing))\n"
        out += "frames \(f(l.menuButtonFrame)) \(f(l.sortButtonFrame)) \(f(l.seatTagFrame)) \(l.roomy) \(l.fits) \(l.controllerSideBySide)\n"
        out += "fanRight \(f(l.controllerFanRight(cards: 11)))\n"
        return out
    }

    private static func tiles(_ l: TilesLayout, _ name: String) -> String {
        var out = "== \(name)\n" + stored(l)
        let slots = l.rackSlots(count: 20)
        out += "rack \(slots.centers.map(f)) \(f(slots.contentWidth)) \(f(l.rackScrollLimit(count: 40)))\n"
        out += "rackSlot \(l.rackSlot(at: CGPoint(x: l.size.width / 2, y: l.rack.midY), count: 20)) \(l.roomy)\n"
        return out
    }

    /// Every stored property, private ones too, by name.
    private static func stored(_ value: Any) -> String {
        Mirror(reflecting: value).children.map { "\($0.label ?? "?") \(describe($0.value))\n" }.joined()
    }

    private static func describe(_ v: Any) -> String {
        switch v {
        case let x as CGFloat: f(x)
        case let x as CGPoint: f(x)
        case let x as CGSize: "(\(f(x.width)), \(f(x.height)))"
        case let x as CGRect: f(x)
        case let x as [CGPoint]: "\(x.map(f))"
        default: "\(v)"
        }
    }

    private static func f(_ x: CGFloat) -> String { String(format: "%.4f", Double(x)) }
    private static func f(_ p: CGPoint) -> String { "(\(f(p.x)), \(f(p.y)))" }
    private static func f(_ r: CGRect) -> String { "(\(f(r.minX)), \(f(r.minY)), \(f(r.width)), \(f(r.height)))" }

    @Test func everyPhoneAndIPadArrangementIsUnchanged() throws {
        let url = Fixtures.localURL("layout/pin.txt")
        let now = Self.dump()
        if ProcessInfo.processInfo.environment["POUNCE_RECORD_LAYOUT_PIN"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try now.write(to: url, atomically: true, encoding: .utf8)
        }
        let pinned = try String(contentsOf: url, encoding: .utf8)
        let a = pinned.split(separator: "\n", omittingEmptySubsequences: false)
        let b = now.split(separator: "\n", omittingEmptySubsequences: false)
        let first = zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        #expect(a.count == b.count, "the pin has \(a.count) lines, the layouts \(b.count)")
        if let first {
            Issue.record("line \(first + 1) changed:\n  was \(a[first])\n  now \(b[first])")
        }
    }
}
