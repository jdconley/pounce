import Foundation
import Testing
@testable import PounceKit

@Suite struct RatingPromptTests {
    private static let day: TimeInterval = 24 * 60 * 60
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// An ask that passes every rule: an adult owner, alone on the phone, just won their second
    /// game, a week after the first launch, never asked before.
    private func input(_ change: (inout RatingPrompt.Input) -> Void = { _ in }) -> RatingPrompt.Input {
        var input = RatingPrompt.Input(
            band: .adult, outcome: .won, sawItEnd: true, localHumans: 1, winnerIsOwner: true, completedGames: 2,
            firstLaunch: now.addingTimeInterval(-7 * Self.day), lastRequest: nil, now: now, version: "1.1", staged: false)
        change(&input)
        return input
    }

    private func asks(_ change: (inout RatingPrompt.Input) -> Void = { _ in }) -> Bool {
        RatingPrompt.shouldAsk(input(change))
    }

    // MARK: the decision

    @Test func asksWhenEveryRuleHolds() {
        #expect(asks())
    }

    @Test func onlyAdults() {
        #expect(!asks { $0.band = .teen })
        #expect(!asks { $0.band = .kitten })
        // The age check hasn't run: unknown counts as the most limited.
        #expect(!asks { $0.band = nil })
    }

    @Test func onlyAfterARealWin() {
        #expect(!asks { $0.outcome = .lost })
        #expect(!asks { $0.outcome = .wonByForfeit })
    }

    @Test func onlyWhenTheGameEndedHere() {
        // A won table opened from Home later: no celebration played, so no ask.
        #expect(!asks { $0.sawItEnd = false })
    }

    @Test func neverOnASharedPhone() {
        #expect(!asks { $0.localHumans = 2 })
        #expect(!asks { $0.localHumans = 4 })
        // No seat here at all.
        #expect(!asks { $0.localHumans = 0 })
    }

    @Test func onlyThePhoneOwner() {
        // Someone else from this phone's people list played alone on it.
        #expect(!asks { $0.winnerIsOwner = false })
    }

    @Test func notBeforeTheSecondFinishedGame() {
        #expect(!asks { $0.completedGames = 0 })
        #expect(!asks { $0.completedGames = 1 })
        #expect(asks { $0.completedGames = 2 })
        #expect(asks { $0.completedGames = 30 })
    }

    @Test func notWithinThreeDaysOfFirstLaunch() {
        let now = now
        #expect(!asks { $0.firstLaunch = now })
        #expect(!asks { $0.firstLaunch = now.addingTimeInterval(-3 * Self.day + 1) })
        #expect(asks { $0.firstLaunch = now.addingTimeInterval(-3 * Self.day) })
        #expect(asks { $0.firstLaunch = now.addingTimeInterval(-3 * Self.day - 1) })
        // A clock set back to before the first launch.
        #expect(!asks { $0.firstLaunch = now.addingTimeInterval(Self.day) })
    }

    @Test func oncePerVersion() {
        let longAgo = now.addingTimeInterval(-400 * Self.day)
        #expect(!asks { $0.lastRequest = .init(at: longAgo, version: "1.1") })
        #expect(asks { $0.lastRequest = .init(at: longAgo, version: "1.0") })
        // Versions are compared as written: 1.1 and 1.1.0 are two versions.
        #expect(asks { $0.lastRequest = .init(at: longAgo, version: "1.1.0") })
    }

    @Test func sixtyDaysAfterTheLastAsk() {
        let now = now
        #expect(!asks { $0.lastRequest = .init(at: now, version: "1.0") })
        #expect(!asks { $0.lastRequest = .init(at: now.addingTimeInterval(-60 * Self.day + 1), version: "1.0") })
        #expect(asks { $0.lastRequest = .init(at: now.addingTimeInterval(-60 * Self.day), version: "1.0") })
        #expect(asks { $0.lastRequest = .init(at: now.addingTimeInterval(-60 * Self.day - 1), version: "1.0") })
        // A clock set back to before the last ask.
        #expect(!asks { $0.lastRequest = .init(at: now.addingTimeInterval(Self.day), version: "1.0") })
        // The same version stays quiet however long ago.
        #expect(!asks { $0.lastRequest = .init(at: now.addingTimeInterval(-60 * Self.day), version: "1.1") })
    }

    @Test func neverInAStagedRun() {
        #expect(!asks { $0.staged = true })
    }

    @Test func theRulesAreTheOnesWrittenDown() {
        #expect(RatingPrompt.minimumGames == 2)
        #expect(RatingPrompt.quietAfterFirstLaunch == 3 * Self.day)
        #expect(RatingPrompt.quietAfterRequest == 60 * Self.day)
        #expect(RatingPrompt.settleDelay == .milliseconds(1500))
        #expect(RatingPrompt.writeReviewURL.absoluteString == "https://apps.apple.com/app/id6829560061?action=write-review")
    }

