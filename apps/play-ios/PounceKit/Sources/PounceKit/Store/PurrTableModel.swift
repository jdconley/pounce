import Foundation

/// What a phone at a Purrtrait table shows (spec §11.2, §11.3), from the room alone. The server
/// decides who sees a word (`choices` and `word` reach only the drawer's device); this only picks
/// the screen for what arrived.
public struct PurrTableModel: Equatable, Sendable {
    public let room: RoomView
    public let view: PurrView

    public init?(room: RoomView) {
        guard room.isPurrtrait, let view = room.purrtrait else { return nil }
        self.room = room
        self.view = view
    }

    /// Seats this phone holds.
    public var mySeats: [Seat] { room.seats.indices.filter { room.seats[$0].yours } }

    /// This phone holds more than one seat: the curtain comes down before a word shows.
    public var isShared: Bool { mySeats.count > 1 }

    public enum Screen: Equatable, Sendable {
        /// The drawer picks a word (this phone controls the drawer's seat).
        case pick(seat: Seat, choices: PurrChoices)
        /// This device owns the drawing turn.
        case draw(seat: Seat, word: String)
        /// Everyone else: look at the TV.
        case watch
        /// The word, now everyone's, and who got it.
        case reveal(PurrLast)
        case over
    }

    public var screen: Screen {
        switch view.phase {
        case .over: return .over
        case .reveal: return view.last.map(Screen.reveal) ?? .watch
        case .choosing:
            if let drawer = view.drawer, mySeats.contains(drawer), let choices = view.choices { return .pick(seat: drawer, choices: choices) }
            return .watch
        case .drawing:
            if let drawer = view.drawer, mySeats.contains(drawer), view.youDraw, let word = view.word { return .draw(seat: drawer, word: word) }
            return .watch
        }
    }

    /// This device owns the drawing turn right now.
    public var isDrawingHere: Bool {
        if case .draw = screen { return true }
        return false
    }

    /// The seat whose word must stay behind the curtain on a shared phone, if this screen shows one.
    public var curtained: Seat? {
        guard isShared else { return nil }
        switch screen {
        case .pick(let seat, _), .draw(let seat, _): return seat
        default: return nil
        }
    }

    /// One of this phone's seats draws next (the turn after this one).
    public var drawsNext: Seat? {
        guard let next = view.nextDrawer, mySeats.contains(next), next != view.drawer else { return nil }
        return next
    }

    /// Who can be tapped as having got it: everyone still in, but the drawer.
    public var guessers: [Seat] {
        room.seats.indices.filter { seat in
            seat != view.drawer && !view.isOut(seat) && room.seats[seat].kind == .human && seat < view.seats
        }
    }

    /// Every seat in the game, best score first (ties in seat order).
    public var standings: [(seat: Seat, score: Int)] {
        (0..<min(view.seats, view.scores.count))
            .filter { room.seats.indices.contains($0) && room.seats[$0].kind != .open && room.seats[$0].kind != .closed }
            .map { ($0, view.scores[$0]) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.seat < $1.seat }
    }

    /// When the phase's clock runs out, from a snapshot that arrived at `arrived`. Nil when it is
    /// stopped (no TV) or the phase has no clock.
    public func deadline(arrived: Date) -> Date? {
        guard !view.paused, let ms = view.remainingMs else { return nil }
        return arrived.addingTimeInterval(Double(ms) / 1000)
    }
}
