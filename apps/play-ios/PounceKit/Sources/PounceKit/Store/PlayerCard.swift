/// What the player card shows for one seat (tap a cat in the table's top bar): who plays there,
/// where they are in the game, and, for a person, whether you're connected and your streak.
public struct PlayerCard: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A House Cat.
        case bot
        /// Someone on this phone (a shared phone's other seat).
        case here
        /// Someone on their own phone, with their presence when the server sent one.
        case away(Presence?)
    }

    public enum Connection: Equatable, Sendable {
        /// No row: a bot, or streaks are off (or not answered yet).
        case none
        /// Connected: the pair's streak as `person` on this phone sees it.
        case connected(person: String, view: StreakView)
        /// A person nobody on this phone is connected with yet. Playing makes the connection:
        /// once both of you take a turn at a table (§6.1).
        case notYet
    }

    public let seat: Seat
    public let person: Person?
    public let kind: Kind
    /// 0 = phase 1; `Rules.phases.count` once every phase is done.
    public let phase: Int
    public let cards: Int?
    public let score: Int
    /// Laid this round's phase down.
    public let laid: Bool
    /// A skip waits on this seat.
    public let skipped: Bool
    public let isTurn: Bool
    public let connection: Connection

    /// The phase in plain words, nil once every phase is done.
    public var phaseText: String? {
        Rules.phases.indices.contains(phase) ? Rules.describe(phase: phase) : nil
    }

    /// The card for `seat` of `model`, or nil for a seat the game doesn't have.
    ///
    /// `streaks` is every pair of this phone's seated people (top pair first, the phone's owner
    /// first), nil while streaks are off. A pair is this seat's when its partner has the seat's
    /// name and cat; when they changed either since, a pair that played at this table (one of its
    /// moves, or a streak message this table's socket brought, `reported`) still is when this
    /// seat is the table's only other person.
    public static func make(
        model: TableModel, seat: Seat, streaks: [(person: String, view: StreakView)]?, reported: Set<String> = []
    ) -> PlayerCard? {
        guard let game = model.game, game.phase.indices.contains(seat), let view = model.room.seats[safe: seat]
        else { return nil }
        let kind: Kind = view.kind == .bot ? .bot : (view.yours ? .here : .away(view.presence))
        return PlayerCard(
            seat: seat, person: view.kind == .bot ? nil : view.person, kind: kind,
            phase: min(max(game.phase[seat], 0), Rules.phases.count),
            cards: game.handCounts[safe: seat],
            score: game.scores[safe: seat] ?? 0,
            laid: (game.laid[safe: seat] ?? nil) != nil,
            skipped: game.pendingSkip[safe: seat] ?? false,
            isTurn: game.status == .playing && game.turn == seat,
            connection: connection(model: model, seat: seat, streaks: streaks, reported: reported))
    }

    static func connection(
        model: TableModel, seat: Seat, streaks: [(person: String, view: StreakView)]?, reported: Set<String>
    ) -> Connection {
        guard let streaks, let view = model.room.seats[safe: seat], view.kind == .human, let them = view.person
        else { return .none }
        // Their own pairs (a shared phone's other seat) never count: a pair needs two people.
        let mine = streaks.filter { $0.person != them.id }
        if let exact = mine.first(where: { $0.view.partner.name == them.name && $0.view.partner.cat == them.cat }) {
            return .connected(person: exact.person, view: exact.view)
        }
        let code = model.room.code
        let others = model.room.seats.indices.filter { i in
            i != seat && !model.mySeats.contains(i) && model.room.seats[i].kind == .human
        }
        if others.isEmpty, !view.yours, let here = mine.first(where: {
            $0.view.myMove.contains(code) || $0.view.theirMove.contains(code) || reported.contains($0.view.pair)
        }) {
            return .connected(person: here.person, view: here.view)
        }
        return .notYet
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
