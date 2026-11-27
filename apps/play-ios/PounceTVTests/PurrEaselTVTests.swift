import PounceKit
import SwiftUI
import Testing
import UIKit
@testable import PounceTV

/// Purrtrait's easel on the TV: the lines the drawer's phone sends, drawn by the shared easel view
/// from the room's ink feed. A TV that comes back mid-turn gets the room's `inkSync` and shows the
/// same picture; a new turn wipes it.
@MainActor
@Suite("Purrtrait's easel on the TV")
struct PurrEaselTVTests {
    private static func store(_ room: RoomView) -> RoomStore {
        let store = RoomStore(code: DemoFixtures.code, socket: QuietSocket(), role: .screen)
        store.handle(.connected)
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 1, room: room)))
        return store
    }

    private static func easel(_ store: RoomStore) -> (PurrEaselView, PurrInkFollower) {
        let view = PurrEaselView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 500))
        window.addSubview(view)
        view.layoutIfNeeded()
        return (view, PurrInkFollower(feed: store.ink, view: view))
    }

    private static func line(_ id: Int, _ color: Int, from: InkPoint, to: InkPoint) -> InkOp {
        .stroke(id: id, color: color, width: 2, start: from, deltas: InkCodec.deltas(from: from, through: [to]))
    }

    /// Waits until the easel shows `count` strokes and its bitmap has caught up.
    private static func shown(_ view: PurrEaselView, count: Int) async {
        for _ in 0..<200 where view.drawing.strokes.count != count {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await view.settle()
    }

    private static func bytes(_ image: CGImage?) -> [UInt8]? {
        guard let image else { return nil }
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: data, count: image.width * image.height * 4))
    }

    /// Review focus 2: the TV relaunched mid-turn after an undo and a clear gets the same picture
    /// back from the room's `inkSync`.
    @Test func syncAfterUndoAndClear() async throws {
        let room = DemoFixtures.purrScreen(.draw)
        let turn = try #require(room.purrtrait?.turn)
        let live = Self.store(room)
        let (first, follower) = Self.easel(live)
        let ops: [InkOp] = [
            Self.line(0, 1, from: InkPoint(100, 100), to: InkPoint(600, 100)),
            Self.line(1, 5, from: InkPoint(100, 300), to: InkPoint(600, 300)),
            .undo(id: 1),
            .clear,
            Self.line(2, 4, from: InkPoint(100, 500), to: InkPoint(600, 800)),
            Self.line(3, 6, from: InkPoint(384, 100), to: InkPoint(384, 1000)),
            .extend(id: 3, deltas: [InkPoint(100, 0)]),
        ]
        for op in ops { live.handle(.message(.ink(seat: 0, turn: turn, ops: [op]))) }
        await Self.shown(first, count: 2)
        #expect(first.drawing.strokes.map(\.id) == [2, 3])

        // The TV comes back: a new store, a new easel, the room's drawing so far in one message.
        let back = Self.store(room)
        let (second, again) = Self.easel(back)
        back.handle(.message(.inkSync(turn: turn, ops: InkCodec.compact(ops))))
        await Self.shown(second, count: 2)
        #expect(second.drawing == first.drawing)
        #expect(second.liveID == 3)
        #expect(second.settlingCount == 0)
        let a = try #require(Self.bytes(first.bitmapImage))
        let b = try #require(Self.bytes(second.bitmapImage))
        #expect(a == b, "the bitmap of finished strokes differs")
        follower.stop()
        again.stop()
    }

    @Test func aNewTurnWipesTheEasel() async throws {
        var room = DemoFixtures.purrScreen(.draw)
        let turn = try #require(room.purrtrait?.turn)
        let store = Self.store(room)
        let (view, follower) = Self.easel(store)
        store.handle(.message(.ink(seat: 0, turn: turn, ops: [Self.line(0, 1, from: InkPoint(10, 10), to: InkPoint(700, 900))])))
        await Self.shown(view, count: 1)
        room.purrtrait?.turn = "1:9"
        room.purrtrait?.drawer = 1
        store.handle(.message(.snapshot(protocol: PounceKit.protocolVersion, seq: 2, room: room)))
        await Self.shown(view, count: 0)
        #expect(view.drawing.isEmpty)
        follower.stop()
    }

    @Test func aFinishedStrokeSettlesIntoTheBitmap() async throws {
        let room = DemoFixtures.purrScreen(.draw)
        let turn = try #require(room.purrtrait?.turn)
        let store = Self.store(room)
        let (view, follower) = Self.easel(store)
        store.handle(.message(.ink(seat: 0, turn: turn, ops: [Self.line(0, 1, from: InkPoint(10, 10), to: InkPoint(700, 900))])))
        store.handle(.message(.ink(seat: 0, turn: turn, ops: [Self.line(1, 2, from: InkPoint(10, 900), to: InkPoint(700, 10))])))
        await Self.shown(view, count: 2)
        #expect(view.liveID == 1)
        #expect(view.settlingCount == 0)
        #expect(view.bitmapImage != nil)
        follower.stop()
    }

    /// The TV never has the word: its room has none, so nothing on screen can show it.
    @Test func theTVsRoomHasNoWord() {
        for demo in [DemoFixtures.PurrDemo.pick, .draw, .curtain] {
            let room = DemoFixtures.purrScreen(demo)
            #expect(room.purrtrait?.word == nil)
            #expect(room.purrtrait?.choices == nil)
            #expect(room.near != nil)
        }
    }
}
