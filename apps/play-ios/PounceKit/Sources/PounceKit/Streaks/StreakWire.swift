import Foundation

/// A table's rug and card back (spec §9.4). Ids are the catalog's, which are also the art's file names.
public struct Look: Codable, Hashable, Sendable {
    public var rug: String
    public var back: String

    public init(rug: String, back: String) {
        self.rug = rug
        self.back = back
    }

    /// What every table has until someone changes it.
    public static let standard = Look(rug: StreakCatalog.defaultRug, back: StreakCatalog.defaultBack)
}

/// One day of the week strip. `missed` is drawn like `none`: no screen says a day was missed (§2).
public enum WeekState: String, Codable, Sendable {
    case kept, nap, held, paused, missed, live, none

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WeekState(rawValue: raw) ?? .none
    }
}

public struct WeekDot: Codable, Hashable, Sendable {
    /// `YYYY-MM-DD` in the viewer's day.
    public var day: String
    public var state: WeekState

    public init(day: String, state: WeekState) {
        self.day = day
        self.state = state
    }
}

/// A pair's shared streak as one of its people sees it (`StreakView` on the server, §13.4).
/// Today's two paws are `me` and `them`; nothing here says who missed a past day.
public struct StreakView: Codable, Equatable, Sendable, Identifiable {
    public struct Partner: Codable, Hashable, Sendable {
        public var name: String
        public var cat: Int
        public init(name: String, cat: Int) {
            self.name = name
            self.cat = cat
        }
    }

    public struct Winback: Codable, Hashable, Sendable {
        /// Kept days so far of the two that win the streak back.
        public var kept: Int
        public init(kept: Int) { self.kept = kept }
    }

    public struct Unlocks: Codable, Hashable, Sendable {
        public var backs: [String]
        public var rugs: [String]
        public init(backs: [String], rugs: [String]) {
            self.backs = backs
            self.rugs = rugs
        }
    }

