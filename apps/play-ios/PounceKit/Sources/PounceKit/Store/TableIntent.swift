import Foundation

/// What the table scene should animate next, in server order.
public enum TableIntent: Equatable, Sendable {
    /// Redraw from `RoomStore.room` (after every snapshot).
    case reconcile
    /// The lobby just became a game: play the versus intro before dealing.
    case versusIntro
    /// Animate one game event; `room` already holds what the event carries.
    case game(GameEvent, seq: Int)
    case presence(seat: Seat, presence: Presence)
    /// The in-flight `act` was refused: snap the provisional move back and wiggle.
    case rejected(ErrorCode)
    /// A lobby message was refused: wiggle the control tapped last.
    case lobbyNope(ErrorCode)
}

/// Which screen the room is on.
public enum RoomPhase: Equatable, Sendable {
    case connecting, lobby, playing, over, closed, notFound, needsUpdate, stalled
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
