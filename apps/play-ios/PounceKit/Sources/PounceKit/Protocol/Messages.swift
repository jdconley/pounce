import Foundation

/// A server `error` code. Unknown strings are preserved, never rejected.
public struct ErrorCode: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // Any message.
    public static let badMessage = ErrorCode(rawValue: "bad_message")
    public static let `internal` = ErrorCode(rawValue: "internal")
    /// A person's or a table's name the server's name filter refuses (or, from a kitten's device,
    /// one the dice didn't roll).
    public static let badName = ErrorCode(rawValue: "bad_name")
    /// Not for this device: a kitten renaming the table.
    public static let notAllowed = ErrorCode(rawValue: "not_allowed")
    /// The table's host blocked this player, so the seat is refused.
    public static let blocked = ErrorCode(rawValue: "blocked")
    // Lobby and seats.
    public static let notLobby = ErrorCode(rawValue: "not_lobby")
    public static let inGame = ErrorCode(rawValue: "in_game")
    public static let badSeat = ErrorCode(rawValue: "bad_seat")
    public static let seatTaken = ErrorCode(rawValue: "seat_taken")
    public static let personSeated = ErrorCode(rawValue: "person_seated")
    public static let notSeated = ErrorCode(rawValue: "not_seated")
    public static let notYourSeat = ErrorCode(rawValue: "not_your_seat")
    public static let seatsOpen = ErrorCode(rawValue: "seats_open")
    public static let notEnoughPlayers = ErrorCode(rawValue: "not_enough_players")
    // Moving a seat to another device.
    public static let gameOver = ErrorCode(rawValue: "game_over")
    public static let badCode = ErrorCode(rawValue: "bad_code")
    public static let tooManyAttempts = ErrorCode(rawValue: "too_many_attempts")
    // Playing.
    public static let notPlaying = ErrorCode(rawValue: "not_playing")
    public static let notYourTurn = ErrorCode(rawValue: "not_your_turn")
    public static let badStep = ErrorCode(rawValue: "bad_step")
    public static let badCard = ErrorCode(rawValue: "bad_card")
    public static let badGroups = ErrorCode(rawValue: "bad_groups")
    public static let alreadyLaid = ErrorCode(rawValue: "already_laid")
    public static let notLaid = ErrorCode(rawValue: "not_laid")
    public static let badTarget = ErrorCode(rawValue: "bad_target")
    public static let emptyDiscard = ErrorCode(rawValue: "empty_discard")
    public static let cucumberFromDiscard = ErrorCode(rawValue: "cucumber_from_discard")
    public static let roundNotOver = ErrorCode(rawValue: "round_not_over")
    /// The seat already forfeited (§5.13).
    public static let forfeited = ErrorCode(rawValue: "forfeited")
    // The tile game (tile game spec §8). It shares `notYourTurn`, `forfeited`, `badSeat` and `gameOver`.
    /// Not one of the game's actions.
    public static let badAction = ErrorCode(rawValue: "bad_action")
    /// A draw with nothing left in the toy box.
    public static let poolEmpty = ErrorCode(rawValue: "pool_empty")
    /// A pass while the toy box still has pieces.
    public static let poolNotEmpty = ErrorCode(rawValue: "pool_not_empty")
    /// The submitted rug is not a list of sets of piece ids.
    public static let badPiece = ErrorCode(rawValue: "bad_piece")
    public static let duplicatePiece = ErrorCode(rawValue: "duplicate_piece")
    /// A piece that was on the rug is not on the submitted rug.
    public static let missingPiece = ErrorCode(rawValue: "missing_piece")
    public static let notYourPiece = ErrorCode(rawValue: "not_your_piece")
    public static let nothingPlayed = ErrorCode(rawValue: "nothing_played")
    /// A set on the submitted rug is not a row or a match.
    public static let badSet = ErrorCode(rawValue: "bad_set")
    /// Before opening: a set that was on the rug was changed.
    public static let tableTouched = ErrorCode(rawValue: "table_touched")
    /// Before opening: the new sets are worth less than 30.
    public static let openingTooLow = ErrorCode(rawValue: "opening_too_low")
    /// Play again at a tile game table after the server stopped dealing that game: no new table
    /// can be dealt. Never sent at a Cat Tower table.
    public static let gameOff = ErrorCode(rawValue: "game_off")
    // Birdwatch.
    /// A move outside its phase (a bid while playing, a card while bidding).
    public static let wrongPhase = ErrorCode(rawValue: "wrong_phase")
    public static let bidTooLow = ErrorCode(rawValue: "bid_too_low")
    public static let bidTooHigh = ErrorCode(rawValue: "bid_too_high")
    /// A bid that isn't a multiple of 5.
    public static let badBid = ErrorCode(rawValue: "bad_bid")
    public static let notYourCard = ErrorCode(rawValue: "not_your_card")
    /// A put-back of the wrong number of cards.
    public static let wrongCount = ErrorCode(rawValue: "wrong_count")
    public static let duplicateCard = ErrorCode(rawValue: "duplicate_card")
    /// A partner call for a card the bid winner holds.
    public static let ownCard = ErrorCode(rawValue: "own_card")
    /// A card off the led suit while the hand still holds that suit.
    public static let mustFollow = ErrorCode(rawValue: "must_follow")
    // Table looks and Play again (daily habit §9.4, §10.4).
    /// Play again before the game is over.
    public static let notOver = ErrorCode(rawValue: "not_over")
    /// A second look change from this device within 10 s.
    public static let tooSoon = ErrorCode(rawValue: "too_soon")
    /// A rug or back the setter hasn't unlocked.
    public static let notUnlocked = ErrorCode(rawValue: "not_unlocked")
    // Nudges (`tooSoon` too: the wait or the cooldown isn't over, or this turn's is sent).
    /// A nudge to a seat that doesn't hold the move.
    public static let notTheirTurn = ErrorCode(rawValue: "not_their_turn")
    // Sent to the whole room, unprompted.
    public static let botStalled = ErrorCode(rawValue: "bot_stalled")
    public static let roomClosed = ErrorCode(rawValue: "room_closed")
    // Local only, never sent by the server.
    /// An `act` whose send failed (the socket was down): it never reached the server.
    public static let notSent = ErrorCode(rawValue: "local_not_sent")
}