    // MARK: reading the table

    /// A finished four-seat table: `mine` on this phone, `bots` House Cats, `winners` crowned.
    private func finished(
        mine: Set<Seat> = [0], bots: Set<Seat> = [], winners: [Seat] = [0], endReason: GameEndReason? = nil,
        forfeited: [Bool]? = nil, status: RoomStatus = .over, gameStatus: GameStatus = .gameOver
    ) -> TableModel {
        var room = makeRoom(seatCount: 4, mine: mine, status: status, gameStatus: gameStatus, forfeited: forfeited)
        for seat in bots { room.seats[seat] = SeatView(kind: .bot) }
        room.game?.winners = winners
        room.game?.endReason = endReason
        return TableModel(room: room)
    }

    @Test func outcomeOfAFinishedTable() {
        #expect(RatingPrompt.outcome(finished()) == .won)
        #expect(RatingPrompt.outcome(finished(bots: [1, 2, 3])) == .won)
        // A shared win is a win.
        #expect(RatingPrompt.outcome(finished(winners: [0, 2])) == .won)
        // The server ended it early because nothing could change the result: still played out.
        #expect(RatingPrompt.outcome(finished(endReason: .decided)) == .won)
        #expect(RatingPrompt.outcome(finished(winners: [1])) == .lost)
        #expect(RatingPrompt.outcome(finished(winners: [])) == .lost)
        #expect(RatingPrompt.outcome(finished(endReason: .forfeit, forfeited: [false, true, true, true])) == .wonByForfeit)
        #expect(RatingPrompt.outcome(finished(winners: [1], endReason: .forfeit, forfeited: [true, false, true, true])) == .lost)
        // On a shared phone any local seat's win counts as this device's.
        #expect(RatingPrompt.outcome(finished(mine: [0, 1], winners: [1])) == .won)
    }

    @Test func noOutcomeWhileTheGameIsOnOrWithNoSeat() {
        #expect(RatingPrompt.outcome(finished(status: .playing, gameStatus: .playing)) == nil)
        #expect(RatingPrompt.outcome(finished(status: .lobby, gameStatus: .playing)) == nil)
        #expect(RatingPrompt.outcome(finished(mine: [])) == nil)
        // The game says it is over before the room does: over.
        #expect(RatingPrompt.outcome(finished(status: .playing)) == .won)
    }

    @Test func localHumansCountsThisPhonesSeats() {
        #expect(RatingPrompt.localHumans(finished()) == 1)
        #expect(RatingPrompt.localHumans(finished(bots: [1, 2, 3])) == 1)
        #expect(RatingPrompt.localHumans(finished(mine: [0, 2])) == 2)
        #expect(RatingPrompt.localHumans(finished(mine: [0, 1, 2, 3])) == 4)
        #expect(RatingPrompt.localHumans(finished(mine: [])) == 0)
        // A seat that forfeited was still someone on this phone.
        #expect(RatingPrompt.localHumans(finished(mine: [0, 1], forfeited: [false, true, false, false])) == 2)
    }

    @Test func winnerIsOwnerNeedsTheOwnersSeatToWin() {
        // `makeRoom` seats person `p<seat>` at each seat.
        #expect(RatingPrompt.winnerIsOwner(finished(), owner: "p0"))
        #expect(!RatingPrompt.winnerIsOwner(finished(), owner: "someone-else"))
        #expect(!RatingPrompt.winnerIsOwner(finished(), owner: nil))
        // The owner sits here but another seat won.
        #expect(!RatingPrompt.winnerIsOwner(finished(winners: [1]), owner: "p0"))
        // The winner is the owner's id on another phone's seat: not this device's win.
        #expect(!RatingPrompt.winnerIsOwner(finished(winners: [1]), owner: "p1"))
        #expect(RatingPrompt.winnerIsOwner(finished(mine: [0, 1], winners: [1]), owner: "p1"))
    }

    @Test func whichTablesCountAsCompleted() {
        #expect(RatingPrompt.countsAsCompleted(finished()))
        // A loss is a finished game too.
        #expect(RatingPrompt.countsAsCompleted(finished(winners: [2])))
        #expect(RatingPrompt.countsAsCompleted(finished(endReason: .decided)))
        #expect(!RatingPrompt.countsAsCompleted(finished(endReason: .forfeit, forfeited: [false, true, true, true])))
        // This phone's only seat left the game; the others played it out.
        #expect(!RatingPrompt.countsAsCompleted(finished(winners: [1], forfeited: [true, false, false, false])))
        #expect(RatingPrompt.countsAsCompleted(finished(mine: [0, 1], winners: [2], forfeited: [true, false, false, false])))
        #expect(!RatingPrompt.countsAsCompleted(finished(mine: [])))
        #expect(!RatingPrompt.countsAsCompleted(finished(status: .playing, gameStatus: .playing)))
    }

