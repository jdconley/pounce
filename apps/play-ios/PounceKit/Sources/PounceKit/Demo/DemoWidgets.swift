#if DEBUG
import Foundation

extension DemoFixtures {
    /// The widgets' snapshot for previews and `-demo-streaks` runs: the demo owner (JD, cat 4) with
    /// `streaks()`'s pairs, their tables named, and no server, so nothing touches the network.
    public static func widgetSnapshot(now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        WidgetSnapshot.make(
            owner: .init(person: "demo-owner", name: "JD", cat: 4), band: .adult, server: nil, pairs: streaks(today: now).pairs,
            names: [code: demoName, "K9PQR": "Kitchen Table"], quietStart: ClockTime(h: 22, m: 0), previous: nil, now: now,
            calendar: calendar)
    }

    /// One demo pair in a chosen state, for the widget previews.
    public static func widgetSnapshot(_ change: (inout StreakView) -> Void, now: Date = .now) -> WidgetSnapshot {
        var s = widgetSnapshot(now: now)
        if !s.pairs.isEmpty { change(&s.pairs[0]) }
        return s
    }
}
#endif
