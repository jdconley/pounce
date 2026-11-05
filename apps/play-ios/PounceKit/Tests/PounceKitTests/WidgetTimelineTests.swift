import Foundation
import Testing
@testable import PounceKit

@Suite struct WidgetTimelineTests {
    let la = widgetCalendar()

    @Test func reloadsAtTheRolloverOrInThreeHours() {
        let s = widgetSnapshot([streakView(count: 4)])
        let morning = WidgetTimeline.plan(s, pair: nil, now: at(2026, 11, 5, 9), calendar: la)
        #expect(morning.reload == at(2026, 11, 5, 12))
        #expect(morning.dates == [at(2026, 11, 5, 9)])
        let late = WidgetTimeline.plan(s, pair: nil, now: at(2026, 11, 6, 2), calendar: la)
        #expect(late.reload == at(2026, 11, 6, 4))
        #expect(late.dates == [at(2026, 11, 6, 2), at(2026, 11, 6, 4)], "an entry greys today at the rollover")
    }

    @Test func eveningEntry() {
        let s = widgetSnapshot([streakView(count: 4)])
        let plan = WidgetTimeline.plan(s, pair: nil, now: at(2026, 11, 5, 18), calendar: la)
        #expect(plan.dates == [at(2026, 11, 5, 18), at(2026, 11, 5, 20)])
        #expect(plan.reload == at(2026, 11, 5, 21))
    }

    @Test func pounceExpiryEntry() {
        var view = streakView(count: 4)
        view.pounce = PounceState(sent: true)
        var s = widgetSnapshot([view], now: at(2026, 11, 5, 9))
        s.pounced["pr_mia"] = at(2026, 11, 5, 9, 10)
        let plan = WidgetTimeline.plan(s, pair: nil, now: at(2026, 11, 5, 9, 15), calendar: la)
        #expect(plan.dates == [at(2026, 11, 5, 9, 15), at(2026, 11, 5, 10, 10)])
    }

    @Test func datesAreSortedUniqueAndBeforeTheReload() {
        let s = widgetSnapshot([streakView(count: 4)], quiet: ClockTime(h: 23, m: 0))
        for hour in [0, 3, 4, 9, 18, 20, 21, 23] {
            let plan = WidgetTimeline.plan(s, pair: nil, now: at(2026, 11, 5, hour), calendar: la)
            #expect(plan.dates == plan.dates.sorted())
            #expect(Set(plan.dates).count == plan.dates.count)
            #expect(plan.dates.allSatisfy { $0 <= plan.reload })
            #expect(plan.dates.first == at(2026, 11, 5, hour))
        }
    }

    @Test func noSnapshotStillReloads() {
        let plan = WidgetTimeline.plan(nil, pair: nil, now: at(2026, 11, 5, 9), calendar: la)
        #expect(plan.dates == [at(2026, 11, 5, 9)])
        #expect(plan.reload == at(2026, 11, 5, 12))
    }
}
