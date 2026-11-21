import PounceKit
import SwiftUI

/// Sniff as a TV watches it (spec §8, `DailyWatchGames.swift`): a watch frame's public state, the
/// guesses with their letters, read-only. The TV builds this folder only (`Sniff/TV/`).
struct SniffWatch: DailyWatchView {
    nonisolated static let game = DailyCatalog.sniff

    let state: SniffView

    init(puzzle: SniffPublic, state: SniffView) {
        self.state = state
    }

    var body: some View {
        SniffWatchView(board: state.board)
    }
}

/// The run's trails, filling the space the TV gives them; no draft row, no keyboard.
struct SniffWatchView: View {
    let board: SniffBoard

    var body: some View {
        GeometryReader { geo in
            let showsAnswer = board.answer != nil && !board.isSolved
            let tag = SniffTrail.tagWidth(
                fitting: CGSize(width: geo.size.width * 0.9, height: geo.size.height * 0.92),
                rows: SniffBoard.tries + (showsAnswer ? 1 : 0), cap: 150)
            SniffTrail(board: board, tagWidth: tag)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sniff.watch")
    }
}
