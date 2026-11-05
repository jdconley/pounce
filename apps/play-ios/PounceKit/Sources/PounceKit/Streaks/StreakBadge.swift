import Foundation

/// What a streak badge draws (Home §10.1, the table's top bar §10.3): today's two paws, the
/// numeral and one mode picture. Never who missed a day.
public struct StreakBadge: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case normal
        /// A missed day with no nap left: the numeral wears a bandage, two dots fill as days are kept.
        case winback(kept: Int)
        /// The suitcase: paused.
        case paused
        /// A cat nap covered yesterday (and today isn't kept yet): the blanket.
        case napped
        /// A fresh 0 after a break: sleeping cats and a soft sparkle.
        case fresh
    }

    public var count: Int
    public var me: Bool
    public var them: Bool
    public var kept: Bool
    public var mode: Mode
    /// The little cloud with a plus (§10.5): keep this streak on all your devices.
    public var offerSignIn: Bool

    public init(count: Int, me: Bool, them: Bool, kept: Bool, mode: Mode, offerSignIn: Bool) {
        self.count = count
        self.me = me
        self.them = them
        self.kept = kept
        self.mode = mode
        self.offerSignIn = offerSignIn
    }

    /// The badge for the top pair, or nil with no pair. `all` is every pair of the person: the cloud
    /// shows once any of them reached 3, for a guest on a phone that offers sign-in (never a kitten's).
    public static func make(_ top: StreakView?, all: [StreakView], signedIn: Bool, offersSignIn: Bool) -> StreakBadge? {
        guard let top else { return nil }
        return StreakBadge(
            count: top.count, me: top.me, them: top.them, kept: top.kept, mode: mode(top),
            offerSignIn: !signedIn && offersSignIn && all.contains { $0.count >= 3 || $0.best >= 3 })
    }

    public static func mode(_ view: StreakView) -> Mode {
        if view.pausedUntil != nil { return .paused }
        if let winback = view.winback { return .winback(kept: winback.kept) }
        if view.count == 0 && view.best > 0 { return .fresh }
        if !view.kept, view.week.count >= 2, view.week[view.week.count - 2].state == .nap { return .napped }
        return .normal
    }
}

/// The moment a `{t:"streak"}` view marks at the table (§9.5).
public enum StreakStamp: Equatable, Sendable {
    /// Your turn kept today for both of you: double paw stamp, the numeral rolls up, the toy arcs in.
    case dayKept(toy: String?)
    /// You're in and the other person isn't yet: one paw lights with a small stamp.
    case halfDone

    public static func diff(old: StreakView?, new: StreakView) -> StreakStamp? {
        if new.kept && old?.kept != true { return .dayKept(toy: new.todayToy) }
        if new.me && !new.kept && old?.me != true { return .halfDone }
        return nil
    }
}

/// A stamp a table socket brought (§9.5), for one pair as one person on this phone sees it.
public struct TableStamp: Sendable {
    public var pair: String
    public var person: String
    public var kind: StreakStamp
    /// Goes up with each stamp at this table, so the same stamp plays twice.
    public var serial: Int
    public var at: Date

    /// A badge that appears this soon after its stamp still plays it (the first day's badge
    /// appears with the message that made the pair).
    public static let freshFor: TimeInterval = 1.5

    public init(pair: String, person: String, kind: StreakStamp, serial: Int, at: Date) {
        self.pair = pair
        self.person = person
        self.kind = kind
        self.serial = serial
        self.at = at
    }

    /// Plays on the badge of this pair as this person sees it; never on another pair's badge, and
    /// never twice for one pair whose two people share this phone.
    public func plays(on pair: String, person: String) -> Bool {
        self.pair == pair && self.person == person
    }

    public func isFresh(now: Date = .now) -> Bool {
        now.timeIntervalSince(at) < Self.freshFor
    }
}

/// The latest stamp per pair and person at one table. Two people of a same-phone pair hear a kept
/// day back to back, often before the screen redraws, so one slot would lose the first stamp.
public struct TableStamps: Sendable {
    private var latest: [String: TableStamp] = [:]
    private var serial = 0

    public init() {}

    public mutating func add(pair: String, person: String, kind: StreakStamp, at: Date) {
        serial += 1
        latest["\(pair)|\(person)"] = TableStamp(pair: pair, person: person, kind: kind, serial: serial, at: at)
    }

    public func latest(pair: String, person: String) -> TableStamp? { latest["\(pair)|\(person)"] }
}

/// Which pair's badge a table shows (§10.3): the top one whose people both sit there.
public enum TableStreak {
    /// `candidates` are this phone's seated people's pairs, top pair first. A pair is at this table
    /// when the table is one of its moves, when this table's socket reported it, or when another
    /// human seat is its partner (same name and cat).
    public static func pick(
        code: String, candidates: [(person: String, view: StreakView)], reported: Set<String>, others: [Person]
    ) -> (person: String, view: StreakView)? {
        candidates.first { candidate in
            let view = candidate.view
            if view.myMove.contains(code) || view.theirMove.contains(code) { return true }
            if reported.contains(view.pair) { return true }
            return others.contains { $0.name == view.partner.name && $0.cat == view.partner.cat }
        }
    }
}
