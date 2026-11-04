import PounceKit
import SpriteKit
import UIKit

/// Whose turn it is, as the shell's turn overlay (`TurnCueView`) should show it. The table
/// decides; the shell only draws. Rects are in scene space (origin bottom-left).
///
/// - `mine`: a hand of this phone is face up and it is that seat's turn. The big "Your turn"
///   moment plays and stays (the piles pulse "start here" while there is a card to draw) until
///   the first touch on the table, then gets out of the way. It comes back for the same turn
///   only when the app returns from the background (`replayTurnCue`).
/// - `theirs`: another seat is up. A calm "Mochi's turn" label hangs under their cat.
///
/// On a pass-and-play phone a seat's hand is shown only once its curtain lifts, so the cue
/// plays after the curtain, never behind it.
enum TurnCue: Equatable {
    case mine(Mine)
    case theirs(Theirs)

    /// One seat's turn: the store's turn epoch moves with every turn, round and status change.
    struct Key: Hashable {
        var epoch: Int
        var seat: Seat
    }

    struct Mine: Equatable {
        var key: Key
        /// Bumped when the cue plays again for the same turn (back from the background).
        var showing: Int
        var name: String
        var cat: Int
        /// A phone shared by several people: the cue says whose turn by name.
        var multiSeat: Bool
        /// The turn's first step: the piles pulse and the cue says to draw.
        var draw: Bool
        /// The piles that can be drawn from now.
        var piles: [CGRect]
        /// The open table between the piles and the hand, where the lettering lands.
        var stage: CGRect
    }

    struct Theirs: Equatable {
        var seat: Seat
        var name: String
        /// Their cat in the bar.
        var cat: CGRect
        /// The bar's bottom edge: the label hangs from it.
        var barBottom: CGFloat
    }

    var isMine: Bool {
        if case .mine = self { return true }
        return false
    }
}

/// The scene's bookkeeping for `TurnCue`.
struct TurnCueState {
    /// The turn whose cue a touch on the table put away.
    var dismissed: TurnCue.Key?
    /// A turn whose cue shows again after the draw too (the app came back on it).
    var replay: TurnCue.Key?
    var showing = 0
    var published: TurnCue?
}

extension TableScene {
    /// What the turn overlay should show for the table as drawn, or nil.
    func turnCueSnapshot() -> TurnCue? {
        guard let model, let game = model.game, let layout, game.status == .playing,
              model.room.status == .playing else { return nil }
        let seat = game.turn
        let seats = model.room.seats
        if model.mySeats.contains(seat) {
            let key = TurnCue.Key(epoch: store.turnEpoch, seat: seat)
            let draw = game.step == .draw
            guard seat == bottomSeat, seat == shownRevealed, !animating, !celebration.announced,
                  turnCue.dismissed != key, draw || turnCue.replay == key else { return nil }
            let piles = draw ? [deck.hitFrame, discard.hitFrame].enumerated()
                .filter { glows.piles.contains($0.offset == 0 ? .deck : .discard) }.map(\.element) : []
            let pilesBottom = layout.deck.y - layout.cardSize.height / 2
            let stage = CGRect(
                x: 0, y: layout.traysFrame.minY, width: size.width,
                height: max(pilesBottom - layout.traysFrame.minY, 0))
            return .mine(TurnCue.Mine(
                key: key, showing: turnCue.showing, name: SeatInfo.name(seats[safe: seat]),
                cat: SeatInfo.catIndex(seats[safe: seat]), multiSeat: model.isMultiSeat, draw: draw,
                piles: piles, stage: stage))
        }
        guard let frame = opponents.frame(of: seat) else { return nil }
        return .theirs(TurnCue.Theirs(
            seat: seat, name: SeatInfo.name(seats[safe: seat]), cat: frame, barBottom: layout.opponentsBar.minY))
    }

    /// Sends the shell a changed cue.
    func publishTurnCue() {
        let cue = turnCueSnapshot()
        guard cue != turnCue.published else { return }
        turnCue.published = cue
        onTurnCue(cue)
    }

    /// A touch on the table: a "Your turn" cue that is up goes away for the rest of the turn.
    func dismissTurnCue() {
        guard case .mine(let mine) = turnCue.published else { return }
        turnCue.dismissed = mine.key
        turnCue.replay = nil
        publishTurnCue()
    }

    /// The app came back from the background: on this phone's turn the cue plays again.
    func replayTurnCue() {
        guard let model, let game = model.game, game.status == .playing, model.mySeats.contains(game.turn) else { return }
        let key = TurnCue.Key(epoch: store.turnEpoch, seat: game.turn)
        if turnCue.dismissed == key { turnCue.dismissed = nil }
        turnCue.replay = key
        turnCue.showing += 1
        publishTurnCue()
    }
}
