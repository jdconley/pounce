/// What VoiceOver announces for a game event (spec §13: "turn changes and big events post
/// announcements"). The app turns these into short localized sentences.
public enum TableAnnouncement: Equatable, Sendable {
    public struct SeatPoints: Equatable, Sendable {
        public let seat: Seat
        public let points: Int
        public init(seat: Seat, points: Int) {
            self.seat = seat
            self.points = points
        }
    }

    /// One of this phone's seats is up. On a multi-seat phone the sentence names the seat.
    case yourTurn(seat: Seat, multiSeat: Bool)
    /// The round ended: the points each of this phone's seats took (none on a seatless phone).
    case roundOver(mine: [SeatPoints])
    /// The game ended: who won (several on a tie).
    case gameOver(winners: [Seat])
    /// `seat` forfeited (§5.13); `mine` when it is one of this phone's.
    case forfeited(seat: Seat, mine: Bool)

    /// The announcement for `event` on the table `model` shows, or nil (most events are only
    /// seen: another seat's turn, draws, discards).
    public static func announcement(for event: GameEvent, model: TableModel) -> TableAnnouncement? {
        switch event {
        case .turn(let seat):
            guard model.mySeats.contains(seat) else { return nil }
            return .yourTurn(seat: seat, multiSeat: model.isMultiSeat)
        case .roundOver(_, let points, _, _, _):
            let mine = model.mySeats.filter(points.indices.contains).map { SeatPoints(seat: $0, points: points[$0]) }
            return .roundOver(mine: mine)
        case .gameOver(let winners):
            return .gameOver(winners: winners)
        case .forfeited(let seat):
            return .forfeited(seat: seat, mine: model.mySeats.contains(seat))
        default:
            return nil
        }
    }
}