/// Server to client (discriminator key `t`).
public enum ServerMessage: Decodable, Equatable, Sendable {
    case snapshot(protocol: Int, seq: Int, room: RoomView)
    /// A snapshot from a protocol this client doesn't speak (anything but 1). Its
    /// room is never decoded, since a future shape may not parse; the app asks for an update.
    case unsupportedProtocol(Int)
    case event(seq: Int, event: RoomEvent)
    case moveCode(seat: Seat, code: String)
    case error(ErrorCode)
    /// A pair's new streak view for one person on this device, after a turn (§9.5).
    case streak(pair: String, person: String, view: StreakView)
    /// Play again dealt the next table under this code (§10.4).
    case rematch(code: String)
    /// The answer to `ClientMessage.ping`.
    case pong
    /// Every seat's link (nil: fine) whenever one changes. Not a state change: no seq.
    case link(seats: [SeatLink?])
    /// To this phone: its nudge to `seat` went. Not a state change: no seq.
    case nudgeSent(seat: Seat)
    /// To the phones of the person in `seat`: the person in `from` nudged them. No seq.
    case nudged(seat: Seat, from: Seat)
    /// Where `seat`'s player is pointing now, relayed to every other device; nil: cleared. Not a
    /// state change: no seq, never replayed. An app that predates it skips the unknown type.
    case aim(seat: Seat, aim: GameAim?)
    /// Toy Tumble's live stream (`docs/live-protocol.md`): relays, hits, syncs and seat links. Not
    /// room state: no seq. An app that predates it skips the unknown types.
    case tumble(TumbleMessage)

