import Foundation

/// A cat's pose on a widget (the existing sprites, spec §11.1).
public enum WidgetPose: String, Sendable {
    case idle, awake, celebrate, asleep, leap
}

/// The medium widget's Pounce button (spec §11.1, §12.4).
public enum WidgetPounce: Equatable, Sendable {
    /// The bell: a tap sends a "you pick" pounce.
    case ready
    /// Sent, unanswered: the check (a moon beside it when it landed in their quiet hours).
    case sent(quiet: Bool)
    /// The bell rests (§12.4 limits): the sleeping bell, and a tap does nothing.
    case resting
    /// Their answer, for the hour.
    case answered(PounceAnswer)

    /// The bell for a pounce state (the app's `BellState`).
    public init(_ bell: BellState) {
        switch bell {
        case .ready: self = .ready
        case .sent: self = .sent(quiet: false)
        case .quiet: self = .sent(quiet: true)
        case .resting: self = .resting
        case .answered(let a): self = .answered(a)
        }
    }
}

/// What a widget shows for one pair at one moment (spec §11.1): the cats' poses, today's paws and
/// ring, the numeral and its mode, the shared tables and the Pounce button, and where a tap goes.
public struct UsWidgetState: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case pair
        /// No owner yet, no pairs, or streaks off: your cat on the first condo, no numeral.
        case empty
    }

    public struct Table: Equatable, Sendable, Identifiable {
        public var code: String
        public var name: String
        /// Your move (your bell), else theirs (their cat).
        public var mine: Bool
        public var id: String { code }

        public init(code: String, name: String, mine: Bool) {
            self.code = code
            self.name = name
            self.mine = mine
        }
    }

    /// How long a pounce's check (or answer, or rest) shows on the widget.
    public static let pounceHour: TimeInterval = 3600
    /// The most tables the medium widget lists.
    public static let maxTables = 2

    public var kind: Kind
    public var me: StreakView.Partner?
    public var partner: StreakView.Partner?
    public var pair: String?
    public var count: Int
    public var meIn: Bool
    public var themIn: Bool
    public var kept: Bool
    public var mode: StreakBadge.Mode
    public var myPose: WidgetPose
    public var theirPose: WidgetPose
    public var condoStage: Int
    /// Today's ring: 0, half for one of you in, full for kept or both in.
    public var ring: Double
    public var tables: [Table]
    public var pounce: WidgetPounce
    /// When the Pounce button goes back to the bell (a timeline entry).
    public var pounceExpires: Date?
    /// Where a tap on the whole widget goes: your first move, else the Us screen.
    public var url: URL
    /// The first table where it's your move (the rectangular widget's bell).
    public var myMove: String?

    public static func empty(me: StreakView.Partner?) -> UsWidgetState {
        UsWidgetState(
            kind: .empty, me: me, partner: nil, pair: nil, count: 0, meIn: false, themIn: false, kept: false,
            mode: .normal, myPose: .idle, theirPose: .idle, condoStage: 1, ring: 0, tables: [], pounce: .ready,
            pounceExpires: nil, url: WidgetLink.app.url, myMove: nil)
    }

    public static func make(_ snapshot: WidgetSnapshot?, pair id: String?, at date: Date, calendar: Calendar = .current) -> UsWidgetState {
        guard let snapshot else { return .empty(me: nil) }
        let me = snapshot.owner?.face
        let projected = snapshot.projected(to: date, calendar: calendar)
        guard me != nil, let view = projected.pair(id) else { return .empty(me: me) }

        let mode = StreakBadge.mode(view)
        let paused = view.pausedUntil != nil
        let evening = !view.kept && !paused && view.count >= 1
            && date >= WidgetDay.eveningCutoff(for: date, quietStart: snapshot.quietStart, calendar: calendar)
        var poses = Self.poses(view)
        if evening {
            if !view.me { poses.mine = .awake }
            if !view.them { poses.theirs = .awake }
        }

        var tables = view.myMove.map { Table(code: $0, name: Self.name($0, snapshot), mine: true) }
        for code in view.theirMove where !view.myMove.contains(code) {
            tables.append(Table(code: code, name: Self.name(code, snapshot), mine: false))
        }

        var pounce = WidgetPounce(BellState.make(view.pounce))
        var expires: Date?
        if pounce != .ready {
            let end = (snapshot.pounced[view.pair] ?? snapshot.savedAt).addingTimeInterval(Self.pounceHour)
            if date >= end { pounce = .ready } else { expires = end }
        }

        let ring: Double = view.kept || (view.me && view.them) ? 1 : view.me || view.them ? 0.5 : 0
        let url = view.myMove.first.map { WidgetLink.table($0).url } ?? WidgetLink.us(pair: view.pair).url
        return UsWidgetState(
            kind: .pair, me: me, partner: view.partner, pair: view.pair, count: view.count, meIn: view.me,
            themIn: view.them, kept: view.kept, mode: mode, myPose: poses.mine, theirPose: poses.theirs,
            condoStage: max(1, view.condoStage), ring: ring, tables: Array(tables.prefix(maxTables)), pounce: pounce,
            pounceExpires: expires, url: url, myMove: view.myMove.first)
    }

    /// The poses by state (§11.1).
    static func poses(_ view: StreakView) -> (mine: WidgetPose, theirs: WidgetPose) {
        if view.pausedUntil != nil { return (.asleep, .asleep) }
        if view.kept { return (.celebrate, .celebrate) }
        if view.me { return (.celebrate, view.theirMove.isEmpty ? .idle : .awake) }
        if !view.myMove.isEmpty { return (.awake, .idle) }
        if !view.theirMove.isEmpty { return (.idle, .awake) }
        return (.idle, .idle)
    }

    static func name(_ code: String, _ snapshot: WidgetSnapshot) -> String {
        snapshot.tableNames[code] ?? TableName.fallback(code: code)
    }
}

/// When the widgets' timeline changes and reloads (spec §11.2): entries for the predictable
/// changes, and a reload at the rollover or within three hours, whichever comes first.
public enum WidgetTimeline {
    /// A widget whose push went missing is at most this stale.
    public static let maxAge: TimeInterval = 3 * 3600

    public static func plan(
        _ snapshot: WidgetSnapshot?, pair: String?, now: Date, calendar: Calendar = .current
    ) -> (dates: [Date], reload: Date) {
        let rollover = WidgetDay.nextRollover(after: now, calendar: calendar)
        let reload = min(rollover, now.addingTimeInterval(maxAge))
        var dates: Set<Date> = [now]
        if let snapshot {
            let evening = WidgetDay.eveningCutoff(for: now, quietStart: snapshot.quietStart, calendar: calendar)
            dates.insert(evening)
            if let expires = UsWidgetState.make(snapshot, pair: pair, at: now, calendar: calendar).pounceExpires {
                dates.insert(expires)
            }
            dates.insert(rollover)
        }
        return (dates.filter { $0 >= now && $0 <= reload }.sorted(), reload)
    }
}
