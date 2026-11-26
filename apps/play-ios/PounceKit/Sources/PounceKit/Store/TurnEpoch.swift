/// Counts turn changes in a room, so a pass-and-play reveal can name the one turn it was granted
/// for. `value` goes up by one every time an observed room's round, turn, game status or room
/// status differs from the last one observed, and never goes down: two turns of the same seat
/// always have different epochs, however many rooms in between a viewer skipped.
///
/// In a tile game the key is its turn, its count of completed turns and its status instead. In
/// Birdwatch it is the hand, the phase, the seat to act, the cards played and the status.
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
        /// Birdwatch's hand, phase, turn, cards on the sill and status (all nil in other games).
        var birdHand: Int?
        var birdPhase: BirdPhase?
        var birdTurn: Seat?
        var birdTrick: Int?
        var birdStatus: BirdStatus?
        /// Purrtrait's turn key and whether it is over (a word pick and the drawing are one turn).
        var purrTurn: String?
        var purrOver: Bool?
    }

    public init() {}

    public mutating func observe(_ room: RoomView) {
        let next = Key(
            roomStatus: room.status, round: room.game?.round, turn: room.game?.turn, status: room.game?.status,
            tilesTurn: room.tiles?.turn, tilesTurns: room.tiles?.turns, tilesStatus: room.tiles?.status,
            birdHand: room.birdwatch?.hand, birdPhase: room.birdwatch?.phase, birdTurn: room.birdwatch?.turn,
            birdTrick: room.birdwatch.map { $0.played.count }, birdStatus: room.birdwatch?.status,
            purrTurn: room.purrtrait?.turn, purrOver: room.purrtrait.map { $0.phase == .over })
        guard next != key else { return }
        key = next
        value += 1
    }
}
