public enum CurtainState: Equatable, Sendable {
    case none
    case curtain(Seat)
    case revealed(Seat)
}

/// Decides when the pass-the-phone curtain covers the table. With one seat on
/// the phone nothing is ever hidden; with several, a hand is shown only after
/// the holder confirms, and any turn that leaves this phone hides it again.
///
/// `RoomStore` owns one and updates it with every room it applies (`RoomStore.pass`), so the
/// curtain always matches the store. Turn changes are read from the store's turn epoch
/// (`RoomStore.turnEpoch`, see `TurnEpoch`), not by comparing rooms: two turns of the same seat
/// with others in between are still a change. A reveal (a hold on the curtain, or a peek) is
/// valid only in the epoch it was granted in and only while this phone holds the same seats (a
/// hand shown on a one-seat phone goes behind the curtain when a second seat arrives). Outside
/// live play (round over, game over, lobby) a multi-seat phone shows no hand and no curtain.
public struct PassAndPlay: Equatable, Sendable {
    public private(set) var revealed: Seat?
    public private(set) var state: CurtainState = .none {
        didSet {
            if case .curtain = state, state != oldValue { curtains += 1 }
        }
    }
    /// The turn epoch `state` (and `revealed`) belong to; -1 before the first update.
    public private(set) var epoch = -1
    /// Goes up each time a new curtain comes down (the state turns into a curtain), so the
    /// shell can start the hold afresh.
    public private(set) var curtains = 0

    private var mySeats: [Seat] = []
    /// The seat of mine whose turn is live, if any.
    private var activeTurn: Seat?
    /// The room and game are both playing.
    private var live = false

    public init() {}

    /// `epoch` is the store's `turnEpoch` for the room `model` was made from.
    public mutating func update(_ model: TableModel, epoch: Int) {
        // A seat that forfeited (§5.13) never plays again: a shared phone passes between the rest.
        let seats = model.myActiveSeats
        let moved = epoch != self.epoch || seats != mySeats
        mySeats = seats
        self.epoch = epoch
        live = model.isLive
        activeTurn = model.isMyTurn ? model.currentSeat : nil

        if mySeats.count == 1, let only = mySeats.first {
            revealed = only
            state = .revealed(only)
            return
        }
        guard mySeats.count > 1 else {
            revealed = nil
            state = .none
            return
        }

        // A reveal never outlives its epoch or this phone's seats, and nothing stays face up
        // outside play.
        if moved || !live { revealed = nil }
        if let turn = activeTurn {
            if revealed == turn {
                state = .revealed(turn)
            } else {
                revealed = nil
                state = .curtain(turn)
            }
        } else if moved || !live {
            // A remote, bot or finished turn: nothing of mine stays visible.
            revealed = nil
            state = .none
        }
    }

    /// The hold finished on a curtain: show that seat's hand (for this epoch only).
    public mutating func completeHold() {
        guard case .curtain(let seat) = state else { return }
        revealed = seat
        state = .revealed(seat)
    }

    /// Look at one of my own hands outside my turn (behind the curtain first), during play.
    public mutating func peek(_ seat: Seat) {
        guard mySeats.count > 1, mySeats.contains(seat), live, activeTurn == nil else { return }
        revealed = nil
        state = .curtain(seat)
    }

    public mutating func hide() {
        guard mySeats.count > 1 else { return }
        revealed = nil
        state = .none
    }
}
