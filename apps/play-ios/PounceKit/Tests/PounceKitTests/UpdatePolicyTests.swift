import Foundation
import Testing
@testable import PounceKit

private let day: TimeInterval = 24 * 60 * 60
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct SoftPromptTests {
    private func soft(
        current: String = "1.1", latest: String? = "1.2", minimum: String? = nil, channel: InstallChannel = .appStore,
        state: SoftPromptState = SoftPromptState(), now: Date = t0, staged: Bool = false
    ) -> String? {
        UpdatePolicy.soft(
            current: current, status: AppStatus(latest: latest, minimum: minimum), channel: channel, state: state, now: now,
            staged: staged)
    }

    @Test func showsWhenTheStoreHasSomethingNewer() {
        #expect(soft() == "1.2")
        #expect(soft(current: "1.1", latest: "1.1.1") == "1.1.1")
        #expect(soft(current: "1.9", latest: "1.10") == "1.10")
    }

    @Test func neverWhenThereIsNothingNewer() {
        #expect(soft(latest: "1.1") == nil)
        #expect(soft(latest: "1.1.0") == nil)
        #expect(soft(latest: "1.0") == nil)
        #expect(soft(current: "1.10", latest: "1.9") == nil)
    }

    @Test func neverWhenNobodyKnows() {
        #expect(soft(latest: nil) == nil)
        #expect(soft(latest: "") == nil)
        #expect(soft(latest: "soon") == nil)
        #expect(soft(current: "dev", latest: "1.2") == nil)
        #expect(UpdatePolicy.soft(current: "1.1", status: nil, channel: .appStore, state: SoftPromptState(), now: t0) == nil)
    }

    @Test func neverOnTestFlightOrInAStagedRun() {
        #expect(soft(channel: .testFlight) == nil)
        #expect(soft(staged: true) == nil)
    }

    @Test func neverWhenTheAppIsTooOldToRun() {
        // That has its own screen.
        #expect(soft(latest: "1.3", minimum: "1.2") == nil)
        #expect(soft(latest: "1.3", minimum: "1.1") == "1.3")
    }

    @Test func oncePerVersion() {
        let closed = UpdatePolicy.dismissed(SoftPromptState(), version: "1.2", now: t0)
        #expect(closed == SoftPromptState(dismissedVersion: "1.2", dismissedAt: t0))
        // The same version never comes back, however long it has been.
        #expect(soft(state: closed, now: t0 + 1) == nil)
        #expect(soft(state: closed, now: t0 + 8 * day) == nil)
        #expect(soft(state: closed, now: t0 + 400 * day) == nil)
        #expect(soft(latest: "1.2.0", state: closed, now: t0 + 8 * day) == nil)
    }

    @Test func aNewerVersionWaitsOutTheWeekAfterAClose() {
        let closed = UpdatePolicy.dismissed(SoftPromptState(), version: "1.2", now: t0)
        #expect(soft(latest: "1.3", state: closed, now: t0 + day) == nil)
        #expect(soft(latest: "1.3", state: closed, now: t0 + 7 * day - 1) == nil)
        #expect(soft(latest: "1.3", state: closed, now: t0 + 7 * day) == "1.3")
        #expect(UpdatePolicy.quietAfterDismiss == 7 * day)
    }

    @Test func aClockSetBackDoesNotHideTheCardForever() {
        let closed = SoftPromptState(dismissedVersion: "1.2", dismissedAt: t0 + 30 * day)
        #expect(soft(latest: "1.3", state: closed, now: t0) == "1.3")
    }

    @Test func closingNeverGoesBackwards() {
        var state = UpdatePolicy.dismissed(SoftPromptState(), version: "1.3", now: t0)
        state = UpdatePolicy.dismissed(state, version: "1.2", now: t0 + day)
        #expect(state == SoftPromptState(dismissedVersion: "1.3", dismissedAt: t0 + day))
        state = UpdatePolicy.dismissed(state, version: "nonsense", now: t0 + 2 * day)
        #expect(state == SoftPromptState(dismissedVersion: "1.3", dismissedAt: t0 + 2 * day))
    }

    @Test func somethingUnreadableRememberedIsNothingRemembered() {
        #expect(soft(state: SoftPromptState(dismissedVersion: "???", dismissedAt: nil)) == "1.2")
    }
}

