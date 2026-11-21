#if DEBUG
    import PounceKit
    import SwiftUI

    /// The server's test game (`DAILY_TEST=on`, docs/daily-protocol.md): count to 3 + level. A
    /// move is `{ k: "step", n }` with the next number; a hint takes one step. Debug builds show it
    /// on the Dish under `-daily-test`, so the host plays end to end against a local server.
    enum DailyTestGame {
        static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-daily-test") }

        struct Puzzle: Codable, Sendable { let target: Int }
        struct State: Codable, Sendable { let n: Int }
        struct Step: Codable, Sendable {
            var k = "step"
            let n: Int
        }
    }

    struct DailyTestGameView: DailyGameView {
        nonisolated static let game = DailyCatalog.test

        let session: DailyRunSession
        let target: Int
        @SwiftUI.State private var n: Int
        @SwiftUI.State private var asking = false

        init(session: DailyRunSession, puzzle: DailyTestGame.Puzzle, state: DailyTestGame.State) {
            self.session = session
            target = puzzle.target
            _n = SwiftUI.State(initialValue: state.n)
        }

        var body: some View {
            VStack(spacing: 28) {
                Text("\(n) of \(target)")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("daily-test-count")
                HStack(spacing: 16) {
                    PillButton(icon: nil, color: Palette.orange, size: .medium, title: "Step", accessibilityLabel: "Step") { step() }
                        .disabled(n >= target)
                        .accessibilityIdentifier("daily-test-step")
                    PillButton(icon: nil, color: Palette.sky, size: .medium, title: "Hint", accessibilityLabel: "Hint") {
                        Task { await hint() }
                    }
                    .disabled(asking || n >= target)
                    .accessibilityIdentifier("daily-test-hint")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                for await event in await session.events(reveal: DailyTestGame.State.self, state: DailyTestGame.State.self) {
                    if case .resync(let state, _, _) = event { n = state.n }
                }
            }
        }

        private func step() {
            n += 1
            let move = DailyTestGame.Step(n: n)
            let last = n == target
            Task { await session.send(move: move, urgent: last) }
        }

        private func hint() async {
            asking = true
            if let reveal = await session.hint(as: DailyTestGame.State.self) { n = max(n, reveal.n) }
            asking = false
        }
    }
#endif
