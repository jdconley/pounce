import Foundation
import Testing
@testable import PounceKit

@Suite struct UITipsTests {
    private func home(_ visible: Set<String>, opens: Int = 1, band: AgeBand? = .adult, passAndPlay: Bool = false,
                      events: Set<TipEvent> = [], person: String = "a") -> TipFacts {
        TipFacts(screen: .home, person: person, band: band, passAndPlay: passAndPlay, opens: opens,
                 visible: visible, events: events)
    }

    /// A brand-new player's Home: the Cat Tower card, Practice and Join.
    private let newHome: Set<String> = ["home.play", "home.practice", "home.join", "home.hero", "home.people"]

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pounce-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: the rules

    @Test func everyTipHasOneAnchorAndUsingItTeachesIt() {
        for tip in UITip.allCases {
            #expect(tip.rawValue.hasPrefix("ui."))
            #expect(UITip.learned(by: tip.rule.anchor).contains(tip), "\(tip) isn't learned by its own control")
            #expect(CoachTip(rawValue: tip.rawValue) == nil)
        }
    }

    // MARK: triggers and priority

    @Test func aNewPlayersFirstHomeVisitOpensWithTheShelf() {
        #expect(TipDirector.candidate(home(newHome), seen: []) == .homeShelf)
        // Practice and Join wait for the shelf; the rules and people wait for later opens.
        #expect(TipDirector.candidate(home(newHome), seen: [.homeShelf]) == .homePractice)
        #expect(TipDirector.candidate(home(newHome), seen: [.homeShelf, .homePractice]) == .homeJoin)
        #expect(TipDirector.candidate(home(newHome), seen: [.homeShelf, .homePractice, .homeJoin]) == nil)
    }

    @Test func aTipNeedsItsControlOnScreen() {
        #expect(TipDirector.candidate(home(["home.join"]), seen: []) == nil)
        #expect(TipDirector.candidate(home(["home.join"]), seen: [.homeShelf]) == .homeJoin)
        #expect(TipDirector.candidate(TipFacts(screen: .lobby, person: "a", visible: ["home.join"]), seen: [.homeShelf]) == nil)
    }

    @Test func appOpensGateTheLaterTips() {
        let seen: Set<UITip> = [.homeShelf, .homePractice, .homeJoin]
        #expect(TipDirector.candidate(home(newHome, opens: 1), seen: seen) == nil)
        #expect(TipDirector.candidate(home(newHome, opens: 2), seen: seen) == .homeRules)
        #expect(TipDirector.candidate(home(newHome, opens: 2), seen: seen.union([.homeRules])) == nil)
        #expect(TipDirector.candidate(home(newHome, opens: 3), seen: seen.union([.homeRules])) == .homePeople)
    }

    @Test func urgentThingsComeFirst() {
        let all = newHome.union(["home.update", "home.gift", "home.tables"])
        #expect(TipDirector.candidate(home(all), seen: []) == .homeShelf)
        #expect(TipDirector.candidate(home(all), seen: [.homeShelf]) == .homeUpdate)
        #expect(TipDirector.candidate(home(all), seen: [.homeShelf, .homeUpdate]) == .homeGift)
        #expect(TipDirector.candidate(home(all), seen: [.homeShelf, .homeUpdate, .homeGift]) == .homePractice)
    }

    @Test func archiveWaitsForATableThatWaitedADay() {
        let tables: Set<String> = ["home.tables"]
        #expect(TipDirector.candidate(home(tables), seen: []) == .homeTables)
        #expect(TipDirector.candidate(home(tables), seen: [.homeTables]) == nil)
        #expect(TipDirector.candidate(home(tables.union(["home.idleTable"])), seen: [.homeTables]) == .homeArchive)
    }

    @Test func inviteWaitsForAFinishedGame() {
        let strip: Set<String> = ["home.own", "home.add"]
        #expect(TipDirector.candidate(home(strip), seen: []) == .homeStreak)
        #expect(TipDirector.candidate(home(strip), seen: [.homeStreak]) == nil)
        #expect(TipDirector.candidate(home(strip, events: [.gameOver]), seen: [.homeStreak]) == .homeInvite)
    }

