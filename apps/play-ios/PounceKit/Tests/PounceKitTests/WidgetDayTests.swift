import Foundation
import Testing
@testable import PounceKit

/// A calendar in one time zone, and a date in it from wall-clock numbers.
func widgetCalendar(_ zone: String = "America/Los_Angeles") -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    return c
}

func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0, _ calendar: Calendar = widgetCalendar()) -> Date {
    calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

@Suite struct WidgetDayTests {
    let la = widgetCalendar()

    @Test func dayRollsOverAtFour() {
        #expect(WidgetDay.key(at(2026, 11, 5, 3, 59), calendar: la) == "2026-11-04", "1 a.m. counts as tonight")
        #expect(WidgetDay.key(at(2026, 11, 5, 4, 0), calendar: la) == "2026-11-05")
        #expect(WidgetDay.key(at(2026, 11, 5, 23, 59), calendar: la) == "2026-11-05")
        #expect(WidgetDay.key(at(2026, 1, 1, 2, 0), calendar: la) == "2025-12-31", "across the year")
    }

    @Test func nextRollover() {
        #expect(WidgetDay.nextRollover(after: at(2026, 11, 5, 3, 0), calendar: la) == at(2026, 11, 5, 4, 0))
        #expect(WidgetDay.nextRollover(after: at(2026, 11, 5, 4, 0), calendar: la) == at(2026, 11, 6, 4, 0))
        #expect(WidgetDay.nextRollover(after: at(2026, 11, 5, 21, 30), calendar: la) == at(2026, 11, 6, 4, 0))
    }

    @Test func nextRolloverAcrossDaylightSaving() {
        // Fall back (1 Nov 2026, 02:00 → 01:00): the night is 25 hours, 04:00 is still 04:00.
        let fallBack = WidgetDay.nextRollover(after: at(2026, 10, 31, 22, 0), calendar: la)
        #expect(la.dateComponents([.day, .hour], from: fallBack) == DateComponents(day: 1, hour: 4))
        #expect(fallBack.timeIntervalSince(at(2026, 10, 31, 22, 0)) == 7 * 3600)
        // Spring forward (8 Mar 2026, 02:00 → 03:00): 23 hours.
        let spring = WidgetDay.nextRollover(after: at(2026, 3, 7, 22, 0), calendar: la)
        #expect(la.dateComponents([.day, .hour], from: spring) == DateComponents(day: 8, hour: 4))
        #expect(spring.timeIntervalSince(at(2026, 3, 7, 22, 0)) == 5 * 3600)
    }

    @Test func otherTimeZone() {
        let tokyo = widgetCalendar("Asia/Tokyo")
        let now = at(2026, 11, 5, 2, 0, tokyo)
        #expect(WidgetDay.key(now, calendar: tokyo) == "2026-11-04")
        #expect(WidgetDay.nextRollover(after: now, calendar: tokyo) == at(2026, 11, 5, 4, 0, tokyo))
    }

    @Test func eveningCutoffIsTwoHoursBeforeQuiet() {
        let quiet = ClockTime(h: 22, m: 0)
        #expect(WidgetDay.eveningCutoff(for: at(2026, 11, 5, 9, 0), quietStart: quiet, calendar: la) == at(2026, 11, 5, 20, 0))
        // After midnight it still belongs to the day before.
        #expect(WidgetDay.eveningCutoff(for: at(2026, 11, 6, 1, 0), quietStart: quiet, calendar: la) == at(2026, 11, 5, 20, 0))
        // Quiet from 01:00: the cutoff is 23:00 the same evening.
        #expect(WidgetDay.eveningCutoff(for: at(2026, 11, 5, 9, 0), quietStart: ClockTime(h: 1, m: 0), calendar: la)
            == at(2026, 11, 5, 23, 0))
        // Quiet from 05:00: the cutoff is 03:00, after midnight, before the rollover.
        #expect(WidgetDay.eveningCutoff(for: at(2026, 11, 5, 9, 0), quietStart: ClockTime(h: 5, m: 0), calendar: la)
            == at(2026, 11, 6, 3, 0))
    }
}
