import Foundation
import Observation

/// What the Dish's screens read: whether the server has the Dish on, today's board, and stats.
/// It holds memory only; every call goes through `DailyService` (an actor) and the live board
/// through `DailyBoardSocket`, so nothing here blocks. `enabled` is nil until the server answered,
/// false after a 404 (hide the Dish); going offline keeps what was shown.
@MainActor @Observable public final class DailyStore {
    public var person: String? {
        didSet {
            guard person != oldValue else { return }
            board = nil
            stats = [:]
            enabled = nil
        }
    }

    public private(set) var enabled: Bool?
    public private(set) var board: DailyBoard?
    public private(set) var stats: [String: DailyStats] = [:]
    /// A board link made from this phone this session: Unlink shows even before a TV says so.
    public var linkedHere = false

    @ObservationIgnored public let service: any DailyService
    @ObservationIgnored private let makeSocket: (@Sendable (String?) -> DailyBoardSocket)?

    public init(service: any DailyService, socket: (@Sendable (String?) -> DailyBoardSocket)? = nil) {
        self.service = service
        makeSocket = socket
    }

    /// TVs showing a board this person is on: Show on TV only while above 0.
    public var tvs: Int { board?.tvs ?? 0 }

    /// My row on a game's board today: a result, or playing.
    public func mine(_ game: String) -> DailyBoardRow? { board?.mine(game) }

    /// My result today, once the run has ended.
    public func result(_ game: String) -> DailyResult? { mine(game)?.result }

    public func refresh() async {
        let person = person
        do {
            let fresh = try await service.board(date: nil, person: person)
            guard person == self.person else { return }
            board = fresh
            enabled = true
        } catch APIError.notFound {
            guard person == self.person else { return }
            board = nil
            enabled = false
        } catch {
            // Offline or the server is down: keep what was shown.
        }
    }

    public func refreshStats() async {
        let person = person
        guard let list = try? await service.stats(person: person), person == self.person else { return }
        stats = list.games
    }

    /// Takes a fresh result in at once (the end screen), before the socket says so.
    public func record(_ result: DailyResult) {
        board = board?.adding(result, for: DailyBoard.me)
    }

    /// Applies one board socket message.
    public func apply(_ message: DailyBoardMessage) {
        switch message {
        case .board(let fresh):
            board = fresh
            enabled = true
        case .result(let player, let result): board = board?.adding(result, for: player)
        case .progress(let player, let game, let progress): board = board?.moving(player, game: game, progress: progress)
        case .tvs(let count): board = board?.with(tvs: count)
        default: break
        }
    }

    /// Runs the live board until the calling task is cancelled (a view's `.task`).
    public func listen() async {
        guard let makeSocket else { return }
        let person = person
        let socket = makeSocket(person)
        let messages = await socket.messages()
        await socket.start()
        await withTaskCancellationHandler {
            for await message in messages {
                guard person == self.person else { break }
                apply(message)
            }
        } onCancel: {
            Task { await socket.stop() }
        }
        await socket.stop()
    }
}