    private enum CodingKeys: String, CodingKey { case t, `protocol`, seq, room, event, seat, code, pair, person, view, seats, from, aim }
    enum TumbleKeys: String, CodingKey { case r, s, q, ev, id, from, to, k, x, boxes, st }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "snapshot":
            let version = try c.decode(Int.self, forKey: .protocol)
            guard version == PounceKit.protocolVersion else {
                self = .unsupportedProtocol(version)
                return
            }
            self = .snapshot(protocol: version,
                             seq: try c.decode(Int.self, forKey: .seq),
                             room: try c.decode(RoomView.self, forKey: .room))
        case "event":
            self = .event(seq: try c.decode(Int.self, forKey: .seq),
                          event: try c.decode(RoomEvent.self, forKey: .event))
        case "moveCode":
            self = .moveCode(seat: try c.decode(Seat.self, forKey: .seat),
                             code: try c.decode(String.self, forKey: .code))
        case "error":
            self = .error(try c.decode(ErrorCode.self, forKey: .code))
        case "streak":
            self = .streak(pair: try c.decode(String.self, forKey: .pair),
                           person: try c.decode(String.self, forKey: .person),
                           view: try c.decode(StreakView.self, forKey: .view))
        case "rematch":
            self = .rematch(code: try c.decode(String.self, forKey: .code))
        case "pong":
            self = .pong
        case "link":
            self = .link(seats: try c.decode([SeatLink?].self, forKey: .seats))
        case "nudgeSent":
            self = .nudgeSent(seat: try c.decode(Seat.self, forKey: .seat))
        case "nudged":
            self = .nudged(seat: try c.decode(Seat.self, forKey: .seat), from: try c.decode(Seat.self, forKey: .from))
        case "aim":
            self = .aim(seat: try c.decode(Seat.self, forKey: .seat),
                        aim: try c.decodeIfPresent(GameAim.self, forKey: .aim))
        case "tumble":
            let k = try decoder.container(keyedBy: TumbleKeys.self)
            self = .tumble(.relay(TumbleRelay(
                r: try k.decode(Int.self, forKey: .r), s: try k.decode(Int.self, forKey: .s), q: try k.decode(Int.self, forKey: .q),
                ev: try k.decode([TumbleEvent].self, forKey: .ev))))
        case "tumbleHit":
            self = .tumble(.hit(try TumbleHitWire(from: try decoder.container(keyedBy: TumbleKeys.self))))
        case "tumbleSync":
            let k = try decoder.container(keyedBy: TumbleKeys.self)
            self = .tumble(.sync(TumbleSync(r: try k.decode(Int.self, forKey: .r), boxes: try k.decode([TumbleBoxSync].self, forKey: .boxes))))
        case "tumbleSeat":
            let k = try decoder.container(keyedBy: TumbleKeys.self)
            self = .tumble(.seat(TumbleSeat(
                r: try k.decode(Int.self, forKey: .r), s: try k.decode(Int.self, forKey: .s), st: try k.decode(TumbleSeat.State.self, forKey: .st))))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .t, in: c, debugDescription: "unknown server message type: \(t)")
        }
    }
}

/// What a player points at, live, for the TV: Cat Tower's laid group, or Tuna Tiles' draft of the
/// whole table (docs/tv-protocol.md, `aim`).
public enum GameAim: Codable, Equatable, Sendable {
    /// `laid[seat][group]`.
    case target(seat: Seat, group: Int)
    /// The draft table, set by set.
    case table([[TileID]])

    private enum CodingKeys: String, CodingKey { case target, table }
    private enum TargetKeys: String, CodingKey { case seat, group }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.target) {
            let t = try c.nestedContainer(keyedBy: TargetKeys.self, forKey: .target)
            self = .target(seat: try t.decode(Seat.self, forKey: .seat), group: try t.decode(Int.self, forKey: .group))
        } else {
            self = .table(try c.decode([[TileID]].self, forKey: .table))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .target(let seat, let group):
            var t = c.nestedContainer(keyedBy: TargetKeys.self, forKey: .target)
            try t.encode(seat, forKey: .seat)
            try t.encode(group, forKey: .group)
        case .table(let sets):
            try c.encode(sets, forKey: .table)
        }
    }
}

