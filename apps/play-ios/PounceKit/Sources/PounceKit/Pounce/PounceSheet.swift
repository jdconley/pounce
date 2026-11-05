import Foundation

/// One of the Pounce sheet's big picture tiles (§12.4).
public enum PounceTile: Hashable, Sendable {
    /// A table you share, by its name; `theirMove` tables say "come make a move".
    case table(code: String, name: String, theirMove: Bool)
    /// A plus on a rug: the server deals a new Cat Tower table for you both.
    case new
    /// Dice: they choose.
    case pick
}

/// The rules behind the Pounce sheet and the pick sheet.
public enum PounceSheet {
    /// Their-move tables first, then the rest you share, then New game and You pick. With no
    /// partner (the share-only sheet for someone who doesn't play yet) only New game.
    public static func tiles(view: StreakView?, names: [String: String]) -> [PounceTile] {
        guard let view else { return [.new] }
        return tables(view: view, names: names, theirFirst: true) + [.new, .pick]
    }

    /// What a "you pick" answer chooses from: the tables you share, then a new game.
    public static func pickTiles(view: StreakView?, names: [String: String]) -> [PounceTile] {
        guard let view else { return [.new] }
        return tables(view: view, names: names, theirFirst: false) + [.new]
    }

    /// For the pick sheet, "my move" tables (from my side) come first: those wait on me.
    private static func tables(view: StreakView, names: [String: String], theirFirst: Bool) -> [PounceTile] {
        let first = theirFirst ? view.theirMove : view.myMove
        let second = theirFirst ? view.myMove : view.theirMove
        var seen: Set<String> = []
        var out: [PounceTile] = []
        for (codes, theirs) in [(first, theirFirst), (second, !theirFirst)] {
            for code in codes where RoomCode.isValid(code) && seen.insert(code).inserted {
                out.append(.table(code: code, name: names[code] ?? TableName.fallback(code: code), theirMove: theirs))
            }
        }
        return out
    }

    /// A their-move table when there is one, else New game; New game when asked (the Us
    /// screen's Play pill, §10.2).
    public static func preselect(_ tiles: [PounceTile], preferNew: Bool) -> PounceTile {
        if !preferNew, let theirs = tiles.first(where: { if case .table(_, _, true) = $0 { true } else { false } }) {
            return theirs
        }
        return tiles.contains(.new) ? .new : tiles.first ?? .new
    }

    public static func target(_ tile: PounceTile) -> PounceTarget {
        switch tile {
        case .table(let code, _, _): .table(code)
        case .new: .new
        case .pick: .pick
        }
    }

    /// A link can't name a table (the server refuses it): a table tile shares as "you pick".
    public static func shareTarget(_ tile: PounceTile) -> PounceTarget {
        tile == .new ? .new : .pick
    }

    /// A pick tile's `choice` for the answer: the table's code, or `new`.
    public static func choice(_ tile: PounceTile) -> String {
        if case .table(let code, _, _) = tile { return code }
        return "new"
    }
}

/// The Us screen's bell (§12.4): what it shows for my latest pounce on them.
public enum BellState: Equatable, Sendable {
    case ready
    /// Out and unanswered.
    case sent
    /// Out, and it landed in their quiet hours: a moon on the bell.
    case quiet
    /// The bell rests (the limits): a sleeping bell.
    case resting
    /// Their answer: Play (their cat leaps), In a bit (a clock), Not now (their cat asleep).
    case answered(PounceAnswer)

    public static func make(_ p: PounceState) -> BellState {
        if let answer = p.answer { return .answered(answer) }
        if p.resting { return .resting }
        if p.sent { return p.quiet ? .quiet : .sent }
        return .ready
    }

    /// For the UI tests' accessibility value.
    public var name: String {
        switch self {
        case .ready: "ready"
        case .sent: "sent"
        case .quiet: "quiet"
        case .resting: "resting"
        case .answered(let a): a.rawValue
        }
    }
}
