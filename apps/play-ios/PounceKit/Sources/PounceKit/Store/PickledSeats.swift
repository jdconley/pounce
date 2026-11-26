/// "Pickled": a seat a Cucumber skips. Its cat says so from the moment the Cucumber
/// is aimed at it until the turn played in its place is over. The server's `pendingSkip` covers
/// the wait; it clears as the seat is passed over, often in the very move that aimed it (at the
/// next seat), so the game's `skipped` and `turn` events say whose turn replaced it, and the
/// mark stays through that turn. Fed every Cat Tower event as the table plays it, on the phone
/// and on the TV.
public struct PickledSeats: Equatable, Sendable {
    /// A seat passed over, and the turn played instead (nil until its `turn` event).
    private struct Served: Equatable, Sendable {
        let round: Int
        var turn: Seat?
    }

    private var served: [Seat: Served] = [:]
    /// Seats a Cucumber was just discarded at, by round, until they are passed over: the mark
    /// shows as the discard plays, before the snapshot with `pendingSkip` arrives.
    private var aimed: [Seat: Int] = [:]
    /// The latest round a `roundStarted` dealt: its events play before its snapshot arrives.
    private var dealt: Int?

    public init() {}

    /// Notes `event`, played over a table in `round`.
    public mutating func note(_ event: GameEvent, round: Int) {
        switch event {
        case .roundStarted(let next, _):
            served = [:]
            aimed = [:]
            dealt = next
        case .discarded(_, _, let target?):
            aimed[target] = max(dealt ?? round, round)
        case .skipped(let seat):
            aimed[seat] = nil
            served[seat] = Served(round: max(dealt ?? round, round), turn: nil)
        case .turn(let seat):
            for (skipped, entry) in served {
                if let turn = entry.turn {
                    if turn != seat { served[skipped] = nil }
                } else {
                    served[skipped]?.turn = seat
                }
            }
        case .forfeited(let seat):
            served[seat] = nil
            aimed[seat] = nil
        case .roundOver, .gameOver:
            served = [:]
            aimed = [:]
        case .drew, .laidDown, .hit, .discarded, .reshuffled:
            break
        }
    }

    /// The pickled seats in `game` as drawn: skips still waiting, and seats whose replacing turn
    /// is the one being played. None outside play, and never a seat that forfeited.
    public func seats(in game: GameView) -> Set<Seat> {
        guard game.status == .playing else { return [] }
        var seats = Set(game.pendingSkip.indices.filter { game.pendingSkip[$0] })
        for (seat, round) in aimed where round == game.round { seats.insert(seat) }
        for (seat, entry) in served where entry.round == game.round && (entry.turn ?? game.turn) == game.turn {
            seats.insert(seat)
        }
        return seats.filter { !game.isOut($0) }
    }
}
