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
