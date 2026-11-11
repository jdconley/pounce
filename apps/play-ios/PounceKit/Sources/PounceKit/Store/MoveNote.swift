/// Why a move on the table didn't go through, for the one line of words the table shows with
/// the wiggle. Worked out on the phone for a move it never sends (`TableModel.whyNo...`), or
/// from the server's error code for one it refused (`server`).
public enum MoveNote: String, CaseIterable, Equatable, Sendable {
    /// Someone else has the move.
    case notYourTurn
    /// The turn starts by taking a card.
    case drawFirst
    /// A card was already taken this turn.
    case alreadyDrew
    /// The discard pile's top card is a Cucumber: it can't be taken.
    case cucumberOnDiscard
    /// Nothing on the discard pile to take.
    case emptyDiscard
    /// A held card was put on the deck: discards go on the face-up pile.
    case discardOnDeck
    case trayFull
    /// A card can only be added to a laid group once this seat's own level is down.
    case layDownFirst
    /// The card doesn't extend that laid group.
    case noFit
    /// The trays don't hold a whole level yet.
    case notALevel
    case alreadyLaid
    /// Only a Cucumber goes on a cat.
    case cucumberOnly
    /// A Cucumber needs a cat to skip.
    case pickACat
    /// That cat is already skipping its next turn, or is out of the game.
    case catSkipped
    /// A Yarn can't stand at that place in its run.
    case yarnNoFit
    /// The round is over (or the next one hasn't been dealt).
    case roundOver
    /// This seat left the game.
    case forfeited
    /// The move never left the phone.
    case notSent
    /// Anything else the server refused.
    case unknown

    /// The note for a move the server refused.
    public static func server(_ code: ErrorCode) -> MoveNote {
        switch code {
        case .notYourTurn: .notYourTurn
        case .badStep: .drawFirst
        case .badCard: .unknown
        case .badGroups: .notALevel
        case .alreadyLaid: .alreadyLaid
        case .notLaid: .layDownFirst
        case .badTarget: .noFit
        case .emptyDiscard: .emptyDiscard
        case .cucumberFromDiscard: .cucumberOnDiscard
        case .roundNotOver, .notPlaying, .gameOver: .roundOver
        case .forfeited: .forfeited
        case .notSent: .notSent
        default: .unknown
        }
    }
}

extension TableModel {
    /// Why `seat` can't do anything at all right now, or nil when it holds the move.
    private func whyNotActing(_ seat: Seat) -> MoveNote? {
        guard room.status == .playing, let game, game.status == .playing else { return .roundOver }
        if game.isOut(seat) { return .forfeited }
        return game.turn == seat ? nil : .notYourTurn
    }

    /// Why `seat` can't play a card (lay, hit, discard) now; nil when it can.
    public func whyNoPlay(_ seat: Seat) -> MoveNote? {
        if let note = whyNotActing(seat) { return note }
        return canPlay(seat) ? nil : .drawFirst
    }

    /// Why `seat` can't take a card from `source`; nil when it can.
    public func whyNoDraw(_ source: DrawSource, seat: Seat) -> MoveNote? {
        if let note = whyNotActing(seat) { return note }
        guard let game, game.step == .draw else { return .alreadyDrew }
        guard source == .discard else { return nil }
        guard let top = game.discardTop else { return .emptyDiscard }
        return Card.decode(top) == .cucumber ? .cucumberOnDiscard : nil
    }

    /// Why `card` from `seat`'s hand can't be added to the laid group `target`; nil when it can.
    public func whyNoHit(card: CardID, seat: Seat, target: HitTarget) -> MoveNote? {
        if let note = whyNoPlay(seat) { return note }
        guard let game, game.laid.indices.contains(seat), game.laid[seat] != nil else { return .layDownFirst }
        return hitTargets(card: card, seat: seat).contains(target) ? nil : .noFit
    }

    /// Why `card` from `seat`'s hand can't be dropped on the cat at `target`; nil when it can.
    public func whyNoAim(card: CardID, seat: Seat, at target: Seat) -> MoveNote? {
        if let note = whyNoPlay(seat) { return note }
        guard Card.decode(card) == .cucumber else { return .cucumberOnly }
        return skipTargets(for: seat).contains(target) ? nil : .catSkipped
    }

    /// Why `card` from `seat`'s hand can't go on the discard pile with no cat picked; nil when it
    /// can (a Cucumber with nobody left to skip goes out plain).
    public func whyNoDiscard(card: CardID, seat: Seat) -> MoveNote? {
        if let note = whyNoPlay(seat) { return note }
        return Card.decode(card) == .cucumber && !skipTargets(for: seat).isEmpty ? .pickACat : nil
    }
}

/// A discard held back for a moment so a mis-tap can be undone: the card sits on the pile, the
/// table offers Undo, and the action goes to the server when the window closes. Nothing is sent
/// before that, so undoing needs no help from the server and the turn never ends by accident.
public struct DiscardHold: Equatable, Sendable {
    /// How long Undo is offered, at normal speed.
    public static let window: Double = 3

    public let card: CardID
    /// The cat a Cucumber skips.
    public let target: Seat?
    public let seat: Seat
    /// The store's turn epoch when the card was put down.
    public let epoch: Int
    /// Goes up with every hold, so a late timer never fires for a newer one.
    public let serial: Int

    public init(card: CardID, target: Seat?, seat: Seat, epoch: Int, serial: Int) {
        self.card = card
        self.target = target
        self.seat = seat
        self.epoch = epoch
        self.serial = serial
    }

    /// The hold still stands on this table: the same turn, `seat` in its play step with the
    /// card still in hand, and (a Cucumber) the cat still there to skip. Anything else (the
    /// turn moved on, the seat forfeited, the round ended) drops it without sending.
    public func stands(_ model: TableModel, epoch: Int) -> Bool {
        guard epoch == self.epoch, model.canPlay(seat), let game = model.game else { return false }
        if let hand = game.hands[seat], !hand.contains(card) { return false }
        if let target, !model.skipTargets(for: seat).contains(target) { return false }
        return true
    }
}
