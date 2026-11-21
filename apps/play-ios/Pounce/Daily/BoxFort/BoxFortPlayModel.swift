import Observation
import PounceKit
import SwiftUI

/// A placement the play view sends to the run (phase B: the host's `DailyRunSession`).
struct BoxFortMove: Equatable, Sendable {
    let slot: Int
    let row: Int
    let col: Int
}

/// The boxes one placement cleared, for the burst: each spot and the paint it had.
struct BoxFortBurst: Equatable, Sendable {
    let id: Int
    let boxes: [Int: Int]
    let lines: Int
}

/// A piece on its way onto the rug.
struct BoxFortLanding: Equatable, Sendable {
    let slot: Int
    let piece: BoxFortPiece
    let at: BoxFortCell
}

/// Points a placement earned, floated up from where it landed.
struct BoxFortGain: Equatable, Sendable {
    let id: Int
    let points: Int
    /// The middle of the placed piece, in rug spots.
    let at: CGPoint
    let combo: Int
}

/// Box Fort's play state on the phone. It shows each placement at once with the client rules
/// (they match the server's on every golden vector), sends it to the run, and waits for the
/// server to deal the next set. Everything that searches the rug runs off the main actor.
@MainActor
@Observable
final class BoxFortPlayModel {
    private(set) var state: BoxFortState
    /// Which tray pieces fit anywhere; a stuck one dims.
    private(set) var fits: [Bool] = [true, true, true]
    /// The set is placed and the next one is on its way from the server.
    private(set) var waiting = false
    private(set) var burst: BoxFortBurst?
    private(set) var gain: BoxFortGain?
    /// A piece let go on a good spot, drawn there until the rules have taken it (a frame or two).
    private(set) var landing: BoxFortLanding?
    /// Bumped when a new set lands in the tray, so it can bounce in.
    private(set) var dealt = 0

    @ObservationIgnored private let send: (BoxFortMove) -> Void
    @ObservationIgnored private var counter = 0

    init(state: BoxFortState, send: @escaping (BoxFortMove) -> Void) {
        self.state = state
        self.send = send
        refreshFits()
    }

    var over: Bool { state.over != nil }

    /// Puts the tray's piece in `slot` on the rug at `at`. False when it can't go there (the
    /// view sends it back to the tray).
    @discardableResult
    func place(slot: Int, at: BoxFortCell) async -> Bool {
        guard !waiting, state.over == nil, state.pieces.indices.contains(slot), !state.placed[slot] else { return false }
        let before = state
        let piece = before.pieces[slot]
        landing = BoxFortLanding(slot: slot, piece: piece, at: at)
        let out = await BoxFortRules.stepOffMain(before, slot: slot, row: at.row, col: at.col)
        landing = nil
        guard state == before, let out else { return false }
        send(BoxFortMove(slot: slot, row: at.row, col: at.col))
        counter += 1
        state = out.state
        let size = piece.size
        gain = BoxFortGain(
            id: counter, points: out.gained,
            at: CGPoint(x: CGFloat(at.col) + CGFloat(size.col) / 2, y: CGFloat(at.row) + CGFloat(size.row) / 2),
            combo: out.state.combo)
        if out.cleared.count > 0 {
            var boxes: [Int: Int] = [:]
            // The rug as it was the moment the piece landed, before the lines went.
            var landed = before.rug
            for c in piece.cells { landed[(at.row + c.row) * 8 + at.col + c.col] = piece.tint }
            for row in out.cleared.rows { for col in 0..<8 { boxes[row * 8 + col] = landed[row * 8 + col] } }
            for col in out.cleared.cols { for row in 0..<8 { boxes[row * 8 + col] = landed[row * 8 + col] } }
            burst = BoxFortBurst(id: counter, boxes: boxes, lines: out.cleared.count)
        }
        if out.setDone {
            if state.set + 1 == state.sets {
                state = BoxFortRules.deal(state, next: nil)  // the full fort: no search
            } else {
                waiting = true
            }
        }
        refreshFits()
        return true
    }

    /// The server dealt the next set.
    func receive(_ reveal: BoxFortReveal) async {
        guard waiting, reveal.set == state.set + 1 else { return }
        let before = state
        let next = await BoxFortRules.dealOffMain(before, next: reveal.pieces)
        guard state == before else { return }
        state = next
        waiting = false
        dealt += 1
        refreshFits()
    }

    /// The server's own state (a resume, or a correction): it wins.
    func resync(_ server: BoxFortState) {
        state = server
        waiting = false
        landing = nil
        refreshFits()
    }

    private func refreshFits() {
        let now = state
        Task { [weak self] in
            let fits = await BoxFortRules.fitsBySlotOffMain(now)
            guard let self, self.state == now else { return }
            self.fits = fits
        }
    }
}

/// The finger during a drag. Only the lifted piece reads `finger`, so a move redraws nothing
/// else; `spot` changes only when the snapped spot does.
@MainActor
@Observable
final class BoxFortDrag {
    private(set) var slot: Int?
    private(set) var finger: CGPoint = .zero
    /// Where the piece would land, and the lines that landing would clear.
    private(set) var spot: BoxFortCell?
    private(set) var clears: BoxFortCleared = .none

    func begin(slot: Int, at finger: CGPoint) {
        self.slot = slot
        self.finger = finger
    }

    func move(to finger: CGPoint) { self.finger = finger }

    func aim(_ spot: BoxFortCell?, clears: BoxFortCleared) {
        if self.spot != spot { self.spot = spot }
        if self.clears != clears { self.clears = clears }
    }

    func end() {
        slot = nil
        spot = nil
        clears = .none
    }
}