    @Test func eligibilityByAgeAndPassAndPlay() {
        let gear = { (band: AgeBand?) in TipFacts(screen: .gear, person: "a", band: band, visible: ["settings.reminder"]) }
        #expect(TipDirector.candidate(gear(.adult), seen: []) == .gearAlerts)
        #expect(TipDirector.candidate(gear(.teen), seen: []) == .gearAlerts)
        #expect(TipDirector.candidate(gear(.kitten), seen: []) == nil)
        // The cat opens People: worth a tip on a phone one person uses, not one already shared.
        let seen: Set<UITip> = [.homeShelf, .homePractice, .homeJoin, .homeRules]
        #expect(TipDirector.candidate(home(newHome, opens: 3), seen: seen) == .homePeople)
        #expect(TipDirector.candidate(home(newHome, opens: 3, passAndPlay: true), seen: seen) == nil)
    }

    // MARK: pacing

    @Test func oneAtATimeAndAFewPerVisit() {
        var director = TipDirector()
        var seen: Set<UITip> = []
        let all = newHome.union(["home.update", "home.gift", "home.tables", "home.own"])
        var shown: [UITip] = []
        for _ in 0..<10 {
            if let tip = director.update(home(all), seen: seen, today: shown.count) {
                #expect(director.tip == tip)
                // While it's up, nothing else goes up.
                #expect(director.update(home(all), seen: seen.union([tip]), today: shown.count + 1) == nil)
                shown.append(tip)
                seen.insert(tip)
                director.dismiss()
            }
        }
        #expect(shown == [.homeShelf, .homeUpdate, .homeGift])
        // A new visit to the same screen gets more, up to the session's limit.
        director.visit(.home)
        #expect(director.update(home(all), seen: seen, today: 3) == .homePractice)
        director.dismiss()
        #expect(director.update(home(all), seen: seen.union([.homePractice]), today: 4) == nil, "four a session")
    }

    @Test func theDailyLimitHolds() {
        var director = TipDirector()
        #expect(director.update(home(newHome), seen: [], today: TipPacing.standard.perDay) == nil)
        #expect(director.update(home(newHome), seen: [], today: TipPacing.standard.perDay - 1) == .homeShelf)
    }

    @Test func sessionsArePerPerson() {
        var director = TipDirector(pacing: TipPacing(perVisit: 9, perSession: 1, perDay: 9))
        let tiles: Set<String> = ["tiles.meter", "tiles.draw"]
        #expect(director.update(TipFacts(screen: .tiles, person: "a", visible: tiles), seen: [], today: 0) == .tilesMeter)
        director.dismiss()
        #expect(director.update(TipFacts(screen: .tiles, person: "a", visible: tiles), seen: [.tilesMeter], today: 1) == nil)
        // The phone passes to someone else: they get their own.
        #expect(director.update(TipFacts(screen: .tiles, person: "b", visible: tiles), seen: [], today: 0) == .tilesMeter)
    }

    @Test func aTipComesDownWhenItsControlGoesOrTheScreenChanges() {
        var director = TipDirector()
        #expect(director.update(home(newHome), seen: [], today: 0) == .homeShelf)
        _ = director.update(home(["home.join"]), seen: [.homeShelf], today: 1)
        #expect(director.tip != .homeShelf)
        director.dismiss()
        #expect(director.update(TipFacts(screen: .lobby, person: "a", visible: ["lobby.share"]), seen: [], today: 1) == .lobbyShare)
        director.visit(.home)
        #expect(director.tip == nil)
    }

    // MARK: learned signals

    @Test func usingAControlTeachesItsTipEvenUnshown() {
        var director = TipDirector()
        #expect(director.used("home.join") == [.homeJoin])
        #expect(director.update(home(newHome), seen: [.homeShelf, .homePractice, .homeJoin], today: 0) == nil)
        // Seating someone teaches the seat and the add tips at once.
        #expect(director.used("lobby.seat") == [.lobbyAdd, .lobbySeat])
        #expect(UITip.learned(by: "tiles.turn") == [.tilesPlay, .tilesDraw])
        #expect(UITip.learned(by: "nothing").isEmpty)
    }

