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
    // Sent to the whole room, unprompted.
    public static let botStalled = ErrorCode(rawValue: "bot_stalled")
    public static let roomClosed = ErrorCode(rawValue: "room_closed")
}

/// Server to client (discriminator key `t`).
public enum ServerMessage: Decodable, Equatable, Sendable {
    case snapshot(protocol: Int, seq: Int, room: RoomView)
    case event(seq: Int, event: RoomEvent)
    case moveCode(seat: Seat, code: String)
    case error(ErrorCode)

    private enum CodingKeys: String, CodingKey { case t, `protocol`, seq, room, event, seat, code }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "snapshot":
            self = .snapshot(protocol: try c.decode(Int.self, forKey: .protocol),
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
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .t, in: c, debugDescription: "unknown server message type: \(t)")
        }
    }
}

/// A move inside a game (discriminator key `type`). `skipTarget` is omitted when nil.
public enum Action: Encodable, Equatable, Sendable {
    case draw(DrawSource)
    case layDown([LayGroup])
    case hit(card: CardID, target: HitTarget)
    case discard(card: CardID, skipTarget: Seat?)
    case nextRound

    private enum CodingKeys: String, CodingKey { case type, from, groups, card, target, skipTarget }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .draw(let source):
            try c.encode("draw", forKey: .type)
            try c.encode(source, forKey: .from)
        case .layDown(let groups):
            try c.encode("layDown", forKey: .type)
            try c.encode(groups, forKey: .groups)
        case .hit(let card, let target):
            try c.encode("hit", forKey: .type)
            try c.encode(card, forKey: .card)
            try c.encode(target, forKey: .target)
        case .discard(let card, let skipTarget):
            try c.encode("discard", forKey: .type)
            try c.encode(card, forKey: .card)
            try c.encodeIfPresent(skipTarget, forKey: .skipTarget)
        case .nextRound:
            try c.encode("nextRound", forKey: .type)
        }
    }
}

public enum ConfigureKind: String, Codable, Sendable { case open, bot, closed }
public enum PresenceState: String, Codable, Sendable { case active, background }

/// Client to server (discriminator key `t`).
public enum ClientMessage: Encodable, Equatable, Sendable {
    case claim(seat: Seat, person: Person)
    case configure(seat: Seat, kind: ConfigureKind)
    case start
    case act(seat: Seat, action: Action)
    case presence(PresenceState)
    case moveSeat(seat: Seat)
    case claimMove(code: String)
    case leave(seat: Seat)

    private enum CodingKeys: String, CodingKey { case t, seat, person, kind, action, state, code }

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
        case .act(let seat, let action):
            try c.encode("act", forKey: .t)
            try c.encode(seat, forKey: .seat)
            try c.encode(action, forKey: .action)
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
        }
    }
}
