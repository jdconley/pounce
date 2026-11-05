#if DEBUG
import PounceKit
import SwiftUI
import WidgetKit

/// Every family and state from the demo fixtures (spec §16: previews for every family, state
/// and rendering mode; switch the mode in the canvas).
enum PreviewEntries {
    static let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
    static let evening = Calendar.current.date(bySettingHour: 20, minute: 30, second: 0, of: .now) ?? .now

    static func entry(_ change: (inout StreakView) -> Void = { _ in }, at date: Date = noon) -> UsEntry {
        let snapshot = DemoFixtures.widgetSnapshot(change, now: noon)
        return UsEntry(date: date, state: .make(snapshot, pair: nil, at: date))
    }

    static var all: [UsEntry] {
        [
            entry(),  // Mia: my half done, their move, a gift on the condo
            entry { $0.kept = true; $0.them = true },
            entry { $0.me = false; $0.them = true; $0.myMove = ["M3W7Z"]; $0.theirMove = [] },
            entry { $0.me = false; $0.them = false; $0.pausedUntil = "2999-01-01" },
            entry { $0.me = false; $0.winback = .init(kept: 1) },
            entry({ $0.me = false }, at: evening),
            entry { $0.pounce = PounceState(sent: true, quiet: true) },
            entry { $0.pounce = PounceState(resting: true) },
            entry { $0.pounce = PounceState(answer: .play) },
            UsEntry(date: noon, state: .empty(me: .init(name: "JD", cat: 4))),
        ]
    }
}

#Preview("Small", as: .systemSmall) {
    UsWidget()
} timeline: {
    for entry in PreviewEntries.all { entry }
}

#Preview("Medium", as: .systemMedium) {
    UsWidget()
} timeline: {
    for entry in PreviewEntries.all { entry }
}

#Preview("Circular", as: .accessoryCircular) {
    StreakWidget()
} timeline: {
    for entry in PreviewEntries.all { entry }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    StreakWidget()
} timeline: {
    for entry in PreviewEntries.all { entry }
}

#Preview("Inline", as: .accessoryInline) {
    StreakWidget()
} timeline: {
    for entry in PreviewEntries.all { entry }
}

/// The live table (spec §11.3): my move, their move, no paws yet, and six seats.
enum LivePreviews {
    static let attributes = LiveTableAttributes(code: DemoFixtures.liveTable(mine: true).code)
    static let states: [LiveTableState] = [
        DemoFixtures.liveTable(mine: true).state,
        DemoFixtures.liveTable(mine: false).state,
        DemoFixtures.liveTable(mine: false, seats: 2, paws: false).state,
        DemoFixtures.liveTable(mine: true, seats: 6).state,
    ]
}

#Preview("Live table", as: .content, using: LivePreviews.attributes) {
    LiveTableWidget()
} contentStates: {
    for state in LivePreviews.states { state }
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: LivePreviews.attributes) {
    LiveTableWidget()
} contentStates: {
    for state in LivePreviews.states { state }
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: LivePreviews.attributes) {
    LiveTableWidget()
} contentStates: {
    for state in LivePreviews.states { state }
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: LivePreviews.attributes) {
    LiveTableWidget()
} contentStates: {
    for state in LivePreviews.states { state }
}
#endif
