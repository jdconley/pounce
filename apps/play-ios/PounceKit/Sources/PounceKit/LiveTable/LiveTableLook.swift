import Foundation

/// What the live table draws (spec §11.3), from its content state: the rug strip's cats with a
/// glowing ring on whoever's move it is and their phase numerals, the bell when the move is yours,
/// the table name and the pair's paws; and for the Dynamic Island, your cat leading and the bell
/// (or the current player's cat) trailing. Words only for VoiceOver.
public struct LiveTableLook: Equatable, Sendable {
    public struct Seat: Equatable, Sendable {
        public let cat: Int
        public let phase: Int
        public let bot: Bool
        public let me: Bool
        /// Their move: the ring glows.
        public let glowing: Bool
    }

    /// The Island's trailing side (and the minimal view).
    public enum Trailing: Equatable, Sendable {
        case bell
        case cat(Int, bot: Bool)
        case none
    }

    public struct Paws: Equatable, Sendable {
        public enum Lit: Equatable, Sendable { case none, one, both }
        public let count: Int
        public let lit: Lit
    }

    public let table: String
    public let seats: [Seat]
    public let bell: Bool
    /// Your cat (the first seat this device holds), else the first cat.
    public let leadingCat: Int
    public let trailing: Trailing
    public let paws: Paws?
    /// For VoiceOver only: the table and whose move it is.
    public let spoken: String

    private static let botName = "House Cat"

    public init(_ state: LiveTableState) {
        table = state.table
        seats = state.seats.enumerated().map { i, s in
            Seat(cat: s.cat, phase: s.phase, bot: s.bot, me: s.me, glowing: i == state.turn)
        }
        bell = state.mine
        leadingCat = (state.seats.first { $0.me } ?? state.seats.first)?.cat ?? 0
        let mover = state.turn.flatMap { state.seats.indices.contains($0) ? state.seats[$0] : nil }
        if state.mine {
            trailing = .bell
        } else if let mover {
            trailing = .cat(mover.cat, bot: mover.bot)
        } else {
            trailing = .none
        }
        paws = state.streak.map { p in
            Paws(count: p.count, lit: p.me && p.them ? .both : (p.me || p.them ? .one : .none))
        }
        if state.mine {
            spoken = "\(state.table). Your move."
        } else if let mover {
            spoken = "\(state.table). \(mover.name ?? Self.botName)'s move."
        } else {
            spoken = "\(state.table)."
        }
    }
}

/// The live table's push tokens (spec §11.3, §14.1): the push-to-start token and each activity's
/// update token go up only from a teen's or an adult's device, as the widget token does. A kitten's
/// device, or one whose age isn't known yet, never sends one.
public enum LiveTableToken {
    public typealias Uploaded = WidgetPushToken.Uploaded

    public static func uploads(band: AgeBand?) -> Bool { WidgetPushToken.uploads(band: band) }

    public static func needsUpload(token: String?, deviceId: String?, last: Uploaded?, band: AgeBand?) -> Bool {
        WidgetPushToken.needsUpload(token: token, deviceId: deviceId, last: last, band: band)
    }
}

/// Which live tables the app ends itself (spec §11.3): the one for a table you just opened, every
/// one when the toggle is off, any past its stale date (a teen's night, a missed end), and all
/// but the newest (at most one per device). Newest is the latest stale date, which the server
/// moves on every update; a local one with none counts as newest.
public enum LiveTableSweep {
    public struct Item: Equatable, Sendable {
        public let id: String
        public let code: String
        public let stale: Date?

        public init(id: String, code: String, stale: Date?) {
            self.id = id
            self.code = code
            self.stale = stale
        }
    }

    public static func toEnd(_ items: [Item], entering code: String?, liveOn: Bool, now: Date) -> [String] {
        guard liveOn else { return items.map(\.id) }
        var end = items.filter { $0.code == code || ($0.stale.map { $0 <= now } ?? false) }.map(\.id)
        let kept = items.filter { !end.contains($0.id) }
        let newest = kept.max { ($0.stale ?? .distantFuture) < ($1.stale ?? .distantFuture) }
        end += kept.filter { $0.id != newest?.id }.map(\.id)
        return end
    }
}
