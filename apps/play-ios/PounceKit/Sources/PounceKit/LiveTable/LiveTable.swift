import Foundation
#if os(iOS)
import ActivityKit
#endif

/// The live table's `content-state` (spec §11.3), exactly as play-api's `LiveState` sends it
/// (`src/live/live.ts`; checked against `fixtures/push/live-activity.json`): the rug strip's seats
/// from this device's point of view, whose move it is, and the pair's paws. No dates, so
/// ActivityKit's decoder needs no date strategy.
public struct LiveTableState: Codable, Hashable, Sendable {
    public struct Seat: Codable, Hashable, Sendable {
        public var cat: Int
        /// The phase this seat is working on, 1 to 10.
        public var phase: Int
        /// Absent for a bot (the House Cat).
        public var name: String?
        public var bot: Bool
        /// This device holds the seat.
        public var me: Bool

        public init(cat: Int, phase: Int, name: String?, bot: Bool, me: Bool) {
            self.cat = cat
            self.phase = phase
            self.name = name
            self.bot = bot
            self.me = me
        }
    }

    /// The device player's pair at this table: the numeral and today's two paws.
    public struct Paws: Codable, Hashable, Sendable {
        public var count: Int
        public var me: Bool
        public var them: Bool

        public init(count: Int, me: Bool, them: Bool) {
            self.count = count
            self.me = me
            self.them = them
        }
    }

    public var table: String
    public var seats: [Seat]
    /// Whose move it is; nil between rounds.
    public var turn: Int?
    /// The move is one of this device's seats.
    public var mine: Bool
    public var streak: Paws?

    public init(table: String, seats: [Seat], turn: Int?, mine: Bool, streak: Paws?) {
        self.table = table
        self.seats = seats
        self.turn = turn
        self.mine = mine
        self.streak = streak
    }
}

/// The live table's fixed attributes: the table it opens. The server's push-to-start names this
/// type (`attributes-type`), so its Swift name must stay `LiveTableAttributes`.
public struct LiveTableAttributes: Codable, Hashable, Sendable {
    public var code: String

    public init(code: String) {
        self.code = code
    }

    /// The `attributes-type` the server sends.
    public static let typeName = "LiveTableAttributes"
}

#if os(iOS)
extension LiveTableAttributes: ActivityAttributes {
    public typealias ContentState = LiveTableState
}
#endif