    public struct Gift: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var milestone: Int
        /// A toy, back or rug id, or `confetti` once everything is owned.
        public var item: String
        public init(id: String, milestone: Int, item: String) {
            self.id = id
            self.milestone = milestone
            self.item = item
        }
    }

    public var pair: String
    public var partner: Partner
    public var count: Int
    public var me: Bool
    public var them: Bool
    /// Today is kept (both in, and the day's effects applied).
    public var kept: Bool
    public var naps: Int
    public var winback: Winback?
    public var pausedUntil: String?
    public var best: Int
    public var lifetimeKept: Int
    public var perfectWeeks: Int
    public var week: [WeekDot]
    public var next: Int
    public var condoStage: Int
    public var toys: [String]
    public var todayToy: String?
    public var unlocked: Unlocks
    public var gifts: [Gift]
    public var myMove: [String]
    public var theirMove: [String]
    /// Only in `GET /v1/me/streaks`: the person's pinned top pair.
    public var pinned: Bool

    public var id: String { pair }

    public init(
        pair: String, partner: Partner, count: Int, me: Bool = false, them: Bool = false, kept: Bool = false,
        naps: Int = 0, winback: Winback? = nil, pausedUntil: String? = nil, best: Int = 0, lifetimeKept: Int = 0,
        perfectWeeks: Int = 0, week: [WeekDot] = [], next: Int = 3, condoStage: Int = 0, toys: [String] = [],
        todayToy: String? = nil, unlocked: Unlocks = Unlocks(backs: [], rugs: []), gifts: [Gift] = [],
        myMove: [String] = [], theirMove: [String] = [], pinned: Bool = false
    ) {
        self.pair = pair
        self.partner = partner
        self.count = count
        self.me = me
        self.them = them
        self.kept = kept
        self.naps = naps
        self.winback = winback
        self.pausedUntil = pausedUntil
        self.best = best
        self.lifetimeKept = lifetimeKept
        self.perfectWeeks = perfectWeeks
        self.week = week
        self.next = next
        self.condoStage = condoStage
        self.toys = toys
        self.todayToy = todayToy
        self.unlocked = unlocked
        self.gifts = gifts
        self.myMove = myMove
        self.theirMove = theirMove
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey {
        case pair, partner, count, me, them, kept, naps, winback, pausedUntil, best, lifetimeKept, perfectWeeks
        case week, next, condoStage, toys, todayToy, unlocked, gifts, myMove, theirMove, pinned
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pair = try c.decode(String.self, forKey: .pair)
        partner = try c.decode(Partner.self, forKey: .partner)
        count = try c.decode(Int.self, forKey: .count)
        me = try c.decodeIfPresent(Bool.self, forKey: .me) ?? false
        them = try c.decodeIfPresent(Bool.self, forKey: .them) ?? false
        kept = try c.decodeIfPresent(Bool.self, forKey: .kept) ?? false
        naps = try c.decodeIfPresent(Int.self, forKey: .naps) ?? 0
        winback = try c.decodeIfPresent(Winback.self, forKey: .winback)
        pausedUntil = try c.decodeIfPresent(String.self, forKey: .pausedUntil)
        best = try c.decodeIfPresent(Int.self, forKey: .best) ?? count
        lifetimeKept = try c.decodeIfPresent(Int.self, forKey: .lifetimeKept) ?? 0
        perfectWeeks = try c.decodeIfPresent(Int.self, forKey: .perfectWeeks) ?? 0
        week = try c.decodeIfPresent([WeekDot].self, forKey: .week) ?? []
        next = try c.decodeIfPresent(Int.self, forKey: .next) ?? StreakCatalog.nextMilestone(after: count)
        condoStage = try c.decodeIfPresent(Int.self, forKey: .condoStage) ?? 0
        toys = try c.decodeIfPresent([String].self, forKey: .toys) ?? []
        todayToy = try c.decodeIfPresent(String.self, forKey: .todayToy)
        unlocked = try c.decodeIfPresent(Unlocks.self, forKey: .unlocked) ?? Unlocks(backs: [], rugs: [])
        gifts = try c.decodeIfPresent([Gift].self, forKey: .gifts) ?? []
        myMove = try c.decodeIfPresent([String].self, forKey: .myMove) ?? []
        theirMove = try c.decodeIfPresent([String].self, forKey: .theirMove) ?? []
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}

/// A streak this person left, still undoable from its ghosted cat (§14).
public struct LeftPair: Codable, Hashable, Sendable, Identifiable {
    public var pair: String
    public var partner: StreakView.Partner
    public var id: String { pair }

    public init(pair: String, partner: StreakView.Partner) {
        self.pair = pair
        self.partner = partner
    }
}

/// `GET /v1/me/streaks`: the top pair first (pinned, then longest, then latest turn).
public struct StreakList: Codable, Equatable, Sendable {
    public var pairs: [StreakView]
    public var left: [LeftPair]

    public init(pairs: [StreakView] = [], left: [LeftPair] = []) {
        self.pairs = pairs
        self.left = left
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pairs = try c.decode([StreakView].self, forKey: .pairs)
        left = try c.decodeIfPresent([LeftPair].self, forKey: .left) ?? []
    }

    private enum CodingKeys: String, CodingKey { case pairs, left }
}

/// The catalog the server rewards from (`apps/play-api/src/streaks/catalog.ts`). Ids are art file names.
public enum StreakCatalog {
    public static let defaultBack = "back-violet-paw"
    public static let defaultRug = "rug-classic"
    public static let backs = [
        defaultBack, "back-yarn-swirl", "back-moonlit-fish", "back-cucumber-chaos", "back-crown", "back-heart-paws",
        "back-golden-yarn",
    ]
    public static let rugs = [defaultRug, "rug-night-sky", "rug-candy-stripe", "rug-fish-pond", "rug-royal-violet"]

    public enum Rarity: String, Sendable { case common, shiny, golden }

    public static let commonToys = [
        "yarn-ball", "feather-wand", "cardboard-box", "mouse", "fish", "bell", "laser-dot", "catnip-sack", "sock",
        "bottle-cap", "crinkle-ball", "spring", "ribbon", "paper-bag", "pom-pom", "cork",
    ].map { "toy-\($0)" }
    public static let shinyToys = ["rainbow-yarn", "glitter-mouse", "silver-bell", "moon-fish", "star-wand", "disco-ball"]
        .map { "toy-\($0)" }
    public static let goldenToys = ["golden-fish", "golden-mouse"].map { "toy-\($0)" }
    public static let toys = commonToys + shinyToys + goldenToys

    public static func rarity(_ toy: String) -> Rarity {
        if goldenToys.contains(toy) { return .golden }
        if shinyToys.contains(toy) { return .shiny }
        return .common
    }

    /// 3, 7, 14, 30, 50, 75, 100, 150, 200, 250, 300, 365, then every hundred.
    public static let milestones = [3, 7, 14, 30, 50, 75, 100, 150, 200, 250, 300, 365]

    public static func nextMilestone(after n: Int) -> Int {
        milestones.first { $0 > n } ?? (n / 100 + 1) * 100
    }

    /// The milestone before `next` (0 before the first): where the progress arc starts.
    public static func previousMilestone(before next: Int) -> Int {
        if let i = milestones.firstIndex(of: next) { return i == 0 ? 0 : milestones[i - 1] }
        return next == 400 ? 365 : next - 100
    }

    /// Condo stage thresholds in lifetime days together (§9.1).
    public static let condoThresholds = [1, 3, 7, 14, 30, 50, 100, 150, 200, 365]
}
