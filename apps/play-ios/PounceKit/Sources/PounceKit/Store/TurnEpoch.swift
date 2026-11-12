/// Counts turn changes in a room, so a pass-and-play reveal can name the one turn it was granted
/// for. `value` goes up by one every time an observed room's round, turn, game status or room
/// status differs from the last one observed, and never goes down: two turns of the same seat
/// always have different epochs, however many rooms in between a viewer skipped.
///
/// In a tile game the key is its turn, its count of completed turns and its status instead.
///
/// `RoomStore` observes every room it applies (snapshots and the turn, step and status it folds
/// in from events), so its `turnEpoch` sees every turn even when the SwiftUI shell coalesces
/// several room changes into one update.
public struct TurnEpoch: Equatable, Sendable {
    public private(set) var value = 0
    private var key: Key?

    private struct Key: Equatable, Sendable {
        let roomStatus: RoomStatus
        let round: Int?
        let turn: Seat?
        let status: GameStatus?
        /// The tile game's turn, completed turns and status (all nil in a Cat Tower room).
        var tilesTurn: Seat?
        var tilesTurns: Int?
        var tilesStatus: TilesStatus?
    }

    public init() {}

    public mutating func observe(_ room: RoomView) {
        let next = Key(
            roomStatus: room.status, round: room.game?.round, turn: room.game?.turn, status: room.game?.status,
            tilesTurn: room.tiles?.turn, tilesTurns: room.tiles?.turns, tilesStatus: room.tiles?.status)
        guard next != key else { return }
        key = next
        value += 1
    }
}
