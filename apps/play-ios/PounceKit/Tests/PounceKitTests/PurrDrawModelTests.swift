import Foundation
import Testing
@testable import PounceKit

@MainActor @Suite struct PurrDrawModelTests {
    final class Wire {
        var sent: [[InkOp]] = []
        var lasts: [Bool] = []
        var failing = false
        var failures: [@MainActor () -> Void] = []
    }

    private func model(_ wire: Wire, settle: Duration = .zero, now: @escaping () -> Duration) -> PurrDrawModel {
        PurrDrawModel(seat: 2, turn: "1:3", clock: now, settle: settle) { ops, last, failed in
            if wire.failing {
                wire.failures.append(failed)
            } else {
                wire.sent.append(ops)
                wire.lasts.append(last)
            }
        }
    }

    /// The tap that picked the word lands on the easel as it comes up (a double tap): no stroke,
    /// no ink, an empty easel. A finger after the settle draws as usual.
    @Test func thePickingTapNeverDraws() {
        let wire = Wire()
        var now = Duration.seconds(5)
        let m = model(wire, settle: PurrDrawModel.settle) { now }
        now += .milliseconds(150)
        #expect(!m.down(InkPoint(384, 300)))
        m.move([InkPoint(390, 300)])
        m.up()
        m.tick()
        #expect(wire.sent.isEmpty)
        #expect(m.drawing.strokes.isEmpty)
        #expect(m.strokes == 0 && m.visible == 0 && !m.canUndo)
        now += PurrDrawModel.settle
        #expect(m.down(InkPoint(384, 300)))
        m.up()
        #expect(m.drawing.strokes.count == 1)
        #expect(!wire.sent.isEmpty)
    }

    @Test func batchesGoEveryFiftyMilliseconds() {
        let wire = Wire()
        var now = Duration.zero
        let m = model(wire) { now }
        m.down(InkPoint(10, 10))
        #expect(wire.sent.count == 1)  // the stroke's start goes at once
        for _ in 0..<12 {
            now += .milliseconds(8)  // a 120 Hz frame
            m.move([InkPoint(10 + Int(now / .milliseconds(1)), 10)])
            m.tick()
        }
        // 96 ms of drawing: one more batch at 50 ms, the rest waits for 100.
        #expect(wire.sent.count == 2)
        m.up()
        #expect(wire.sent.count == 3)
        #expect(!m.needsTicks)
    }

    @Test func atMostTwentyFiveASecond() {
        let wire = Wire()
        var now = Duration.zero
        let m = model(wire) { now }
        for i in 0..<60 {
            now += .milliseconds(10)
            m.down(InkPoint(i * 10, 500))
            m.up()
        }
        #expect(wire.sent.count == 25)
        #expect(m.needsTicks)
        now += .seconds(1)
        m.tick()
        #expect(wire.sent.count == 26)
        #expect(InkDrawing(ops: wire.sent.flatMap { $0 }).strokes.count == 60)
    }

    @Test func resendReplaysWithALeadingClear() {
        let wire = Wire()
        var now = Duration.zero
        let m = model(wire) { now }
        m.down(InkPoint(10, 10))
        m.move([InkPoint(200, 10)])
        m.up()
        now += .seconds(1)
        m.down(InkPoint(10, 300))
        m.up()
        wire.sent = []
        wire.lasts = []
        m.resend()
        #expect(wire.sent.first?.first == .clear)
        // One message: it is the first and the last.
        #expect(wire.lasts == [true])
        let picture = InkDrawing(ops: wire.sent.flatMap { $0 })
        #expect(picture.strokes.count == 2)
        #expect(picture.strokes.map(\.id) == [0, 1])
    }

    /// Review focus 5: the app going to the background mid-stroke ends the stroke, and its last
    /// points go before the socket closes.
    @Test func backgroundEndsStroke() {
        let wire = Wire()
        var now = Duration.zero
        let m = model(wire) { now }
        m.down(InkPoint(100, 100))
        now += .milliseconds(10)
        m.move([InkPoint(150, 150)])
        #expect(m.pen.isDrawing)
        m.background()
        #expect(!m.pen.isDrawing)
        let tv = InkDrawing(ops: wire.sent.flatMap { $0 })
        #expect(tv.strokes.first?.points.last == InkPoint(150, 150))
        // On return, a room's copy isn't taken over this device's own.
        #expect(!m.adopt([.stroke(id: 0, color: 0, width: 1, start: InkPoint(1, 1), deltas: [])]))
    }

    @Test func messagesThatNeverLeftGoAfterTheReconnect() {
        let wire = Wire()
        var now = Duration.zero
        let m = model(wire) { now }
        wire.failing = true
        m.down(InkPoint(10, 10))
        m.up()
        for f in wire.failures { f() }
        wire.failing = false
        #expect(wire.sent.isEmpty)
        m.reconnected()
        #expect(wire.sent == [[.stroke(id: 0, color: 0, width: 1, start: InkPoint(10, 10), deltas: [])]])
        now += .seconds(1)
    }

    @Test func aFullEaselTakesNoStrokesUntilCleared() {
        let wire = Wire()
        var now = Duration.zero
        let m = model(wire) { now }
        m.down(InkPoint(10, 10))
        m.up()
        // A stroke held back by the rate limit when the refusal comes: it never goes.
        for i in 0..<30 {
            m.down(InkPoint(20 + i, 20))
            m.up()
        }
        m.easelFull()
        #expect(!m.needsTicks)
        now += .seconds(2)
        #expect(m.full)
        #expect(!m.down(InkPoint(20, 20)))
        wire.sent = []
        #expect(m.clear())
        #expect(!m.full)
        // Clear goes on its own (the server refuses a batch past the caps whole).
        #expect(wire.sent == [[.clear]])
        #expect(m.down(InkPoint(20, 20)))
    }

    @Test func undoAndClearLightUpWithInk() {
        let m = model(Wire()) { .zero }
        #expect(!m.canUndo)
        m.down(InkPoint(10, 10))
        #expect(m.canUndo)
        #expect(m.canClear)
        m.up()
        m.undo()
        #expect(!m.canUndo)
        #expect(m.strokes == 1)
    }
}