/// A move inside a game (discriminator key `type`). `skipTarget` and `side` are omitted when
/// nil; a hit with no `side` goes where the server's default puts it (a Yarn on a run extends
/// the high end first), so it reads the same to a server that predates `side`.
public enum Action: Encodable, Equatable, Sendable {
    case draw(DrawSource)
    case layDown([LayGroup])
    case hit(card: CardID, target: HitTarget, side: HitSide? = nil)
    case discard(card: CardID, skipTarget: Seat?)
    case nextRound
    /// Leave the game for good (§5.13), on anyone's turn, until it is over.
    case forfeit

    private enum CodingKeys: String, CodingKey { case type, from, groups, card, target, skipTarget, side }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .draw(let source):
            try c.encode("draw", forKey: .type)
            try c.encode(source, forKey: .from)
        case .layDown(let groups):
            try c.encode("layDown", forKey: .type)
            try c.encode(groups, forKey: .groups)
        case .hit(let card, let target, let side):
            try c.encode("hit", forKey: .type)
            try c.encode(card, forKey: .card)
            try c.encode(target, forKey: .target)
            try c.encodeIfPresent(side, forKey: .side)
        case .discard(let card, let skipTarget):
            try c.encode("discard", forKey: .type)
            try c.encode(card, forKey: .card)
            try c.encodeIfPresent(skipTarget, forKey: .skipTarget)
        case .nextRound:
            try c.encode("nextRound", forKey: .type)
        case .forfeit:
            try c.encode("forfeit", forKey: .type)
        }
    }
}

public enum ConfigureKind: String, Codable, Sendable { case open, bot, closed }
/// This phone's own view of its connection, for the other phones (`ClientMessage.link`).
public enum LinkReport: String, Codable, Sendable { case weak, good }
public enum PresenceState: String, Codable, Sendable { case active, background }

/// Client to server (discriminator key `t`).
public enum ClientMessage: Encodable, Equatable, Sendable {
    case claim(seat: Seat, person: Person)
    case configure(seat: Seat, kind: ConfigureKind)
    case start
    /// `id`: the move's id, so a server with links applies it once even if it is sent again
    /// after a reconnect. Omitted when nil (a server without links refuses unknown keys).
    case act(seat: Seat, action: Action, id: String? = nil)
    /// A turn in the tile game: the same `{"t":"act"}` envelope around a `TilesAction`.
    case actTiles(seat: Seat, action: TilesAction, id: String? = nil)
    /// A Birdwatch move: the same envelope around a `BirdAction`.
    case actBirdwatch(seat: Seat, action: BirdAction, id: String? = nil)
    /// Toy Tumble's few room actions (leave the game, the host's Play without), in the `act` envelope.
    case actTumble(seat: Seat, action: TumbleAction)
    /// The host sets the game's options in the lobby (Birdwatch's rule set).
    case setOptions(RoomOptions)
    /// The host swaps two seats in the lobby (Birdwatch's teams follow seat order).
    case swapSeats(Seat, Seat)
    case presence(PresenceState)
    case moveSeat(seat: Seat)
    case claimMove(code: String)
    case leave(seat: Seat)
    /// Names the table (send it `TableName.clean`ed); the host or any seated phone, until game over.
    case rename(name: String)
    /// Renames the person in one of this device's seats, in the lobby or mid-game.
    case renameSeat(seat: Seat, name: String)
    /// Play again, once the room is over (§10.4).
    case rematch
    /// Changes the table's rug or card back (at least one), from the sender's own unlocks (§9.4).
    case setLook(rug: String?, back: String?)
    /// A heartbeat; only to a server with links (its snapshots carry `link`). Encodes exactly
    /// `{"t":"ping"}`, the string the room answers without waking.
    case ping
    /// This phone's link turned weak or good again; only to a server with links.
    case link(LinkReport)
    /// Asks the person in `seat`, whose move it is, to take it; only to a server whose snapshots
    /// carry `nudge` for that seat.
    case nudge(seat: Seat)
    /// Forfeits `seat` for its holder, whose move has waited days; only when the snapshot's
    /// `retire` names that seat with no wait left.
    case retire(seat: Seat)
    /// Live pointing for the TV; nil clears it (`{"t":"aim","seat":n}`).
    case aim(seat: Seat, aim: GameAim?)
    /// Toy Tumble's events for this device's own box, in order (`docs/live-protocol.md`). An
    /// empty `ev` asks for a sync of every box.
    case tumble(r: Int, ev: [TumbleEvent])

