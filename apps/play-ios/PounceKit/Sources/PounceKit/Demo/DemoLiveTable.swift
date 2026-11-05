#if DEBUG
import Foundation

extension DemoFixtures {
    /// The demo live table (spec §11.3) for previews, screenshots and `-demo-live-table`: JD, Mia
    /// and the House Cat at Couch Cats, with JD and Mia's 12-day streak. `mine`: JD's move (the
    /// bell); otherwise Mia's. `seats` up to 6, for the widest rug strip.
    public static func liveTable(mine: Bool, seats: Int = 3, paws: Bool = true) -> (code: String, state: LiveTableState) {
        let all: [LiveTableState.Seat] = [
            .init(cat: 1, phase: 3, name: "JD", bot: false, me: true),
            .init(cat: 2, phase: 4, name: "Mia", bot: false, me: false),
            .init(cat: 3, phase: 2, name: nil, bot: true, me: false),
            .init(cat: 6, phase: 5, name: "Kiki", bot: false, me: false),
            .init(cat: 4, phase: 1, name: "Biscuit", bot: false, me: false),
            .init(cat: 7, phase: 7, name: "Pickle", bot: false, me: false),
        ]
        let state = LiveTableState(
            table: "Couch Cats", seats: Array(all.prefix(max(2, min(seats, all.count)))), turn: mine ? 0 : 1, mine: mine,
            streak: paws ? .init(count: 12, me: false, them: true) : nil)
        return ("GH2VD", state)
    }
}
#endif