@Suite struct UpdateRequiredTests {
    @Test func belowTheMinimumIsTooOld() {
        #expect(UpdatePolicy.isRequired(current: "1.1", status: AppStatus(latest: "1.2", minimum: "1.2")))
        #expect(UpdatePolicy.isRequired(current: "1.1.9", status: AppStatus(minimum: "1.2")))
    }

    @Test func atOrAboveItIsNot() {
        #expect(!UpdatePolicy.isRequired(current: "1.2", status: AppStatus(minimum: "1.2")))
        #expect(!UpdatePolicy.isRequired(current: "1.2.0", status: AppStatus(minimum: "1.2")))
        #expect(!UpdatePolicy.isRequired(current: "1.10", status: AppStatus(minimum: "1.2")))
    }

    @Test func noMinimumOrAnUnreadableOneRetiresNobody() {
        #expect(!UpdatePolicy.isRequired(current: "1.1", status: AppStatus(latest: "1.2")))
        #expect(!UpdatePolicy.isRequired(current: "1.1", status: AppStatus(minimum: "")))
        #expect(!UpdatePolicy.isRequired(current: "1.1", status: AppStatus(minimum: "soon")))
        #expect(!UpdatePolicy.isRequired(current: "1.1", status: nil))
        #expect(!UpdatePolicy.isRequired(current: "dev", status: AppStatus(minimum: "1.2")))
    }

    @Test func refreshesEverySixHours() {
        #expect(UpdatePolicy.shouldRefresh(fetchedAt: nil, now: t0))
        #expect(!UpdatePolicy.shouldRefresh(fetchedAt: t0, now: t0 + 60))
        #expect(!UpdatePolicy.shouldRefresh(fetchedAt: t0, now: t0 + 6 * 3600 - 1))
        #expect(UpdatePolicy.shouldRefresh(fetchedAt: t0, now: t0 + 6 * 3600))
        // A clock set back: ask again rather than wait for it to catch up.
        #expect(UpdatePolicy.shouldRefresh(fetchedAt: t0 + 3600, now: t0))
    }

    /// The server answers from what it knows and never waits on Apple, so a first answer can be empty.
    @Test func anAnswerThatNamedNoVersionIsAskedForAgainWithinTheHour() {
        let nothing = AppStatus(testflightUrl: "https://testflight.apple.com/join/abc")
        #expect(!UpdatePolicy.shouldRefresh(fetchedAt: t0, now: t0 + 3600 - 1, status: nothing))
        #expect(UpdatePolicy.shouldRefresh(fetchedAt: t0, now: t0 + 3600, status: nothing))
        #expect(UpdatePolicy.shouldRefresh(fetchedAt: t0, now: t0 + 3600, status: AppStatus(latest: "soon")))
        // One that named a version keeps its six hours.
        #expect(!UpdatePolicy.shouldRefresh(fetchedAt: t0, now: t0 + 3600, status: AppStatus(latest: "1.1")))
        #expect(UpdatePolicy.shouldRefresh(fetchedAt: t0, now: t0 + 6 * 3600, status: AppStatus(latest: "1.1")))
    }
}

@Suite struct UpdateActionTests {
    private let store = "https://apps.apple.com/us/app/pounce/id6829560061"
    private let beta = "https://testflight.apple.com/join/ABEeCJbe"

    @Test func aGrownUpOnAnAppStoreInstallGoesToTheStore() {
        for band in [AgeBand.teen, .adult] {
            #expect(UpdatePolicy.action(channel: .appStore, band: band, storeUrl: store, testflightUrl: beta) == .store(URL(string: store)!))
        }
    }