    @Test func usingTheControlPutsItsTipAway() {
        var director = TipDirector()
        #expect(director.update(home(newHome), seen: [], today: 0) == .homeShelf)
        #expect(director.used("home.join") == [.homeJoin])
        #expect(director.tip == .homeShelf, "another control leaves it up")
        #expect(director.used("home.newGame").contains(.homeShelf))
        #expect(director.tip == nil)
    }

    @Test func resetStartsTheCountsOver() {
        var director = TipDirector(pacing: TipPacing(perVisit: 1, perSession: 1, perDay: 9))
        #expect(director.update(home(newHome), seen: [], today: 0) == .homeShelf)
        director.dismiss()
        #expect(director.update(home(newHome), seen: [.homeShelf], today: 1) == nil)
        director.reset()
        #expect(director.update(home(newHome), seen: [], today: 0) == .homeShelf)
    }

    // MARK: storage

    @Test func aFileFromBeforeUITipsKeepsEveryGameTip() throws {
        let dir = try tempDir()
        // What earlier builds wrote: person to game tip names.
        try Data(#"{"a":["draw","goal"],"b":["cats"]}"#.utf8).write(to: dir.appendingPathComponent("tutorial.json"))
        let store = TutorialStore(directory: dir)
        #expect(store.loadUI().isEmpty)
        store.markSeen([UITip.homeShelf], person: "a")
        #expect(store.load()["a"] == [.goal, .draw])
        #expect(store.load()["b"] == [.cats])
        #expect(store.loadUI()["a"] == [.homeShelf])
        // And the other way: a game tip doesn't drop the UI tips.
        store.markSeen([CoachTip.discard], person: "a")
        #expect(store.loadUI()["a"] == [.homeShelf])
        #expect(TutorialStore(directory: dir).load()["a"] == [.goal, .draw, .discard])
    }

    @Test func namesFromANewerBuildAreKept() throws {
        let dir = try tempDir()
        try Data(#"{"a":["goal","ui.someday"]}"#.utf8).write(to: dir.appendingPathComponent("tutorial.json"))
        let store = TutorialStore(directory: dir)
        store.markSeen([UITip.homeJoin], person: "a")
        #expect(store.loadNames()["a"] == ["goal", "ui.someday", "ui.home.join"])
    }

    @Test func syncReplacingGameTipsKeepsUITipsAndMovesFollowThePerson() throws {
        let dir = try tempDir()
        let store = TutorialStore(directory: dir)
        store.markSeen([CoachTip.goal], person: "a")
        store.markSeen([UITip.lobbyStart], person: "a")
        store.replace(["a": [.draw]])
        #expect(store.load()["a"] == [.draw])
        #expect(store.loadUI()["a"] == [.lobbyStart])
        store.moveTips(from: "a", to: "z")
        #expect(store.loadUI()["z"] == [.lobbyStart])
        #expect(store.load()["z"] == [.draw])
        #expect(store.loadNames()["a"] == nil)
        store.reset()
        #expect(store.loadNames().isEmpty)
    }

    @Test func pacingCountsPerPersonPerDayAndOpensPerPhone() throws {
        let dir = try tempDir()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let store = TipPacingStore(directory: dir, calendar: calendar)
        #expect(store.opened() == 1)
        #expect(store.opened() == 2)
        let monday = Date(timeIntervalSince1970: 1_762_732_800)  // 2025-11-10 00:00 UTC
        store.noteShown(person: "a", on: monday)
        store.noteShown(person: "a", on: monday.addingTimeInterval(3600))
        store.noteShown(person: "b", on: monday)
        let reloaded = TipPacingStore(directory: dir, calendar: calendar)
        #expect(reloaded.shown(person: "a", on: monday) == 2)
        #expect(reloaded.shown(person: "b", on: monday) == 1)
        #expect(reloaded.shown(person: "a", on: monday.addingTimeInterval(86_400)) == 0, "a new day starts at zero")
        reloaded.noteShown(person: "a", on: monday.addingTimeInterval(86_400))
        #expect(reloaded.shown(person: "a", on: monday.addingTimeInterval(86_400)) == 1)
        reloaded.reset()
        #expect(reloaded.shown(person: "b", on: monday) == 0)
        #expect(reloaded.load().opens == 2)
    }
}
