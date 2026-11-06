import Foundation

/// `GET /v1/me/trophies` (trophy room design §3, §5; play-api `src/streaks/trophies.ts`): your own
/// streak, personal records, what you've earned across your pairs, the catalog with where each
/// item unlocks (D4), and your connections.
public struct Trophies: Codable, Equatable, Sendable {
    public struct Records: Codable, Equatable, Sendable {
        public var current: Int
        public var best: Int
        /// The longest pair streak you've had, with anyone.
        public var longestPair: Int
        /// Days you've kept, ever.
        public var totalDays: Int
        public var perfectWeeks: Int

        public init(current: Int, best: Int, longestPair: Int, totalDays: Int, perfectWeeks: Int) {
            self.current = current
            self.best = best
            self.longestPair = longestPair
            self.totalDays = totalDays
            self.perfectWeeks = perfectWeeks
        }
    }

    /// Everything you've unwrapped in any pair, without the defaults, and the highest condo stage.
    public struct Earned: Codable, Equatable, Sendable {
        public var toys: [String]
        public var backs: [String]
        public var rugs: [String]
        public var condoStage: Int

        public init(toys: [String], backs: [String], rugs: [String], condoStage: Int) {
            self.toys = toys
            self.backs = backs
            self.rugs = rugs
            self.condoStage = condoStage
        }
    }

    public enum Kind: String, Codable, Sendable {
        case condo, back, rug, toy
        /// A kind this app doesn't know yet: not drawn.
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// One catalog entry: `at` is the numeral on its ring, `progress` 0 to 1 (1 once earned).
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var kind: Kind
        public var at: Int
        public var progress: Double

        public init(id: String, kind: Kind, at: Int, progress: Double) {
            self.id = id
            self.kind = kind
            self.at = at
            self.progress = progress
        }
    }

    public var own: OwnStreak
    public var records: Records
    public var earned: Earned
    public var catalog: [Item]
    /// Exactly the pairs of `GET /v1/me/streaks`.
    public var connections: [StreakView]

    public init(own: OwnStreak, records: Records, earned: Earned, catalog: [Item], connections: [StreakView]) {
        self.own = own
        self.records = records
        self.earned = earned
        self.catalog = catalog
        self.connections = connections
    }
}
