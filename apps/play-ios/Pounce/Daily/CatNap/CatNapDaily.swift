import PounceKit
import SwiftUI

/// Cat Nap in the Daily Dish: the quilt, played through the run session (`DailyGameHost.swift`).
/// Marks show at once and go to the session in the order they were made; a hint's cat and the
/// server's resyncs come back on its events. The host draws the rest (the top bar, the clock,
/// give up, the end).
struct CatNapDaily: DailyGameView {
    nonisolated static let game = DailyCatalog.catNap

    let session: DailyRunSession
    @SwiftUI.State private var model: CatNapModel
    @SwiftUI.State private var asking = false
    /// Moves on their way to the session, one at a time and in order (a task per move could
    /// reach the session out of order).
    private let moves: AsyncStream<NapMove>

    init(session: DailyRunSession, puzzle: NapQuilt, state: NapState) {
        self.session = session
        let (moves, sink) = AsyncStream<NapMove>.makeStream()
        self.moves = moves
        _model = SwiftUI.State(initialValue: CatNapModel(quilt: puzzle, state: state) { sink.yield($0) })
    }

    var body: some View {
        CatNapPlayView(model: model, controlsHeight: PillSize.small.height) {
            PillButton(icon: nil, color: Palette.magenta, size: .small, width: 150, title: "Hint +30s", accessibilityLabel: "Hint, adds 30 seconds") {
                Task { await hint() }
            }
            .disabled(asking || !model.playing || model.check.complete)
            .accessibilityIdentifier("catnap.hint")
        }
        .task {
            for await move in moves { await session.send(move: move) }
        }
        .task {
            for await event in await session.events(reveal: NapReveal.self, state: NapState.self) {
                switch event {
                case .hinted(let reveal?, _): model.hint(reveal.cell)
                case .resync(let state, _, _): model.load(state)
                case .ended: model.playing = false
                case .hinted(nil, _), .accepted, .link: break
                }
            }
        }
        #if DEBUG
            .task { if Autoplay.enabled { await model.autoplay() } }
        #endif
    }

    private func hint() async {
        guard !asking else { return }
        asking = true
        _ = await session.hint(as: NapReveal.self)
        asking = false
    }
}