    @Test func withoutAListingFromTheServerTheBuiltInOne() {
        #expect(UpdatePolicy.action(channel: .appStore, band: .adult, storeUrl: nil, testflightUrl: nil) == .store(UpdatePolicy.storeURL))
        #expect(UpdatePolicy.storeURL.absoluteString == "https://apps.apple.com/app/id6829560061")
    }

    @Test func aTestFlightInstallGoesToTestFlightNeverTheStore() {
        #expect(UpdatePolicy.action(channel: .testFlight, band: .adult, storeUrl: store, testflightUrl: beta) == .testFlight(URL(string: beta)!))
        #expect(UpdatePolicy.action(channel: .testFlight, band: .teen, storeUrl: store, testflightUrl: nil) == .testFlight(UpdatePolicy.testFlightURL))
    }

    @Test func aChildIsNeverSentAnywhere() {
        for channel in [InstallChannel.appStore, .testFlight] {
            #expect(UpdatePolicy.action(channel: channel, band: .kitten, storeUrl: store, testflightUrl: beta) == .askGrownUp)
            // An age that isn't known yet counts as the most limited.
            #expect(UpdatePolicy.action(channel: channel, band: nil, storeUrl: store, testflightUrl: beta) == .askGrownUp)
        }
    }

    @Test(arguments: [
        "http://apps.apple.com/app/id6829560061", "https://apps.apple.com.evil.example/app/id1", "https://example.com/app",
        "javascript:alert(1)", "itms-apps://apps.apple.com/app/id1", "https://user@apps.apple.com/app/id1", "", "not a url",
    ])
    func aLinkThatIsNotApplesIsNotFollowed(link: String) {
        #expect(UpdatePolicy.action(channel: .appStore, band: .adult, storeUrl: link, testflightUrl: nil) == .store(UpdatePolicy.storeURL))
        #expect(UpdatePolicy.action(channel: .testFlight, band: .adult, storeUrl: nil, testflightUrl: link) == .testFlight(UpdatePolicy.testFlightURL))
    }

    @Test func aStoreLinkIsNotATestFlightLink() {
        #expect(UpdatePolicy.action(channel: .testFlight, band: .adult, storeUrl: nil, testflightUrl: store) == .testFlight(UpdatePolicy.testFlightURL))
    }
}

@Suite struct TableAdviceTests {
    private func advice(latest: String?, channel: InstallChannel = .appStore, band: AgeBand? = .adult) -> UpdatePolicy.TableAdvice {
        UpdatePolicy.tableAdvice(current: "1.1", status: latest.map { AppStatus(latest: $0) }, channel: channel, band: band)
    }

    @Test func updateWhenTheStoreHasSomethingNewer() {
        #expect(advice(latest: "1.2") == .update)
        #expect(advice(latest: "1.2", band: .teen) == .update)
    }

    @Test func nobodyIsSentToTheStoreForAVersionThatIsNotThere() {
        #expect(advice(latest: "1.1") == .notYet)
        #expect(advice(latest: nil) == .notYet)
        #expect(advice(latest: nil, band: .kitten) == .notYet)
    }

    @Test func aChildAsksAGrownUp() {
        #expect(advice(latest: "1.2", band: .kitten) == .askGrownUp)
        #expect(advice(latest: "1.2", band: nil) == .askGrownUp)
        #expect(advice(latest: nil, channel: .testFlight, band: .kitten) == .askGrownUp)
    }

    @Test func aBetaIsPointedAtTestFlightWhateverTheStoreHas() {
        #expect(advice(latest: nil, channel: .testFlight) == .updateInTestFlight)
        #expect(advice(latest: "1.1", channel: .testFlight) == .updateInTestFlight)
        #expect(advice(latest: "1.2", channel: .testFlight, band: .teen) == .updateInTestFlight)
    }

