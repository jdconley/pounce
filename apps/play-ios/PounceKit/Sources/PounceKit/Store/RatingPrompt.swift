import Foundation

/// When Pounce asks for an App Store rating (the system sheet, never a screen of its own). It
/// asks only the adult who owns this phone, alone on it, right after a game they won and watched
/// end, and rarely: not on a new install, once per app version, and months apart. Apple caps the
/// sheet too (three times a year); these rules are the stricter gate. The gear's "Rate Pounce"
/// row opens `writeReviewURL` for anyone who wants to say something sooner.
public enum RatingPrompt {
    /// The App Store's review page for Pounce.
    public static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6829560061?action=write-review")!

    /// Finished games on this device before the first ask, the one just won included.
    public static let minimumGames = 2
    /// No ask this soon after the first launch.
    public static let quietAfterFirstLaunch: TimeInterval = 3 * 24 * 60 * 60
    /// No ask this soon after the last one.
    public static let quietAfterRequest: TimeInterval = 60 * 24 * 60 * 60
    /// How long the game over screen holds still, with nothing over it, before the ask.
    public static let settleDelay: Duration = .milliseconds(1500)

    /// How the finished game went for this device.
    public enum Outcome: Equatable, Sendable {
        /// A seat of this device won a game that was played to its end.
        case won
        /// A seat of this device won because everyone else forfeited (§5.13).
        case wonByForfeit
        /// Someone else won.
        case lost
    }

    /// Everything the decision reads.
    public struct Input: Equatable, Sendable {
        /// The phone owner's band; nil until the age check ran.
        public var band: AgeBand?
        public var outcome: Outcome
        /// The game ended while this phone was at the table (its celebration played here), not a
        /// finished table opened later.
        public var sawItEnd: Bool
        /// People seated on this device (pass-and-play puts several on one phone).
        public var localHumans: Int
        /// The seat of this device that won is the phone owner's.
        public var winnerIsOwner: Bool
        /// Finished games counted on this device, this one included.
        public var completedGames: Int
        public var firstLaunch: Date
        public var lastRequest: RatingRecord.Request?
        public var now: Date
        /// The running app's version (`CFBundleShortVersionString`).
        public var version: String
        /// A demo, a UI test or a screenshot run (`isStaged`).
        public var staged: Bool

        public init(
            band: AgeBand?, outcome: Outcome, sawItEnd: Bool, localHumans: Int, winnerIsOwner: Bool, completedGames: Int,
            firstLaunch: Date, lastRequest: RatingRecord.Request?, now: Date, version: String, staged: Bool
        ) {
            self.band = band
            self.outcome = outcome
            self.sawItEnd = sawItEnd
            self.localHumans = localHumans
            self.winnerIsOwner = winnerIsOwner
            self.completedGames = completedGames
            self.firstLaunch = firstLaunch
            self.lastRequest = lastRequest
            self.now = now
            self.version = version
            self.staged = staged
        }
    }

    /// Ask now. Every rule has to hold.
    public static func shouldAsk(_ input: Input) -> Bool {
        // Never in a demo, a UI test or a screenshot run.
        guard !input.staged else { return false }
        // Adults only: never a kitten or a teen, or a phone whose age isn't known.
        guard input.band == .adult else { return false }
        // A real win the person just watched: not a loss, not a win by forfeit.
        guard input.outcome == .won, input.sawItEnd else { return false }
        // One person on this phone, and it is the owner: on a shared phone the winner may be anyone.
        guard input.localHumans == 1, input.winnerIsOwner else { return false }
        guard input.completedGames >= minimumGames else { return false }
        guard input.now.timeIntervalSince(input.firstLaunch) >= quietAfterFirstLaunch else { return false }
        if let last = input.lastRequest {
            // Once per app version, and months apart whatever the version.
            guard last.version != input.version else { return false }
            guard input.now.timeIntervalSince(last.at) >= quietAfterRequest else { return false }
        }
        return true
    }

    /// The game is over for the table (the room closed it, or the game says so).
    private static func isOver(_ model: TableModel) -> Bool {
        model.room.status == .over || model.game?.status == .gameOver
    }

    /// How a finished table went for this device; nil while the game is on or this device has no seat.
    public static func outcome(_ model: TableModel) -> Outcome? {
        guard isOver(model), let game = model.game, !model.mySeats.isEmpty else { return nil }
        guard model.mySeats.contains(where: game.winners.contains) else { return .lost }
        return game.endReason == .forfeit ? .wonByForfeit : .won
    }

