import Foundation
import PounceKit

/// What the Daily Dish board socket says to a TV (docs/daily-protocol.md, "The board socket"), as
/// the TV reads it. Only what the TV draws is decoded; anything new is skipped. Rows name players
/// by "me" or a pair id, never a player id.
enum BoardWire {
    /// A run's result, as the server worked it out.
    struct Result: Decodable, Equatable, Sendable {
        let game: String
        let date: String
        let number: Int
        let outcome: Outcome
        let timeMs: Int
        let hints: Int
        let progress: Double
        let tooFast: Bool
        /// Sniff only.
        let guesses: Int?
        /// Box Fort only.
        let points: Int?

        enum Outcome: String, Decodable, Sendable {
            case solved, missed, gaveUp, closed, done
        }

        /// Solved, or Box Fort's ending: a run that finished well.
        var finished: Bool { outcome == .solved || outcome == .done }
    }

    struct Row: Decodable, Equatable, Sendable {
        let player: String
        let name: String
        let cat: Int
        let rank: Int?
        let result: Result?
        var playing: Playing?

        struct Playing: Decodable, Equatable, Sendable {
            let progress: Double
        }
    }

    struct Game: Decodable, Equatable, Sendable {
        let game: String
        let number: Int
        var rows: [Row]
    }

    struct DishRow: Decodable, Equatable, Sendable {
        let player: String
        let name: String
        let cat: Int
        let rank: Int
        let points: Int
        let crowns: [String]
        let ended: Int
    }

    struct Dish: Decodable, Equatable, Sendable {
        let rows: [DishRow]
    }

    struct Board: Decodable, Equatable, Sendable {
        let date: String
        var games: [Game]
        let dish: Dish
        let tvs: Int
    }

    enum Message: Equatable, Sendable {
        case board(Board)
        case result(player: String, result: Result)
        case progress(player: String, game: String, progress: Double)
        case watchOffer(player: String, name: String, cat: Int, game: String)
        case watch(player: String, game: String, puzzle: JSONValue, state: JSONValue)
        case watchEnd(player: String, game: String, result: Result?)
        /// `tvs`, `pong`, `error`, and kinds this build doesn't know.
        case other

        /// One frame of the socket, or nil when it isn't JSON at all.
        static func decode(_ text: String) -> Message? {
            let data = Data(text.utf8)
            guard let head = try? JSONDecoder().decode(Head.self, from: data) else { return nil }
            let decoder = JSONDecoder()
            switch head.t {
            case "board":
                guard let m = try? decoder.decode(BoardFrame.self, from: data) else { return .other }
                return .board(m.board)
            case "result":
                guard let m = try? decoder.decode(ResultFrame.self, from: data) else { return .other }
                return .result(player: m.player, result: m.result)
            case "progress":
                guard let m = try? decoder.decode(ProgressFrame.self, from: data) else { return .other }
                return .progress(player: m.player, game: m.game, progress: m.progress)
            case "watchOffer":
                guard let m = try? decoder.decode(OfferFrame.self, from: data) else { return .other }
                return .watchOffer(player: m.player, name: m.name, cat: m.cat, game: m.game)
            case "watch":
                guard let m = try? decoder.decode(WatchFrame.self, from: data) else { return .other }
                return .watch(player: m.player, game: m.game, puzzle: m.puzzle ?? .null, state: m.state)
            case "watchEnd":
                guard let m = try? decoder.decode(EndFrame.self, from: data) else { return .other }
                return .watchEnd(player: m.player, game: m.game, result: m.result)
            default:
                return .other
            }
        }

        private struct Head: Decodable { let t: String }
        private struct BoardFrame: Decodable { let board: Board }
        private struct ResultFrame: Decodable { let player: String; let result: Result }
        private struct ProgressFrame: Decodable { let player: String; let game: String; let progress: Double }
        private struct OfferFrame: Decodable { let player: String; let name: String; let cat: Int; let game: String }
        private struct WatchFrame: Decodable { let player: String; let game: String; let puzzle: JSONValue?; let state: JSONValue }
        private struct EndFrame: Decodable { let player: String; let game: String; let result: Result? }
    }
}