    @Test func theGamesNameIsTheServersThenTheShelfsThenNone() {
        #expect(UpdatePolicy.gameTitle(id: "tiles", serverTitle: "Tuna Tiles Deluxe") == "Tuna Tiles Deluxe")
        #expect(UpdatePolicy.gameTitle(id: "tiles", serverTitle: nil) == GameCatalog.tiles.title)
        #expect(UpdatePolicy.gameTitle(id: "chess", serverTitle: nil) == nil)
    }
}

@Suite struct LockedTablesTests {
    private func invite(_ code: String, game: String = "tiles", at: Date = t0) -> LockedInvite {
        LockedInvite(code: code, game: game, title: "Tuna Tiles", at: at)
    }

    @Test func remembersARefusedTableNewestFirstOncePerTable() {
        var list = LockedTables.remembering([], code: "GH2VD", game: "tiles", title: "Tuna Tiles", now: t0)
        list = LockedTables.remembering(list, code: "TB4XN", game: "tiles", title: nil, now: t0 + 60)
        list = LockedTables.remembering(list, code: "GH2VD", game: "tiles", title: nil, now: t0 + 120)
        #expect(list.map(\.code) == ["GH2VD", "TB4XN"])
        // A second refusal that names no game keeps the name it had.
        #expect(list[0] == LockedInvite(code: "GH2VD", game: "tiles", title: "Tuna Tiles", at: t0 + 120))
    }

    @Test func keepsTheNewestTen() {
        var list: [LockedInvite] = []
        for i in 0..<14 { list = LockedTables.remembering(list, code: "T\(i)", game: "tiles", title: nil, now: t0 + Double(i)) }
        #expect(list.count == LockedTables.limit)
        #expect(list.first?.code == "T13")
        #expect(!list.contains { $0.code == "T0" })
    }

    @Test func forgetsAfterThirtyDays() {
        let list = [invite("NEWER", at: t0), invite("OLDER", at: t0 - 31 * day)]
        #expect(LockedTables.pruned(list, now: t0 + day).map(\.code) == ["NEWER"])
        #expect(LockedTables.pruned(list, now: t0 + 30 * day).isEmpty)
    }

    @Test func rowsAreTheServersThenThisDevicesWithoutRepeats() {
        let server = [LockedTable(code: "GH2VD", name: "Taco Night", game: "tiles", title: "Tuna Tiles", updatedAt: 1_800_000_000_000)]
        let rows = LockedTables.rows(
            server: server, local: [invite("GH2VD"), invite("TB4XN")], listed: [], drawable: ["cat-tower"], now: t0)
        #expect(rows.map(\.id) == ["GH2VD", "TB4XN"])
        #expect(rows[0].invite.name == "Taco Night")
        #expect(rows[0].invite.at == t0)
        #expect(rows.allSatisfy { !$0.opens })
    }

    @Test func aTableTheAppAlreadyListsIsNotLocked() {
        let rows = LockedTables.rows(
            server: [LockedTable(code: "GH2VD", game: "tiles", updatedAt: 0)], local: [invite("TB4XN")], listed: ["GH2VD", "TB4XN"],
            drawable: ["cat-tower", "tiles"], now: t0)
        #expect(rows.isEmpty)
    }

    @Test func afterTheUpdateTheSameRowOpensTheTable() {
        let rows = LockedTables.rows(server: [], local: [invite("TB4XN"), invite("QQQQQ", game: "chess")], listed: [], drawable: ["cat-tower", "tiles"], now: t0)
        #expect(rows.map(\.opens) == [true, false])
    }

    @Test func nothingLockedMeansNoRows() {
        #expect(LockedTables.rows(server: [], local: [], listed: ["BCDFG"], drawable: ["cat-tower"], now: t0).isEmpty)
        #expect(LockedTables.rows(server: [], local: [invite("OLD", at: t0 - 40 * day)], listed: [], drawable: [], now: t0).isEmpty)
    }
}

