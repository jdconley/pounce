import Observation
import PounceKit
import SwiftUI

/// A Cat Nap run on this phone: the board as the player marks it, and its rule checks. Marks show
/// at once; each change goes out through `send` (the run session, or a local stand-in), and the
/// rule checks run off the main actor (`CatNapRules.check`), a stale answer dropped.
@MainActor @Observable
final class CatNapModel {
    private(set) var play: NapPlay
    /// The rules' read of the board shown: clashes, whether every cat is in, progress.
    private(set) var check: NapCheck = .none
    /// False once the run has ended: the quilt shows, input does nothing.
    var playing = true

    @ObservationIgnored private let send: (NapMove) -> Void
    @ObservationIgnored private var checked: NapState?
    @ObservationIgnored private var pointer: Pointer?

    /// A finger on the quilt: where it went down, where it is, and whether it has turned into a
    /// drag (or can't, starting on a cat).
    private struct Pointer {
        let start: Int
        var last: CGPoint
        var mode: Mode
        enum Mode { case pending, dragging, inert }
    }

    init(quilt: NapQuilt, state: NapState? = nil, send: @escaping (NapMove) -> Void) {
        play = NapPlay(quilt: quilt, state: state)
        self.send = send
        recheck()
    }

    var quilt: NapQuilt { play.quilt }
    var shown: NapState { play.shown }

    // MARK: Input

    func tap(_ cell: Int) {
        guard playing, let move = play.tap(cell) else { return }
        feedback(for: move)
        commit(move)
    }

    /// A finger down or moving at `point` (quilt coordinates). It becomes a drag once it leaves
    /// its cell or travels a third of one.
    func pointer(at point: CGPoint, from start: CGPoint, geo: CatNapGeometry) {
        guard playing else { return }
        if pointer == nil {
            guard let cell = geo.cell(at: start) else { return }
            pointer = Pointer(start: cell, last: start, mode: .pending)
            Haptics.shared.prepare()
        }
        guard var p = pointer else { return }
        if p.mode == .pending {
            let far = hypot(point.x - start.x, point.y - start.y) > geo.unit / 3
            guard far || geo.cell(at: point) != p.start else { return }
            p.mode = play.dragBegan(at: p.start) ? .dragging : .inert
            if p.mode == .dragging { Haptics.shared.tick() }
        }
        if p.mode == .dragging {
            var changed = false
            for cell in geo.cells(from: p.last, to: point) where play.dragMoved(to: cell) { changed = true }
            if changed { Haptics.shared.tick() }
        }
        p.last = point
        pointer = p
    }

    func pointerEnded() {
        guard let p = pointer else { return }
        pointer = nil
        switch p.mode {
        case .pending: tap(p.start)
        case .dragging:
            if let move = play.dragEnded() { commit(move) }
        case .inert: break
        }
    }

    func pointerCancelled() {
        pointer = nil
        play.dragCancelled()
    }

    // MARK: From the server

    /// A hint's cat, from the server.
    func hint(_ cell: Int) {
        play.hint(cell)
        Haptics.shared.success()
        Sound.shared.play(ArtName.Sound.sfxSparkle, kind: .game)
        recheck()
    }

    /// The server's board (a resumed run): it replaces this one.
    func load(_ state: NapState) {
        pointer = nil
        play.load(state)
        recheck()
    }

    // MARK: -

    private func commit(_ move: NapMove) {
        send(move)
        recheck()
    }

    private func feedback(for move: NapMove) {
        switch move.to {
        case .cat:
            Haptics.shared.drop()
            Sound.shared.play(ArtName.Sound.sfxPop, kind: .game)
        case .x, .clear:
            Haptics.shared.tick()
        }
    }

    /// Checks the board off the main actor. Only cats change the answer, so "no cat" marks skip it.
    private func recheck() {
        let state = play.state
        guard checked?.cats != state.cats || checked?.hinted != state.hinted else { return }
        checked = state
        let quilt = play.quilt
        let before = check
        Task { [weak self] in
            let next = await CatNapRules.check(quilt, state)
            guard let self, self.play.state.cats == state.cats else { return }
            self.check = next
            if next.clashes.cells.count > before.clashes.cells.count {
                Haptics.shared.thump()
                Sound.shared.play(ArtName.Sound.sfxNope, kind: .game)
            } else if next.complete, !before.complete {
                Haptics.shared.celebrate()
                Sound.shared.play(ArtName.Sound.sfxFanfare, kind: .game)
            }
        }
    }
}

#if DEBUG
    extension CatNapModel {
        /// DEBUG `-autoplay`: the quilt marks itself, row by row, through the same input a finger
        /// runs: a drag paints a row "no cat", the next drag back clears it. Each drag is one move
        /// to the session. No UI test reads the screen meanwhile, so the frame gates measure the
        /// app's own work (`CatNapFrameTests`, docs/main-thread.md).
        func autoplay() async {
            let geo = CatNapGeometry(n: quilt.n, side: CGFloat(quilt.n) * 40)
            let frame = Duration.milliseconds(16)
            do {
                try await Task.sleep(for: .seconds(Autoplay.firstDragAfter))
                var row = 0
                while !Task.isCancelled, playing {
                    for back in [false, true] {
                        let y = (CGFloat(row) + 0.5) * geo.unit
                        let left = CGPoint(x: geo.unit / 2, y: y), right = CGPoint(x: geo.side - geo.unit / 2, y: y)
                        let (from, to) = back ? (right, left) : (left, right)
                        for step in 0...Autoplay.dragFrames {
                            let t = CGFloat(step) / CGFloat(Autoplay.dragFrames)
                            pointer(at: CGPoint(x: from.x + (to.x - from.x) * t, y: y), from: from, geo: geo)
                            try await Task.sleep(for: frame)
                        }
                        pointerEnded()
                        try await Task.sleep(for: frame * Autoplay.restFrames)
                    }
                    row = (row + 1) % quilt.n
                }
            } catch {}
        }
    }
#endif