    /// People seated on this device at this table.
    public static func localHumans(_ model: TableModel) -> Int {
        model.mySeats.count { model.room.seats[$0].kind == .human }
    }

    /// A seat of this device won and the phone owner sits in it.
    public static func winnerIsOwner(_ model: TableModel, owner: String?) -> Bool {
        guard let owner, let game = model.game else { return false }
        return model.mySeats.contains { game.winners.contains($0) && model.room.seats[$0].person?.id == owner }
    }

    /// This table counts as a finished game on this device: played to its end (not ended by
    /// forfeits) with a seat of this device still in it.
    public static func countsAsCompleted(_ model: TableModel) -> Bool {
        guard isOver(model), let game = model.game, game.endReason != .forfeit else { return false }
        return model.mySeats.contains { !game.isOut($0) }
    }

    /// The run is a demo, a UI test or a screenshot run: any of the app's debug launch arguments
    /// that put canned data or a chosen screen up (`-demo`, `-demo-…`, `-show-…`, `-stub-…`,
    /// `-seed-…`, `-uitest-…`, `-age-band`, `-age-range`, `-slowmo`), or a test's pace
    /// (`-anim-speed` / `POUNCE_ANIM_SPEED`).
    public static func isStaged(arguments: [String], env: [String: String]) -> Bool {
        if PaceSetting.resolve(arguments: arguments, env: env).underTest { return true }
        let exact: Set<String> = ["-demo", "-slowmo", "-age-band", "-age-range"]
        let prefixes = ["-demo-", "-show-", "-stub-", "-seed-", "-uitest-"]
        return arguments.contains { argument in
            exact.contains(argument) || prefixes.contains { argument.hasPrefix($0) }
        }
    }
}

/// What the rating rules remember on this device.
public struct RatingRecord: Codable, Equatable, Sendable {
    /// One ask: when, and by which app version.
    public struct Request: Codable, Equatable, Sendable {
        public var at: Date
        public var version: String

        public init(at: Date, version: String) {
            self.at = at
            self.version = version
        }
    }

    /// Room codes remembered so a finished table opened again isn't counted twice.
    public static let countedLimit = 50

    /// When this record was first made: the app's first launch with the rating rules.
    public var firstLaunch: Date
    /// Finished games counted on this device.
    public var completedGames: Int
    /// The most recent counted tables' room codes, oldest first.
    public var counted: [String]
    /// The last time the system was asked for the sheet (it may not have shown it).
    public var lastRequest: Request?

    public init(firstLaunch: Date, completedGames: Int = 0, counted: [String] = [], lastRequest: Request? = nil) {
        self.firstLaunch = firstLaunch
        self.completedGames = completedGames
        self.counted = counted
        self.lastRequest = lastRequest
    }
}

/// `rating.json` in the given directory (next to `people.json`), rewritten atomically on every
/// change. Not thread-safe by itself; callers use it from one actor (the app model).
public final class RatingStore {
    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("rating.json")
    }

    /// The record; the first call on a device makes it, with `now` as the first launch.
    @discardableResult
    public func load(now: Date = .now) -> RatingRecord {
        if let data = try? Data(contentsOf: fileURL), let record = try? JSONDecoder().decode(RatingRecord.self, from: data) {
            return record
        }
        let record = RatingRecord(firstLaunch: now)
        save(record)
        return record
    }

    /// Counts the finished table `code` once, however often it is opened.
    @discardableResult
    public func noteCompleted(code: String, now: Date = .now) -> RatingRecord {
        var record = load(now: now)
        guard !record.counted.contains(code) else { return record }
        record.completedGames += 1
        record.counted.append(code)
        if record.counted.count > RatingRecord.countedLimit {
            record.counted.removeFirst(record.counted.count - RatingRecord.countedLimit)
        }
        save(record)
        return record
    }

    /// The system was asked for the rating sheet by `version`.
    @discardableResult
    public func noteRequested(version: String, now: Date = .now) -> RatingRecord {
        var record = load(now: now)
        record.lastRequest = RatingRecord.Request(at: now, version: version)
        save(record)
        return record
    }

    private func save(_ record: RatingRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(record) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
