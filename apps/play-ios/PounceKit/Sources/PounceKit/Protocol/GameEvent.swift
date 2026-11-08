import Foundation

/// A game event as broadcast by the server (discriminator key `kind`).
public enum GameEvent: Codable, Equatable, Sendable {
    case roundStarted(round: Int, dealer: Seat)
    /// `card` is absent when another seat drew from the deck.
    case drew(seat: Seat, from: DrawSource, card: CardID?)
    case laidDown(seat: Seat, groups: [Group])
    case hit(seat: Seat, card: CardID, target: HitTarget, group: Group)
    case discarded(seat: Seat, card: CardID, skipTarget: Seat?)
    case skipped(seat: Seat)
    case turn(seat: Seat)
    case reshuffled(deckCount: Int)
    /// `seat` left the game for good (§5.10). A game it leaves with one seat in ends with `gameOver` next.
    case forfeited(seat: Seat)
    case roundOver(wentOut: Seat?, points: [Int], advanced: [Seat], scores: [Int], phase: [Int])
    case gameOver(winners: [Seat])

    private enum CodingKeys: String, CodingKey {
        case kind, round, dealer, seat, from, card, groups, target, group, skipTarget
        case deckCount, wentOut, points, advanced, scores, phase, winners
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "roundStarted":
            self = .roundStarted(round: try c.decode(Int.self, forKey: .round),
                                 dealer: try c.decode(Seat.self, forKey: .dealer))
        case "drew":
            self = .drew(seat: try c.decode(Seat.self, forKey: .seat),
                         from: try c.decode(DrawSource.self, forKey: .from),
                         card: try c.decodeIfPresent(CardID.self, forKey: .card))
        case "laidDown":
            self = .laidDown(seat: try c.decode(Seat.self, forKey: .seat),
                             groups: try c.decode([Group].self, forKey: .groups))
        case "hit":
            self = .hit(seat: try c.decode(Seat.self, forKey: .seat),
                        card: try c.decode(CardID.self, forKey: .card),
                        target: try c.decode(HitTarget.self, forKey: .target),
                        group: try c.decode(Group.self, forKey: .group))
        case "discarded":
            self = .discarded(seat: try c.decode(Seat.self, forKey: .seat),
                              card: try c.decode(CardID.self, forKey: .card),
                              skipTarget: try c.decodeIfPresent(Seat.self, forKey: .skipTarget))
        case "skipped":
            self = .skipped(seat: try c.decode(Seat.self, forKey: .seat))
        case "turn":
            self = .turn(seat: try c.decode(Seat.self, forKey: .seat))
        case "reshuffled":
            self = .reshuffled(deckCount: try c.decode(Int.self, forKey: .deckCount))
        case "forfeited":
            self = .forfeited(seat: try c.decode(Seat.self, forKey: .seat))
        case "roundOver":
            self = .roundOver(wentOut: try c.decodeIfPresent(Seat.self, forKey: .wentOut),
                              points: try c.decode([Int].self, forKey: .points),
                              advanced: try c.decode([Seat].self, forKey: .advanced),
                              scores: try c.decode([Int].self, forKey: .scores),
                              phase: try c.decode([Int].self, forKey: .phase))
        case "gameOver":
            self = .gameOver(winners: try c.decode([Seat].self, forKey: .winners))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "unknown game event kind: \(kind)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .roundStarted(let round, let dealer):
            try c.encode("roundStarted", forKey: .kind)
            try c.encode(round, forKey: .round)
            try c.encode(dealer, forKey: .dealer)
        case .drew(let seat, let from, let card):
            try c.encode("drew", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(from, forKey: .from)
            try c.encodeIfPresent(card, forKey: .card)
        case .laidDown(let seat, let groups):
            try c.encode("laidDown", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(groups, forKey: .groups)
        case .hit(let seat, let card, let target, let group):
            try c.encode("hit", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(card, forKey: .card)
            try c.encode(target, forKey: .target)
            try c.encode(group, forKey: .group)
        case .discarded(let seat, let card, let skipTarget):
            try c.encode("discarded", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(card, forKey: .card)
            try c.encodeIfPresent(skipTarget, forKey: .skipTarget)
        case .skipped(let seat):
            try c.encode("skipped", forKey: .kind)
            try c.encode(seat, forKey: .seat)
        case .turn(let seat):
            try c.encode("turn", forKey: .kind)
            try c.encode(seat, forKey: .seat)
        case .reshuffled(let deckCount):
            try c.encode("reshuffled", forKey: .kind)
            try c.encode(deckCount, forKey: .deckCount)
        case .forfeited(let seat):
            try c.encode("forfeited", forKey: .kind)
            try c.encode(seat, forKey: .seat)
        case .roundOver(let wentOut, let points, let advanced, let scores, let phase):
            try c.encode("roundOver", forKey: .kind)
            try c.encode(wentOut, forKey: .wentOut)  // null when nobody went out
            try c.encode(points, forKey: .points)
            try c.encode(advanced, forKey: .advanced)
            try c.encode(scores, forKey: .scores)
            try c.encode(phase, forKey: .phase)
        case .gameOver(let winners):
            try c.encode("gameOver", forKey: .kind)
            try c.encode(winners, forKey: .winners)
        }
    }
}

/// An `event` payload: a presence change or a wrapped game event.
public enum RoomEvent: Codable, Equatable, Sendable {
    case presence(seat: Seat, presence: Presence)
    case game(GameEvent)
    /// Someone at the table changed its rug or card back (§9.4); `look` is the whole new look.
    case look(seat: Seat, look: Look)

    private enum CodingKeys: String, CodingKey { case kind, seat, presence, event, rug, back }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "presence":
            self = .presence(seat: try c.decode(Seat.self, forKey: .seat),
                             presence: try c.decode(Presence.self, forKey: .presence))
        case "game":
            self = .game(try c.decode(GameEvent.self, forKey: .event))
        case "look":
            self = .look(seat: try c.decode(Seat.self, forKey: .seat),
                         look: Look(rug: try c.decode(String.self, forKey: .rug), back: try c.decode(String.self, forKey: .back)))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "unknown room event kind: \(kind)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .presence(let seat, let presence):
            try c.encode("presence", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(presence, forKey: .presence)
        case .game(let event):
            try c.encode("game", forKey: .kind)
            try c.encode(event, forKey: .event)
        case .look(let seat, let look):
            try c.encode("look", forKey: .kind)
            try c.encode(seat, forKey: .seat)
            try c.encode(look.rug, forKey: .rug)
            try c.encode(look.back, forKey: .back)
        }
    }
}
