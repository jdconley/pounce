/// The names a table shows for its seats.
public enum SeatNames {
    /// Every seat's name as the table shows it: the person's name; a bot's is `bot`, numbered
    /// ("House Cat 2", "House Cat 3") when more than one bot sits; "" for open and closed seats.
    public static func names(_ seats: [SeatView], bot: String) -> [String] {
        let bots = seats.filter { $0.kind == .bot }.count
        var botNumber = 0
        return seats.map { seat in
            switch seat.kind {
            case .human:
                return seat.person?.name ?? ""
            case .bot:
                botNumber += 1
                return bots > 1 && botNumber > 1 ? "\(bot) \(botNumber)" : bot
            case .open, .closed:
                return ""
            }
        }
    }
}

/// Keeps the names in this device's seats in step with the people on this phone, so a rename
/// in the People sheet or the table menu reaches every phone at the table: the server takes
/// `rename` in the lobby and mid-game, and everyone's next snapshot carries the new name.
public struct NameSync: Equatable, Sendable {
    /// The name last sent per seat, so a rename waiting on its snapshot (or refused) goes once.
    private var sent: [Seat: String] = [:]

    public init() {}

    /// The renames to send for `model`: one per seat of mine whose person is on this phone
    /// under another name. Nothing once the room is over (the server refuses it then).
    public mutating func renames(_ model: TableModel, people: [Person]) -> [ClientMessage] {
        guard model.room.status != .over else { return [] }
        var out: [ClientMessage] = []
        for seat in model.mySeats {
            guard let shown = model.room.seats[seat].person,
                  let local = people.first(where: { $0.id == shown.id }) else { continue }
            if local.name == shown.name {
                sent[seat] = nil
            } else if sent[seat] != local.name {
                sent[seat] = local.name
                out.append(.rename(seat: seat, name: local.name))
            }
        }
        return out
    }
}
