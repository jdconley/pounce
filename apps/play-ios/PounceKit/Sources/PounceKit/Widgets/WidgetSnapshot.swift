import Foundation

/// What the widgets draw from (spec §11.2), kept in the App Group by the app, the widget's own
/// fetch, the Pounce intent and `PounceNotify`. Everything in it is the owner's: their pairs as
/// the server last sent them, the names of those pairs' tables, and what the widgets need to
/// project the day forward with no network.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Owner: Codable, Equatable, Sendable {
        /// The local person id (`?person=` on the widget's calls).
        public var person: String
        public var name: String
        public var cat: Int

        public init(person: String, name: String, cat: Int) {
            self.person = person
            self.name = name
            self.cat = cat
        }

        public var face: StreakView.Partner { .init(name: name, cat: cat) }
    }

    public var owner: Owner?
    /// Nil until the age is known; widget push needs teen or adult.
    public var band: AgeBand?
    /// The server's base URL, for the widget's fetch and the Pounce intent. Nil under demos and
    /// UI tests, where the widget never touches the network.
    public var server: String?
    /// The owner's pairs, top pair first.
    public var pairs: [StreakView]
    /// Room code to table name, for the pairs' tables.
    public var tableNames: [String: String]
    /// The owner's quiet hours start, for the evening cutoff (§6.1).
    public var quietStart: ClockTime
    /// The streak day `pairs`' today fields (`me`, `them`, `kept`) are for.
    public var day: String
    public var savedAt: Date
    /// When each pair's pounce bell last changed on this device: its hour runs from here.
    public var pounced: [String: Date]

    public init(
        owner: Owner?, band: AgeBand?, server: String?, pairs: [StreakView], tableNames: [String: String],
        quietStart: ClockTime, day: String, savedAt: Date, pounced: [String: Date] = [:]
    ) {
        self.owner = owner
        self.band = band
        self.server = server
        self.pairs = pairs
        self.tableNames = tableNames
        self.quietStart = quietStart
        self.day = day
        self.savedAt = savedAt
        self.pounced = pounced
    }

    /// The app's snapshot: `names` may hold every known table; only the pairs' tables are kept
    /// (with any name `previous` had for them). Pounce times carry over from `previous` while a
    /// pair's bell is unchanged. `pairs` nil means the app doesn't know them yet (it launched
    /// offline): the same owner's stored pairs stay, moved on to today.
    public static func make(
        owner: Owner?, band: AgeBand?, server: String?, pairs known: [StreakView]?, names: [String: String],
        quietStart: ClockTime, previous: WidgetSnapshot?, now: Date, calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let pairs: [StreakView]
        if let known {
            pairs = known
        } else if let previous, owner != nil, previous.owner?.person == owner?.person {
            pairs = previous.projected(to: now, calendar: calendar).pairs
        } else {
            pairs = []
        }
        let codes = Set(pairs.flatMap { $0.myMove + $0.theirMove })
        let kept = (previous?.tableNames ?? [:]).merging(names) { $1 }.filter { codes.contains($0.key) }
        var snapshot = WidgetSnapshot(
            owner: owner, band: band, server: server, pairs: pairs, tableNames: kept, quietStart: quietStart,
            day: WidgetDay.key(now, calendar: calendar), savedAt: now)
        snapshot.pounced = Self.pounceTimes(pairs, previous: previous, now: now)
        return snapshot
    }

    /// The pair a widget shows: the chosen one, else (none chosen, or it's gone) the top pair.
    public func pair(_ id: String?) -> StreakView? {
        if let id, let chosen = pairs.first(where: { $0.pair == id }) { return chosen }
        return pairs.first
    }

    /// Whether a widget would draw differently: everything but the save time.
    public func visiblyDiffers(from old: WidgetSnapshot?) -> Bool {
        guard var old else { return true }
        old.savedAt = savedAt
        return old != self
    }

    /// A fresh list from the server (the widget's fetch, or the app): the table names stay.
    public func withPairs(_ list: [StreakView], now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        var next = self
        next.pounced = Self.pounceTimes(list, previous: self, now: now)
        next.pairs = list
        next.day = WidgetDay.key(now, calendar: calendar)
        next.savedAt = now
        return next
    }

    /// The pairs as they stand on `date`'s day: after the rollover today is grey again, and a
    /// pause whose last day has passed is over. Nothing else changes until the server says so.
    public func projected(to date: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        let today = WidgetDay.key(date, calendar: calendar)
        guard today > day else { return self }
        var next = self
        next.pairs = pairs.map { Self.project($0, to: today) }
        next.day = today
        return next
    }

    static func project(_ view: StreakView, to today: String) -> StreakView {
        var v = view
        v.me = false
        v.them = false
        v.kept = false
        v.todayToy = nil
        if let until = v.pausedUntil, until < today { v.pausedUntil = nil }
        return v
    }

    /// A push's news folded in (spec §11.2, §12.7): the `streak` block updates its pair (one the
    /// snapshot doesn't know is ignored), and a pounce's answer lands on the pair it came from.
    public func applying(_ push: PushPayload, now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        var next = projected(to: now, calendar: calendar)
        var changed = false
        if let s = push.streak, let i = next.pairs.firstIndex(where: { $0.pair == s.pair }) {
            next.pairs[i].count = s.count
            next.pairs[i].me = s.me
            next.pairs[i].them = s.them
            next.pairs[i].kept = s.me && s.them
            next.pairs[i].naps = s.naps
            next.pairs[i].myMove = s.myMove
            next.pairs[i].theirMove = s.theirMove
            changed = true
        }
        if push.kind == .pounceAnswered, let answer = push.pounce?.answer, let from = push.from,
           let i = next.pairs.firstIndex(where: { $0.partner.name == from.name && $0.partner.cat == from.cat }) {
            next.pairs[i].pounce.answer = answer
            next.pairs[i].pounce.sent = false
            next.pounced[next.pairs[i].pair] = now
            changed = true
        }
        guard changed else { return self }
        next.savedAt = now
        return next
    }

    /// Each pair's bell time: kept while its bell is unchanged, now when it changed, none when ready.
    static func pounceTimes(_ pairs: [StreakView], previous: WidgetSnapshot?, now: Date) -> [String: Date] {
        var times: [String: Date] = [:]
        for view in pairs {
            let bell = BellState.make(view.pounce)
            guard bell != .ready else { continue }
            let before = previous?.pairs.first { $0.pair == view.pair }.map { BellState.make($0.pounce) }
            times[view.pair] = before == bell ? (previous?.pounced[view.pair] ?? now) : now
        }
        return times
    }

    /// The gallery's and the loading placeholder's pair (not a demo: it ships).
    public static let sample = WidgetSnapshot(
        owner: Owner(person: "sample", name: "JD", cat: 4), band: nil, server: nil,
        pairs: [
            StreakView(
                pair: "sample", partner: .init(name: "Mia", cat: 2), count: 12, me: true, them: false, best: 12,
                condoStage: 4, theirMove: ["SAMPL"])
        ],
        tableNames: ["SAMPL": "Couch Cats"], quietStart: ClockTime(h: 22, m: 0),
        // A day that never passes, so the placeholder's paw stays lit.
        day: "9999-12-31", savedAt: .distantPast)
}
