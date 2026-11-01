/// What a 404 on connect means for the code that was opened.
public enum NotFoundMeaning: Equatable, Sendable {
    /// A typed (or otherwise unknown) code: no such room. Shake the join tiles.
    case badCode
    /// A table this device knew: the server deleted it after it closed. Show "room closed".
    case roomClosed
}

/// Decisions made when a room screen opens (spec §5.4, §5.5, §7.3).
public enum RoomEntry {
    /// The claim that seats the phone's owner when it arrives at a lobby holding no seat:
    /// the first open seat, so an invitee is one tap from the table. Nil outside the lobby,
    /// when this device already holds a seat, or when no seat is open.
    public static func autoClaim(model: TableModel, owner: Person) -> ClientMessage? {
        guard model.room.status == .lobby, model.mySeats.isEmpty, let seat = model.firstOpenSeat else {
            return nil
        }
        return .claim(seat: seat, person: owner)
    }

    /// The server deletes a room when it closes, so a later connect to a table this device
    /// knew (`known`: in the table cache or the last `/tables`) returns 404 too.
    public static func notFoundMeaning(code: String, known: Bool) -> NotFoundMeaning {
        known ? .roomClosed : .badCode
    }
}

/// The auto-claim's life (spec §5.5). The first snapshot's claim is sent once; if the server
/// refuses it (someone took that seat first: `seat_taken`), it is retried once with
/// `RoomEntry.autoClaim` on the next lobby snapshot while this phone still holds no seat.
/// Its refusals answer nobody's tap, so the shell never nopes for them.
public struct AutoClaim: Equatable, Sendable {
    private var started = false
    /// A claim is out and neither a seat nor an error has answered it.
    public private(set) var pending = false
    private var retryDue = false
    private var retried = false

    public init() {}

    /// Called for every snapshot. Returns the claim to send now, if any: `first()` on the
    /// first snapshot (the shell's choice for how the room was opened), later the one retry.
    public mutating func snapshot(
        _ model: TableModel, owner: Person?, first: () -> ClientMessage?
    ) -> ClientMessage? {
        if !model.mySeats.isEmpty {
            pending = false
            retryDue = false
        }
        if !started {
            started = true
            let claim = first()
            if case .claim = claim { pending = true }
            return claim
        }
        guard retryDue, !pending, let owner, let claim = RoomEntry.autoClaim(model: model, owner: owner) else {
            return nil
        }
        retryDue = false
        pending = true
        return claim
    }

    /// A server error arrived. True when it refused the pending auto-claim: the shell must not
    /// nope for it. Room-wide errors (`room_closed`, `bot_stalled`) are never the claim's.
    public mutating func refused(_ code: ErrorCode) -> Bool {
        guard pending, code != .roomClosed, code != .botStalled else { return false }
        pending = false
        if !retried {
            retried = true
            retryDue = true
        }
        return true
    }
}
