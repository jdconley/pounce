/// Why the lobby's Start can't deal yet, for the words under the rug.
public enum StartBlock: Equatable, Sendable {
    /// This phone holds no seat: only a seated phone starts the game.
    case notSeated
    /// Seats are still open. With `players` of two or more, Start can close them and deal.
    case openSeats(open: Int, players: Int)
    /// Fewer than two cats (people or House Cats) and no open seat anyone could take.
    case notEnoughPlayers(players: Int)
}

extension TableModel {
    /// The fewest cats a game needs.
    public static let minPlayers = 2

    /// Seats with a person or a House Cat in them.
    public var playerCount: Int {
        room.seats.filter { $0.kind == .human || $0.kind == .bot }.count
    }

    /// What stops Start, or nil when it deals (`canStart`). Only meaningful in the lobby.
    public var startBlock: StartBlock? {
        guard room.status == .lobby else { return nil }
        if mySeats.isEmpty { return .notSeated }
        let open = blockingSeats.count
        if open > 0 { return .openSeats(open: open, players: playerCount) }
        return playerCount < Self.minPlayers ? .notEnoughPlayers(players: playerCount) : nil
    }

    /// Start with the cats already here: closes every open seat, then starts. Nil unless open
    /// seats are the only thing in the way (two or more cats are seated). If someone takes one
    /// of those seats first, the server refuses that close and deals them in.
    public var startClosingOpenSeats: [ClientMessage]? {
        guard case .openSeats(_, let players) = startBlock, players >= Self.minPlayers else { return nil }
        return blockingSeats.map { .configure(seat: $0, kind: .closed) } + [.start]
    }

    /// The seat "Add a player" opens the choices for: the first open seat, else the first
    /// closed one. Nil when every seat is taken, or outside the lobby.
    public var seatToAdd: Seat? {
        guard room.status == .lobby else { return nil }
        return room.seats.firstIndex { $0.kind == .open } ?? room.seats.firstIndex { $0.kind == .closed }
    }

    /// A practice game against the House Cat: puts a House Cat in the first free seat, closes the
    /// other open seats and starts. Nil unless this phone is seated in the lobby and nobody else
    /// (no person on another phone, no House Cat) is at the table yet.
    public var practiceMessages: [ClientMessage]? {
        guard room.status == .lobby, !mySeats.isEmpty,
              !room.seats.contains(where: { $0.kind == .bot || ($0.kind == .human && !$0.yours) }),
              let seat = seatToAdd else { return nil }
        let others = blockingSeats.filter { $0 != seat }
        return [.configure(seat: seat, kind: .bot)] + others.map { .configure(seat: $0, kind: .closed) } + [.start]
    }
}