@Suite struct UpdateStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pounce-updates-\(UUID().uuidString)")
    }

    @Test func startsEmptyAndKeepsWhatItIsTold() {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UpdateStore(directory: dir)
        #expect(store.load() == UpdateRecord())
        store.update { record in
            record.status = AppStatus(latest: "1.2", storeUrl: "https://apps.apple.com/app/id6829560061")
            record.fetchedAt = t0
            record.soft = SoftPromptState(dismissedVersion: "1.2", dismissedAt: t0)
            record.locked = [LockedInvite(code: "GH2VD", game: "tiles", title: "Tuna Tiles", at: t0)]
        }
        let again = UpdateStore(directory: dir).load()
        #expect(again.status?.latest == "1.2")
        #expect(again.fetchedAt == t0)
        #expect(again.soft.dismissedVersion == "1.2")
        #expect(again.locked.map(\.code) == ["GH2VD"])
    }

    @Test func aFileItCannotReadIsAnEmptyRecordAndAPartItCannotReadIsAnEmptyPart() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("updates.json")
        try Data("not json".utf8).write(to: file)
        #expect(UpdateStore(directory: dir).load() == UpdateRecord())
        try Data(#"{"soft":{"dismissedVersion":"1.2"},"locked":"what","status":{"latest":7}}"#.utf8).write(to: file)
        let record = UpdateStore(directory: dir).load()
        #expect(record.soft.dismissedVersion == "1.2")
        #expect(record.locked.isEmpty)
        #expect(record.status == AppStatus())
    }
}

/// The update push (play-api `notify/update.ts`): what this version does with it, and what the
/// payload must never carry, since version 1.0 gets the same bytes.
@Suite struct UpdatePushTests {
    private let userInfo: [AnyHashable: Any] = [
        "aps": [
            "alert": ["title": "Couch Cats", "body": "Mia wants to play Tuna Tiles. Update Pounce to join."],
            "sound": "default", "thread-id": "update:GH2VD", "category": "STATUS", "interruption-level": "active",
            "relevance-score": 0.9,
        ] as [String: Any],
        "kind": "update",
        "from": ["name": "Mia", "cat": 2] as [String: Any],
        "update": ["code": "GH2VD", "game": "tiles"],
    ]

    @Test func aTapOpensItsTable() throws {
        let payload = try #require(PushPayload(userInfo: userInfo))
        #expect(payload.kind == .update)
        #expect(payload.updateCode == "GH2VD")
        #expect(payload.body == "Mia wants to play Tuna Tiles. Update Pounce to join.")
        #expect(NotifyActions.outcome(action: NotifyActions.defaultAction, payload: payload) == .open("GH2VD"))
    }

    /// What version 1.0 reads of the same payload: no table to open, no buttons, not a
    /// communication notification, nothing for the widgets. It shows the words and a tap opens the app.
    @Test func itCarriesNothingAnOlderAppWouldActOn() throws {
        let payload = try #require(PushPayload(userInfo: userInfo))
        #expect(payload.code == nil)
        #expect(payload.category == .status)
        #expect(NotifyActions.actions(for: .status).isEmpty)
        #expect(payload.streak == nil)
        #expect(payload.pounce == nil)
        #expect(CommunicationPlan.make(payload) == nil)
        // 1.0 has no name for the kind: with no top-level code its tap does nothing but open the app.
        var old = payload
        old.kind = .unknown
        old.updateCode = nil
        #expect(NotifyActions.outcome(action: NotifyActions.defaultAction, payload: old) == .none)
    }

    @Test func aCodeThatIsNotOneOpensNothing() throws {
        var bad = userInfo
        bad["update"] = ["code": "not a code"]
        let payload = try #require(PushPayload(userInfo: bad))
        #expect(payload.updateCode == nil)
        #expect(NotifyActions.outcome(action: NotifyActions.defaultAction, payload: payload) == .none)
    }
}
