import Foundation

/// A wall-clock time of day, as the synced settings store it (`{h, m}`).
public struct ClockTime: Codable, Hashable, Sendable {
    public var h: Int
    public var m: Int

    public init(h: Int, m: Int) {
        self.h = h
        self.m = m
    }

    /// Wraps into one day, so a dial can step past midnight either way.
    public init(minutes: Int) {
        let day = 24 * 60
        let v = ((minutes % day) + day) % day
        self.init(h: v / 60, m: v % 60)
    }

    public var minutes: Int { h * 60 + m }

    /// `HH:MM`, numerals only.
    public var text: String { String(format: "%02d:%02d", h, m) }

    public var json: JSONValue { .object(["h": .number(Double(h)), "m": .number(Double(m))]) }

    init?(json: JSONValue?) {
        guard case .object(let o)? = json, let h = o["h"]?.numberValue, let m = o["m"]?.numberValue,
              h.rounded() == h, m.rounded() == m, (0..<24).contains(Int(h)), (0..<60).contains(Int(m))
        else { return nil }
        self.init(h: Int(h), m: Int(m))
    }
}

/// The synced `settings` keys play-api reads (`SETTING_KEYS` in `src/notify/settings.ts`).
public enum NotifyKey {
    public static let reminders = "reminders.on"
    public static let auto = "reminders.auto"
    public static let weekday = "reminders.weekday"
    public static let weekend = "reminders.weekend"
    public static let quietStart = "quiet.start"
    public static let quietEnd = "quiet.end"
    public static let lastChance = "lastChance.on"

    public static let all: Set<String> = [reminders, auto, weekday, weekend, quietStart, quietEnd, lastChance]
}

/// A player's notification settings (spec §12.6) with the age band's defaults (§12.3, §14.1):
/// adults get reminders, learned timing and last chance; teens get them off until they turn them
/// on, and quiet hours from 21:00; a kitten gets nothing from the server.
public struct NotifySettings: Equatable, Sendable {
    /// The bell: every reminder-type push. "Your move" is unaffected.
    public var reminders: Bool
    /// The reminder time is learned from when you play; otherwise `weekday` and `weekend`.
    public var auto: Bool
    public var weekday: ClockTime
    public var weekend: ClockTime
    public var quietStart: ClockTime
    public var quietEnd: ClockTime
    public var lastChance: Bool

    public init(
        reminders: Bool, auto: Bool, weekday: ClockTime, weekend: ClockTime, quietStart: ClockTime,
        quietEnd: ClockTime, lastChance: Bool
    ) {
        self.reminders = reminders
        self.auto = auto
        self.weekday = weekday
        self.weekend = weekend
        self.quietStart = quietStart
        self.quietEnd = quietEnd
        self.lastChance = lastChance
    }

    /// 19:30 local (§12.3).
    public static let defaultReminder = ClockTime(h: 19, m: 30)

    public static func defaults(band: AgeBand?) -> NotifySettings {
        let on = band != .teen && band != .kitten
        return NotifySettings(
            reminders: on, auto: on, weekday: defaultReminder, weekend: defaultReminder,
            quietStart: ClockTime(h: band == .teen ? 21 : 22, m: 0), quietEnd: ClockTime(h: 8, m: 0), lastChance: on)
    }

    /// Synced values over the band's defaults; a value that doesn't parse falls back. A kitten's
    /// reminders stay off whatever is stored (the server sends a kitten nothing).
    public static func resolve(_ section: SyncSection, band: AgeBand?) -> NotifySettings {
        var s = defaults(band: band)
        func flag(_ key: String) -> Bool? { section[key]?.v.boolValue }
        func clock(_ key: String) -> ClockTime? { ClockTime(json: section[key]?.v) }
        let kitten = band == .kitten
        s.reminders = !kitten && (flag(NotifyKey.reminders) ?? s.reminders)
        s.auto = !kitten && (flag(NotifyKey.auto) ?? s.auto)
        s.lastChance = !kitten && (flag(NotifyKey.lastChance) ?? s.lastChance)
        s.weekday = clock(NotifyKey.weekday) ?? s.weekday
        s.weekend = clock(NotifyKey.weekend) ?? s.weekend
        s.quietStart = clock(NotifyKey.quietStart) ?? s.quietStart
        s.quietEnd = clock(NotifyKey.quietEnd) ?? s.quietEnd
        return s
    }

    public static func inQuiet(_ minutes: Int, start: ClockTime, end: ClockTime) -> Bool {
        let a = start.minutes, b = end.minutes
        if a == b { return false }
        return a < b ? minutes >= a && minutes < b : minutes >= a || minutes < b
    }

    private static let day = 24 * 60
    /// A streak day starts at 04:00 (§6.3); times are compared in that order.
    private static let rollover = 4 * 60
    private static func order(_ m: Int) -> Int { (((m - rollover) % day) + day) % day }

    /// A reminder time the way the server will use it (`clampReminder`): outside quiet hours and
    /// at least 2 hours before they start.
    public func clamped(_ time: ClockTime) -> ClockTime {
        let latest = Self.order(quietStart.minutes - 120)
        let earliest = Self.order(quietEnd.minutes)
        var v = min(Self.order(time.minutes), latest)
        if earliest <= latest { v = max(v, earliest) }
        return ClockTime(minutes: v + Self.rollover)
    }

    /// Last chance: 90 minutes before quiet hours (§12.1).
    public var lastChanceTime: ClockTime { ClockTime(minutes: quietStart.minutes - 90) }
}

/// A kitten's only daily nudge (§14.1): a local reminder at a fixed 17:00, off by default.
public enum KittenReminder {
    public static let id = "kitten-daily"
    public static let time = ClockTime(h: 17, m: 0)
}
