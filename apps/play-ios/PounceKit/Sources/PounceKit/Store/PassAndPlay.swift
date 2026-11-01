public enum CurtainState: Equatable, Sendable {
    case none
    case curtain(Seat)
    case revealed(Seat)
}

/// Decides when the pass-the-phone curtain covers the table. With one seat on
/// the phone nothing is ever hidden; with several, a hand is shown only after
/// the holder confirms, and any turn that leaves this phone hides it again.
public struct PassAndPlay: Equatable, Sendable {
    public private(set) var revealed: Seat?
    public private(set) var state: CurtainState = .none

    private var mySeats: [Seat] = []
    private var lastTurn: Seat?
    private var lastRound: Int?
    /// The seat of mine whose turn is live, if any.
    private var activeTurn: Seat?

    public init() {}

    public mutating func update(_ model: TableModel) {
        mySeats = model.mySeats
        let game = model.game
        let turnChanged = game?.turn != lastTurn
        let roundChanged = game?.round != lastRound
        lastTurn = game?.turn
        lastRound = game?.round
        activeTurn = model.isMyTurn ? game?.turn : nil

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

        if roundChanged { revealed = nil }
        if let turn = activeTurn {
            if revealed == turn {
                state = .revealed(turn)
            } else {
                revealed = nil
                state = .curtain(turn)
            }
        } else if turnChanged || roundChanged {
            // A remote, bot or finished turn: nothing of mine stays visible.
            revealed = nil
            state = .none
        }
    }

    /// The hold finished on a curtain: show that seat's hand.
    public mutating func completeHold() {
        guard case .curtain(let seat) = state else { return }
        revealed = seat
        state = .revealed(seat)
    }

    /// Look at one of my own hands outside my turn (behind the curtain first).
    public mutating func peek(_ seat: Seat) {
        guard mySeats.count > 1, mySeats.contains(seat), activeTurn == nil else { return }
        revealed = nil
        state = .curtain(seat)
    }

    public mutating func hide() {
        guard mySeats.count > 1 else { return }
        revealed = nil
        state = .none
    }
}
