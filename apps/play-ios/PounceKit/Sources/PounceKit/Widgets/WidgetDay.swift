import Foundation

/// The viewer's streak day on this device (spec §6.1, §6.3): the local calendar day, rolling
/// over at 04:00 local time, so a turn at 1 a.m. still counts as tonight. The widgets use it to
/// grey today at the rollover and to know when the evening starts, with no network.
public enum WidgetDay {
    public static let rolloverHour = 4

    /// The day `date` belongs to, as `YYYY-MM-DD` (the server's `Day`).
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let day = start(of: date, calendar: calendar)
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The next 04:00 strictly after `date` (wall clock, so daylight-saving nights are 23 or 25 hours).
    public static func nextRollover(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(
            after: date, matching: DateComponents(hour: rolloverHour, minute: 0, second: 0),
            matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
    }

    /// The evening cutoff of `date`'s day: two hours before quiet hours start (§6.1), on that
    /// day's evening or, when it falls before 04:00, in the small hours after it.
    public static func eveningCutoff(for date: Date, quietStart: ClockTime, calendar: Calendar = .current) -> Date {
        let cutoff = ClockTime(minutes: quietStart.minutes - 120)
        var day = start(of: date, calendar: calendar)
        if cutoff.h < rolloverHour { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        return calendar.date(bySettingHour: cutoff.h, minute: cutoff.m, second: 0, of: day) ?? day
    }

    /// Midnight at the start of the calendar day `date`'s streak day is named after.
    static func start(of date: Date, calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)
        guard hour < rolloverHour else { return midnight }
        return calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight
    }
}
