import Foundation

/// How a daily game's result reads and ranks.
public enum DailyScoring: String, Sendable, Hashable {
    /// Nine Lives, Cat Nap: the time; unsolved after solved.
    case time
    /// Sniff: guesses used, then time.
    case guesses
    /// Box Fort: points; every run ends with some.
    case points
}

/// One daily game, as the Dish lists it. Its rules and screens live in the game's own folders;
/// this is only what the Dish, the board and the share card need to know about it.
public struct DailyGameInfo: Sendable, Hashable, Identifiable {
    /// The server's id: `"sniff"`, `"nine-lives"`, `"cat-nap"`, `"box-fort"`, or `"test"`.
    public let id: String
    public let title: String
    public let scoring: DailyScoring
    public let hints: Bool
    /// Sniff's six guesses; nil for games with no fixed number of tries.
    public let tries: Int?
    /// The game's color on the Dish and its share card, from Pounce's palette (0xRRGGBB).
    public let tint: UInt32
    /// The rules this app plays, asked for at start (`{ "rules": ... }`): Nine Lives' `"lives"`.
    /// Nil: the game has one set of rules, and the start has no body.
    public let rules: String?
    /// What a `missed` run is called: "Missed", or Nine Lives' "Out of lives".
    public let missed: String

    public init(
        id: String, title: String, scoring: DailyScoring, hints: Bool, tries: Int? = nil, tint: UInt32, rules: String? = nil,
        missed: String = "Missed"
    ) {
        self.id = id
        self.title = title
        self.scoring = scoring
        self.hints = hints
        self.tries = tries
        self.tint = tint
        self.rules = rules
        self.missed = missed
    }

    /// "Sniff 12: 4 of 6", "Nine Lives 12: 4:07", "Box Fort 12: 1,240 points", "Nine Lives 12: Out of lives".
    /// The share text: the number and the result, nothing that spoils the puzzle.
    public func line(_ result: DailyResult) -> String {
        "\(name(number: result.number)): \(summary(result))"
    }

    /// "Sniff 12", or just "Sniff" for a number below 1 (a server before launch day sets
    /// `LAUNCH` counts from far ahead, so its numbers are negative).
    public func name(number: Int) -> String {
        number >= 1 ? "\(title) \(number)" : title
    }

    /// The result alone: "4 of 6", "4:07", "1,240 points", "Gave up", "Out of lives".
    public func summary(_ result: DailyResult) -> String {
        switch (scoring, result.outcome) {
        case (.points, _):
            return "\((result.points ?? 0).formatted(.number)) points"
        case (.guesses, .solved):
            return "\(result.guesses ?? 0) of \(tries ?? 6)"
        case (.guesses, .missed):
            return "X of \(tries ?? 6)"
        case (_, .solved):
            return DailyClock.format(ms: Int64(result.timeMs))
        case (_, .gaveUp):
            return "Gave up"
        case (_, .closed):
            return "Out of time"
        default:
            return missed
        }
    }

    /// The result in a few characters, for a treat on Home or a board row: "4/6", "4:07", "1,240".
    public func short(_ result: DailyResult) -> String {
        switch (scoring, result.outcome) {
        case (.points, _): return (result.points ?? 0).formatted(.number)
        case (.guesses, .solved): return "\(result.guesses ?? 0)/\(tries ?? 6)"
        case (.guesses, .missed): return "X/\(tries ?? 6)"
        case (_, .solved): return DailyClock.format(ms: Int64(result.timeMs))
        case (_, .missed): return missed
        default: return "Missed"
        }
    }
}

/// The daily games this app knows, in the Dish's order (the server's: Sniff, Nine Lives, Cat Nap,
/// Box Fort). A game is played only when the app also has its screen (`Pounce/Daily/DailyGames.swift`,
/// one line per game) and the server lists it.
public enum DailyCatalog {
    public static let sniff = DailyGameInfo(id: "sniff", title: "Sniff", scoring: .guesses, hints: false, tries: 6, tint: 0xFF2E9A)
    public static let nineLives = DailyGameInfo(id: "nine-lives", title: "Nine Lives", scoring: .time, hints: true, tint: 0x2EB8FF, rules: "lives", missed: "Out of lives")
    public static let catNap = DailyGameInfo(id: "cat-nap", title: "Cat Nap", scoring: .time, hints: true, tint: 0x00D1C1)
    public static let boxFort = DailyGameInfo(id: "box-fort", title: "Box Fort", scoring: .points, hints: false, tint: 0xFF8A00)
    /// The server's test game (`DAILY_TEST=on`): count to 3 + level. Debug builds only play it.
    public static let test = DailyGameInfo(id: "test", title: "Count", scoring: .time, hints: true, tint: 0x9BE22E)

    public static let all: [DailyGameInfo] = [sniff, nineLives, catNap, boxFort]

    public static func info(_ id: String) -> DailyGameInfo? {
        (all + [test]).first { $0.id == id }
    }
}
