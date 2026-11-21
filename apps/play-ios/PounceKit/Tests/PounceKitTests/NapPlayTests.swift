import Testing
@testable import PounceKit

@Suite struct NapPlayTests {
    /// The 5 by 5 quilt from the vectors: cats at (0,1) (1,3) (2,0) (3,2) (4,4).
    let quilt = NapQuilt(n: 5, patches: [0, 0, 1, 1, 1, 0, 2, 2, 1, 1, 3, 2, 2, 2, 1, 3, 3, 2, 4, 4, 3, 3, 4, 4, 4])

    @Test func tapCyclesAndSendsEachStep() {
        var play = NapPlay(quilt: quilt)
        let r1 = play.tap(7)
        #expect(r1 == NapMove(cells: [7], to: .x))
        let r2 = play.tap(7)
        #expect(r2 == NapMove(cells: [7], to: .cat))
        #expect(play.state.cells[7] == NapState.cat)
        let r3 = play.tap(7)
        #expect(r3 == NapMove(cells: [7], to: .clear))
        #expect(play.state == .empty(quilt))
        let r4 = play.tap(25)
        #expect(r4 == nil)
        let r5 = play.tap(-1)
        #expect(r5 == nil)
    }

    @Test func dragPaintsAsItGoesAndSendsOnce() {
        var play = NapPlay(quilt: quilt)
        _ = play.tap(2)
        _ = play.tap(2) // a cat at 2
        let r6 = play.dragBegan(at: 0)
        #expect(r6)
        let r7 = play.dragMoved(to: 1)
        #expect(r7)
        let r8 = play.dragMoved(to: 1)
        #expect(!r8) // already crossed
        let r9 = play.dragMoved(to: 2)
        #expect(!r9) // a cat: not painted
        let r10 = play.dragMoved(to: 3)
        #expect(r10)
        let r11 = play.dragMoved(to: 99)
        #expect(!r11)
        #expect(play.shown.cells.prefix(4) == [1, 1, 2, 1])
        #expect(play.state.cells.prefix(4) == [0, 0, 2, 0]) // nothing sent yet
        let r12 = play.tap(4)
        #expect(r12 == nil) // no taps mid-drag
        let r13 = play.dragEnded()
        #expect(r13 == NapMove(cells: [0, 1, 3], to: .x))
        #expect(play.state.cells.prefix(4) == [1, 1, 2, 1])
        #expect(play.drag == nil)
        let r14 = play.dragEnded()
        #expect(r14 == nil)
    }

    @Test func dragFromNoCatClears() {
        var play = NapPlay(quilt: quilt)
        _ = play.tap(0)
        _ = play.tap(1)
        let r15 = play.dragBegan(at: 0)
        #expect(r15)
        play.dragMoved(to: 1)
        play.dragMoved(to: 2) // empty: untouched by a clear
        let r16 = play.dragEnded()
        #expect(r16 == NapMove(cells: [0, 1], to: .clear))
        #expect(play.state == .empty(quilt))
    }

    @Test func noDragFromACatOrOffTheQuilt() {
        var play = NapPlay(quilt: quilt)
        _ = play.tap(0)
        _ = play.tap(0)
        let r17 = play.dragBegan(at: 0)
        #expect(!r17)
        let r18 = play.dragBegan(at: 30)
        #expect(!r18)
        let r19 = play.dragMoved(to: 1)
        #expect(!r19)
        let r20 = play.dragEnded()
        #expect(r20 == nil)
    }

    @Test func aCancelledDragSendsNothing() {
        var play = NapPlay(quilt: quilt)
        play.dragBegan(at: 0)
        play.dragMoved(to: 1)
        play.dragCancelled()
        let r21 = play.dragEnded()
        #expect(r21 == nil)
        #expect(play.state == .empty(quilt))
        #expect(play.shown == .empty(quilt))
    }

    @Test func aStartOnlyDragOnACellEndsAsItsMark() {
        var play = NapPlay(quilt: quilt)
        play.dragBegan(at: 6)
        let r22 = play.dragEnded()
        #expect(r22 == NapMove(cells: [6], to: .x))
    }

    @Test func hintsLockAndLoadReplaces() {
        var play = NapPlay(quilt: quilt)
        _ = play.tap(0)
        _ = play.tap(0) // a wrong cat in row 0
        play.hint(1)
        #expect(play.state.hinted == [1])
        #expect(play.state.cells[0] == NapState.empty)
        let r23 = play.tap(1)
        #expect(r23 == nil)
        play.hint(40)
        #expect(play.state.hinted == [1])
        let server = NapState(cells: Array(repeating: 1, count: 25), hinted: [])
        play.dragBegan(at: 3)
        play.load(server)
        #expect(play.state == server && play.drag == nil)
        play.load(NapState(cells: [0], hinted: []))
        #expect(play.state == server)
    }

    @Test func equalityIncludesTheDrag() {
        var a = NapPlay(quilt: quilt)
        let b = NapPlay(quilt: quilt)
        #expect(a == b)
        a.dragBegan(at: 0)
        #expect(a != b)
    }
}