    // MARK: staged runs

    @Test func demoTestAndScreenshotRunsAreStaged() {
        func staged(_ arguments: [String], env: [String: String] = [:]) -> Bool {
            RatingPrompt.isStaged(arguments: ["Pounce"] + arguments, env: env)
        }
        #expect(!staged([]))
        for arguments in [
            ["-demo", "over"], ["-demo", "celebrate", "-slowmo", "0.2"], ["-slowmo", "0.5"], ["-uitest-reset"],
            ["-uitest-age-service", "x"], ["-anim-speed", "10"], ["-anim-speed", "1"], ["-demo-streaks"], ["-demo-home"],
            ["-demo-kitten", "locked"], ["-demo-live-table", "mine"], ["-demo-communication"], ["-show-gear"],
            ["-show-us"], ["-show-scoreboard"], ["-stub-accounts", "signed-in"], ["-seed-people"], ["-age-band", "adult"],
            ["-age-range", "adult"],
        ] {
            #expect(staged(arguments), "\(arguments)")
        }
        #expect(staged([], env: ["POUNCE_ANIM_SPEED": "10"]))
        // What Xcode and the system pass, a link opened at launch and another server: a real run.
        #expect(!staged(["-NSDocumentRevisionsDebugMode", "YES", "-AppleLanguages", "(en)"]))
        #expect(!staged(["-open-link", "pounce-dev://j/BCDFG"]))
        #expect(!staged([], env: ["POUNCE_API_BASE_URL": "http://localhost:8787"]))
    }

    // MARK: the record

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pounce-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func theFirstLoadIsTheFirstLaunch() throws {
        let dir = try tempDir()
        let first = RatingStore(directory: dir).load(now: now)
        #expect(first == RatingRecord(firstLaunch: now))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("rating.json").path))
        // Later launches keep it.
        let later = RatingStore(directory: dir).load(now: now.addingTimeInterval(9 * Self.day))
        #expect(later.firstLaunch == now)
    }

    @Test func theDirectoryIsMadeWhenMissing() throws {
        let dir = try tempDir().appendingPathComponent("Pounce", isDirectory: true)
        RatingStore(directory: dir).load(now: now)
        #expect(RatingStore(directory: dir).load(now: now.addingTimeInterval(Self.day)).firstLaunch == now)
    }

    @Test func aFinishedTableIsCountedOnce() throws {
        let dir = try tempDir()
        let store = RatingStore(directory: dir)
        #expect(store.noteCompleted(code: "BCDFG", now: now).completedGames == 1)
        #expect(store.noteCompleted(code: "BCDFG", now: now).completedGames == 1)
        #expect(store.noteCompleted(code: "HJKLM", now: now).completedGames == 2)
        let reloaded = RatingStore(directory: dir).load(now: now)
        #expect(reloaded.completedGames == 2)
        #expect(reloaded.counted == ["BCDFG", "HJKLM"])
        #expect(reloaded.firstLaunch == now)
    }

    @Test func onlyTheNewestCodesAreKept() throws {
        let store = RatingStore(directory: try tempDir())
        let total = RatingRecord.countedLimit + 5
        for i in 0..<total { store.noteCompleted(code: "T\(i)", now: now) }
        let record = store.load(now: now)
        #expect(record.completedGames == total)
        #expect(record.counted.count == RatingRecord.countedLimit)
        #expect(record.counted.first == "T5")
        #expect(record.counted.last == "T\(total - 1)")
    }

    @Test func anAskIsRememberedWithItsVersion() throws {
        let dir = try tempDir()
        let store = RatingStore(directory: dir)
        store.noteCompleted(code: "BCDFG", now: now)
        let asked = now.addingTimeInterval(5 * Self.day)
        store.noteRequested(version: "1.1", now: asked)
        let record = RatingStore(directory: dir).load(now: asked)
        #expect(record.lastRequest == RatingRecord.Request(at: asked, version: "1.1"))
        #expect(record.completedGames == 1)
        #expect(record.firstLaunch == now)
    }

    @Test func aBrokenFileStartsOver() throws {
        let dir = try tempDir()
        try Data("not json".utf8).write(to: dir.appendingPathComponent("rating.json"))
        // Starting over is the quiet side: the three days count from now again.
        #expect(RatingStore(directory: dir).load(now: now) == RatingRecord(firstLaunch: now))
    }
}
