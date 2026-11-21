#if DEBUG
    import Foundation
    import PounceKit

    /// `-demo-dish <fresh|some|done|long|off>`: the Dish fed from memory, no server, for screenshots
    /// and UI tests. `fresh`: nothing played, Grandpa playing. `some`: two of mine done. `done`:
    /// all four done, the board full. `long`: long names and big numbers. `off`: the server has the
    /// Dish off (a 404), so it hides. Every game the catalog knows shows, playable or not.
    enum DailyDemo {
        static func mode(arguments: [String]) -> String? {
            guard let i = arguments.firstIndex(of: "-demo-dish") else { return nil }
            let next = arguments.indices.contains(i + 1) ? arguments[i + 1] : "some"
            return next.hasPrefix("-") ? "some" : next
        }

        static var active: Bool { mode(arguments: CommandLine.arguments) != nil }

        static func service(arguments: [String]) -> (any DailyService)? {
            mode(arguments: arguments).map { DemoDailyService(mode: $0) }
        }

        static let date = "2026-11-23"
        static let number = 12

        static func result(_ game: String, _ outcome: DailyOutcome, ms: Int, hints: Int = 0, guesses: Int? = nil, points: Int? = nil) -> DailyResult {
            DailyResult(
                game: game, date: date, number: number, outcome: outcome, timeMs: ms, hints: hints, progress: outcome.finished ? 1 : 0.6,
                guesses: guesses, points: points)
        }

        static func board(_ mode: String) -> DailyBoard {
            let long = mode == "long"
            let me = long ? "Bartholomew" : "Mom"
            let kid = long ? "Clementine Rosalind" : "Kid"
            let gramps = long ? "Grandpa Archibald" : "Grandpa"
            func row(_ player: String, _ name: String, _ cat: Int, _ rank: Int?, _ r: DailyResult?, playing: Double? = nil) -> DailyBoardRow {
                DailyBoardRow(player: player, name: name, cat: cat, rank: rank, result: r, playing: playing.map(DailyPlaying.init))
            }
            let mine = mode != "fresh"
            let all = mode == "done" || long
            let sniff = DailyGameBoard(
                game: "sniff", number: number,
                rows: [
                    mine ? row("me", me, 2, 1, result("sniff", .solved, ms: 95_000, guesses: 3)) : nil,
                    row("pr_kid", kid, 5, mine ? 2 : 1, result("sniff", .solved, ms: 140_000, guesses: 4)),
                    row("pr_gramps", gramps, 1, nil, nil, playing: 0.5),
                ].compactMap { $0 })
            let nine = DailyGameBoard(
                game: "nine-lives", number: number,
                rows: [
                    row("pr_kid", kid, 5, 1, result("nine-lives", .solved, ms: long ? 3_729_000 : 247_000, hints: 1)),
                    mine ? row("me", me, 2, 2, result("nine-lives", .solved, ms: long ? 3_900_000 : 312_000)) : nil,
                ].compactMap { $0 })
            let nap = DailyGameBoard(
                game: "cat-nap", number: number,
                rows: all ? [row("me", me, 2, 1, result("cat-nap", .solved, ms: 133_000)), row("pr_gramps", gramps, 1, 2, result("cat-nap", .gaveUp, ms: 401_000))] : [row("pr_gramps", gramps, 1, nil, nil, playing: 0.2)])
            let fort = DailyGameBoard(
                game: "box-fort", number: number,
                rows: all
                    ? [row("me", me, 2, 1, result("box-fort", .done, ms: 300_000, points: long ? 12_480 : 1_240)), row("pr_kid", kid, 5, 2, result("box-fort", .done, ms: 280_000, points: long ? 9_870 : 980))]
                    : [])
            // As the server sends it: ties share a rank, and someone still playing isn't on it.
            let dish = DailyDish(
                rows: all
                    ? [
                        DailyDishRow(player: "me", name: me, cat: 2, rank: 1, points: 13, crowns: ["sniff", "cat-nap", "box-fort"], ended: 4),
                        DailyDishRow(player: "pr_kid", name: kid, cat: 5, rank: 2, points: 8, crowns: ["nine-lives"], ended: 3),
                        DailyDishRow(player: "pr_gramps", name: gramps, cat: 1, rank: 3, points: 3, crowns: [], ended: 1),
                    ]
                    : mine
                        ? [
                            DailyDishRow(player: "me", name: me, cat: 2, rank: 1, points: 6, crowns: ["sniff"], ended: 2),
                            DailyDishRow(player: "pr_kid", name: kid, cat: 5, rank: 1, points: 6, crowns: ["nine-lives"], ended: 2),
                        ]
                        : [DailyDishRow(player: "pr_kid", name: kid, cat: 5, rank: 1, points: 5, crowns: ["sniff", "nine-lives"], ended: 2)])
            return DailyBoard(date: date, games: [sniff, nine, nap, fort], dish: dish, tvs: mode == "fresh" ? 0 : 1)
        }

        static func stats() -> DailyStatsList {
            func days(_ game: String, _ make: (Int) -> DailyResult?) -> [DailyDay] {
                (0..<30).compactMap { i -> DailyDay? in
                    guard let r = make(i) else { return nil }
                    let date = String(format: "2026-10-%02d", min(31, 25 + i % 7))
                    return DailyDay(date: date, result: r)
                }
            }
            let guesses = [0, 2, 5, 7, 3, 1]
            return DailyStatsList(games: [
                "sniff": DailyStats(
                    played: 19, solved: 18, streak: 6, best: 11, bestTimeMs: 61_000, bestPoints: nil, guesses: guesses,
                    last30: days("sniff") { $0 % 5 == 4 ? nil : result("sniff", .solved, ms: 90_000, guesses: 2 + $0 % 4) },
                    lastEnded: date),
                "nine-lives": DailyStats(
                    played: 14, solved: 12, streak: 3, best: 8, bestTimeMs: 201_000, bestPoints: nil, guesses: Array(repeating: 0, count: 6),
                    last30: days("nine-lives") { $0 % 3 == 2 ? nil : result("nine-lives", .solved, ms: 200_000 + ($0 * 37_000) % 300_000) },
                    lastEnded: date),
                "cat-nap": DailyStats(
                    played: 9, solved: 9, streak: 2, best: 5, bestTimeMs: 98_000, bestPoints: nil, guesses: Array(repeating: 0, count: 6),
                    last30: days("cat-nap") { $0 % 4 == 0 ? result("cat-nap", .solved, ms: 98_000 + $0 * 4_000) : nil }, lastEnded: date),
                "box-fort": DailyStats(
                    played: 21, solved: 21, streak: 9, best: 9, bestTimeMs: nil, bestPoints: 1_640, guesses: Array(repeating: 0, count: 6),
                    last30: days("box-fort") { $0 % 6 == 5 ? nil : result("box-fort", .done, ms: 300_000, points: 700 + ($0 * 131) % 900) },
                    lastEnded: date),
            ])
        }
    }

    /// The Dish from memory. Starting a run isn't part of the demo: puzzles play against a server.
    actor DemoDailyService: DailyService {
        let mode: String
        init(mode: String) { self.mode = mode }

        func board(date: String?, person: String?) async throws -> DailyBoard {
            if mode == "off" { throw APIError.notFound }
            return DailyDemo.board(mode)
        }
        func stats(person: String?) async throws -> DailyStatsList {
            if mode == "off" { throw APIError.notFound }
            return DailyDemo.stats()
        }
        func start(game: String, person: String?) async throws -> DailyStart { throw APIError.notFound }
        func moves(run: String, body: DailyMovesBody, person: String?) async throws -> DailyMovesAnswer { throw APIError.notFound }
        func hint(run: String, hints: Int, person: String?) async throws -> DailyMovesAnswer { throw APIError.notFound }
        func giveUp(run: String, person: String?) async throws -> DailyMovesAnswer { throw APIError.notFound }
        func showOnTV(run: String, on: Bool, person: String?) async throws {}
        func linkBoard(_ key: ScreenKey, person: String?) async throws {}
        func unlinkBoard(person: String?) async throws {}
    }
#endif