    private enum CodingKeys: String, CodingKey { case t, seat, person, kind, action, state, code, name, rug, back, id, aim, options, seats, r, ev }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .claim(let seat, let person):
            try c.encode("claim", forKey: .t)
            try c.encode(seat, forKey: .seat)
            try c.encode(person, forKey: .person)
        case .configure(let seat, let kind):
            try c.encode("configure", forKey: .t)
            try c.encode(seat, forKey: .seat)
            try c.encode(kind, forKey: .kind)
        case .start:
            try c.encode("start", forKey: .t)
        case .act(let seat, let action, let id):
            try c.encode("act", forKey: .t)
            try c.encode(seat, forKey: .seat)
            try c.encode(action, forKey: .action)
            try c.encodeIfPresent(id, forKey: .id)
        case .actTiles(let seat, let action, let id):
            try c.encode("act", forKey: .t)
            try c.encode(seat, forKey: .seat)
            try c.encode(action, forKey: .action)
            try c.encodeIfPresent(id, forKey: .id)
        case .actBirdwatch(let seat, let action, let id):
            try c.encode("act", forKey: .t)
            try c.encode(seat, forKey: .seat)
            try c.encode(action, forKey: .action)
            try c.encodeIfPresent(id, forKey: .id)
        case .actTumble(let seat, let action):
            try c.encode("act", forKey: .t)
            try c.encode(seat, forKey: .seat)
            try c.encode(action, forKey: .action)
        case .setOptions(let options):
            try c.encode("setOptions", forKey: .t)
            try c.encode(options, forKey: .options)
        case .swapSeats(let a, let b):
            try c.encode("swapSeats", forKey: .t)
            try c.encode([a, b], forKey: .seats)
        case .presence(let state):
            try c.encode("presence", forKey: .t)
            try c.encode(state, forKey: .state)
        case .moveSeat(let seat):
            try c.encode("moveSeat", forKey: .t)
            try c.encode(seat, forKey: .seat)
        case .claimMove(let code):
            try c.encode("claimMove", forKey: .t)
            try c.encode(code, forKey: .code)
        case .leave(let seat):
            try c.encode("leave", forKey: .t)
            try c.encode(seat, forKey: .seat)
        case .rename(let name):
            try c.encode("rename", forKey: .t)
            try c.encode(name, forKey: .name)
        case .renameSeat(let seat, let name):
            try c.encode("renameSeat", forKey: .t)
            try c.encode(seat, forKey: .seat)
            try c.encode(name, forKey: .name)
        case .rematch:
            try c.encode("rematch", forKey: .t)
        case .setLook(let rug, let back):
            try c.encode("setLook", forKey: .t)
            try c.encodeIfPresent(rug, forKey: .rug)
            try c.encodeIfPresent(back, forKey: .back)
        case .ping:
            try c.encode("ping", forKey: .t)
        case .link(let report):
            try c.encode("link", forKey: .t)
            try c.encode(report, forKey: .state)
        case .nudge(let seat):
            try c.encode("nudge", forKey: .t)
            try c.encode(seat, forKey: .seat)
        case .retire(let seat):
            try c.encode("retire", forKey: .t)
            try c.encode(seat, forKey: .seat)
        case .aim(let seat, let aim):
            try c.encode("aim", forKey: .t)
            try c.encode(seat, forKey: .seat)
            try c.encodeIfPresent(aim, forKey: .aim)
        case .tumble(let r, let ev):
            try c.encode("tumble", forKey: .t)
            try c.encode(r, forKey: .r)
            try c.encode(ev, forKey: .ev)
        }
    }
}
