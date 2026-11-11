import Foundation

/// What the table scene should animate next, in server order.
public enum TableIntent: Equatable, Sendable {
    /// Redraw from `RoomStore.room` (after every snapshot).
    case reconcile
    /// The lobby just became a game: play the versus intro before dealing.
    case versusIntro
    /// Animate one game event. Events only animate: `room` folds in just the turn,
    /// step and status they imply, for timing. The snapshot the server sends after
    /// every action, at the same seq as its last event, carries the truth (drawn
    /// cards, discard top, counts, a finished room) and follows as `.reconcile`.
    case game(GameEvent, seq: Int)
    case presence(seat: Seat, presence: Presence)
    /// Some seat's connection quality changed (`SeatView.link`): redraw the seats.
    case link
    /// The in-flight `act` was refused: snap the provisional move back and wiggle.
    case rejected(ErrorCode)
    /// A lobby message was refused: wiggle the control tapped last.
    case lobbyNope(ErrorCode)
}

/// Which screen the room is on.
public enum RoomPhase: Equatable, Sendable {
    case connecting, lobby, playing, over, closed, notFound, needsUpdate, stalled
    /// The server refused the connection: too many wrong room codes lately.
    case locked
}

/// A move code for handing `seat` to another device.
public struct MoveCode: Equatable, Sendable {
    public let seat: Seat
    public let code: String

    public init(seat: Seat, code: String) {
        self.seat = seat
        self.code = code
    }
}
