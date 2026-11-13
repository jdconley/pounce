import XCTest

/// Accounts in the app (spec §10.5, §13.1, §14), against the Debug stub: `-stub-accounts
/// <scenario>` swaps both Sign in with Apple and the account routes for in-memory fakes, so no
/// Apple account and no server are needed.
@MainActor
final class AccountTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ scenario: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-stub-accounts", scenario] + extra
        app.launchEnvironment["POUNCE_API_BASE_URL"] = Live.baseURL
        app.launch()
        onboard(app)
        return app
    }

    private func openPeople(_ app: XCUIApplication) {
        el(app, "home.people").tap()
        XCTAssertTrue(el(app, "sheet-people").waitForExistence(timeout: Live.t(5)), "no people sheet")
    }

    /// Settings, on its Account page.
    private func openGear(_ app: XCUIApplication) {
        el(app, "home.settings").tap()
        XCTAssertTrue(el(app, "sheet-gear").waitForExistence(timeout: Live.t(5)), "no gear sheet")
        openSettingsAccount(app)
    }

    private func signedIn(_ e: XCUIElement) -> Bool { value(e) == "signed in" }

    func testSignInFromPeopleSheetUpgrades() {
        let app = launch("upgraded")
        openPeople(app)
        let offer = el(app, "people.signin")
        XCTAssertTrue(offer.waitForExistence(timeout: Live.t(5)), "no sign-in offer on the people sheet")
        XCTAssertFalse(signedIn(el(app, "people.owner")))
        offer.tap()
        XCTAssertTrue(until(5) { self.signedIn(self.el(app, "people.owner")) }, "the owner didn't sign in")
        XCTAssertTrue(until(3) { !offer.exists }, "the offer stays after signing in")
        XCTAssertFalse(el(app, "screen-merge").exists, "an upgrade is not a merge")
    }

    func testMergedShowsTwoCatsThenAccount() {
        let app = launch("merged")
        openPeople(app)
        el(app, "people.signin").tap()
        let done = el(app, "merge.done")
        XCTAssertTrue(done.waitForExistence(timeout: Live.t(5)), "a merge shows the two cats becoming one")
        XCTAssertFalse(el(app, "merge.back").exists, "a finished merge asks nothing")
        done.tap()
        XCTAssertTrue(until(5) { self.label(self.el(app, "people.owner")) == "Mia" }, "the account's name didn't arrive")
        XCTAssertTrue(signedIn(el(app, "people.owner")))
    }

    func testMergeNeededAsksFirst() {
        let app = launch("link-merge")
        openGear(app)
        XCTAssertTrue(el(app, "gear.account").waitForExistence(timeout: Live.t(5)), "not signed in")
        XCTAssertFalse(el(app, "gear.provider.apple").exists)
        el(app, "gear.link.apple").tap()
        let back = el(app, "merge.back")
        XCTAssertTrue(back.waitForExistence(timeout: Live.t(5)), "no merge question")
        XCTAssertTrue(el(app, "merge.confirm").exists)
        back.tap()
        XCTAssertTrue(until(3) { !back.exists }, "back doesn't close the question")
        XCTAssertFalse(el(app, "gear.provider.apple").exists, "back merged anyway")

        el(app, "gear.link.apple").tap()
        let confirm = el(app, "merge.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: Live.t(5)))
        confirm.tap()
        let done = el(app, "merge.done")
        if done.waitForExistence(timeout: Live.t(5)) { done.tap() }
        XCTAssertTrue(el(app, "gear.provider.apple").waitForExistence(timeout: Live.t(5)), "the provider didn't link")
    }

    func testCancelledSignInChangesNothing() {
        let app = launch("cancel")
        openPeople(app)
        let offer = el(app, "people.signin")
        XCTAssertTrue(offer.waitForExistence(timeout: Live.t(5)))
        offer.tap()
        Thread.sleep(forTimeInterval: Live.pace(1.5))
        XCTAssertTrue(offer.exists, "a cancelled sign-in removed the offer")
        XCTAssertFalse(signedIn(el(app, "people.owner")))
        XCTAssertFalse(el(app, "screen-merge").exists)
    }

    func testSignOutReturnsToGuest() {
        let app = launch("signed-in")
        openGear(app)
        XCTAssertTrue(el(app, "gear.account").waitForExistence(timeout: Live.t(5)), "not signed in")
        XCTAssertTrue(el(app, "gear.provider.apple").exists, "no Apple icon")
        el(app, "gear.signout").tap()
        XCTAssertTrue(el(app, "gear.signin").waitForExistence(timeout: Live.t(5)), "no offer after signing out")
        XCTAssertFalse(el(app, "gear.account").exists)
    }

    func testDeleteConfirmsThenShowsSettingsPath() {
        let app = launch("signed-in")
        openGear(app)
        el(app, "gear.delete").tap()
        let back = el(app, "delete.back")
        XCTAssertTrue(back.waitForExistence(timeout: Live.t(5)), "no delete confirm")
        XCTAssertEqual(el(app, "delete.title").label, "Delete your account?")
        back.tap()
        XCTAssertTrue(until(3) { !back.exists })
        XCTAssertTrue(el(app, "gear.account").exists, "back deleted anyway")

        el(app, "gear.delete").tap()
        el(app, "delete.confirm").tap()
        let path = el(app, "settings.path")
        XCTAssertTrue(path.waitForExistence(timeout: Live.t(5)), "no picture of the Settings path")
        el(app, "settings.path.done").tap()
        XCTAssertTrue(el(app, "gear.signin").waitForExistence(timeout: Live.t(5)), "still signed in after deleting")
    }

    func testAGuestCanDeleteToo() {
        let app = launch("upgraded")
        openGear(app)
        XCTAssertTrue(el(app, "gear.signin").exists, "a guest still gets the sign-in offer")
        let trash = el(app, "gear.delete")
        XCTAssertTrue(trash.waitForExistence(timeout: Live.t(5)), "no delete for a guest (guideline 5.1.1(v))")
        trash.tap()
        XCTAssertTrue(el(app, "delete.title").waitForExistence(timeout: Live.t(5)), "no delete confirm")
        XCTAssertEqual(el(app, "delete.title").label, "Delete your data?")
        XCTAssertTrue(el(app, "delete.detail").label.contains("It can't be undone."), "the confirm says what happens in words")
        el(app, "delete.confirm").tap()
        XCTAssertTrue(el(app, "deleted.done").waitForExistence(timeout: Live.t(5)), "no done after a guest's delete")
        XCTAssertFalse(el(app, "settings.path").exists, "a guest has no Apple sign-in to stop")
        el(app, "deleted.done").tap()
        XCTAssertTrue(el(app, "gear.signin").waitForExistence(timeout: Live.t(5)), "still a player who can sign in")
    }

    func testKittenSeesNoSignIn() {
        let app = launch("upgraded", ["-age-band", "kitten"])
        openPeople(app)
        Thread.sleep(forTimeInterval: Live.pace(1))
        XCTAssertFalse(el(app, "people.signin").exists, "a kitten was offered sign-in")
        el(app, "people.close").tap()
        XCTAssertTrue(until(3) { !self.el(app, "sheet-people").exists })
        openGear(app)
        XCTAssertFalse(el(app, "gear.signin").exists, "a kitten was offered sign-in")
        XCTAssertTrue(el(app, "gear.delete").exists, "a kitten's device can still delete its data")
    }

    func testHouseholdKittenPicksDiceName() {
        let app = launch("upgraded")
        openPeople(app)
        el(app, "people.add").tap()
        let kitten = el(app, "age.band.kitten")
        XCTAssertTrue(kitten.waitForExistence(timeout: Live.t(5)), "no age pictures for a new person")
        XCTAssertTrue(el(app, "age.band.teen").exists)
        XCTAssertTrue(el(app, "age.band.adult").exists)
        kitten.tap()
        XCTAssertTrue(el(app, "pickcat.generatedName").waitForExistence(timeout: Live.t(5)), "a kitten gets a generated name")
        XCTAssertFalse(app.textFields["pickcat.name"].exists)
        el(app, "pickcat.confirm").tap()
        let tile = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'people.person.'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: Live.t(5)), "the kitten wasn't added")
        tile.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: Live.pace(1))
        XCTAssertFalse(el(app, "people.signin.person").exists, "a kitten was offered sign-in")
    }

    /// Adds a teen with a dice name and returns their tile.
    private func addTeen(_ app: XCUIApplication) -> XCUIElement {
        el(app, "people.add").tap()
        let teen = el(app, "age.band.teen")
        XCTAssertTrue(teen.waitForExistence(timeout: Live.t(5)))
        teen.tap()
        XCTAssertTrue(el(app, "pickcat.dice").waitForExistence(timeout: Live.t(5)))
        el(app, "pickcat.dice").tap()
        _ = until(3) { app.keyboards.count == 0 }
        el(app, "pickcat.confirm").tap()
        let tile = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'people.person.'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: Live.t(5)))
        return tile
    }

    func testHouseholdHoldNeedsTheOwnerSignedIn() {
        // On a phone with no account the server would make the teen the phone's account.
        let app = launch("upgraded")
        openPeople(app)
        let tile = addTeen(app)
        tile.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: Live.pace(1))
        XCTAssertFalse(el(app, "people.signin.person").exists, "offered before the owner signed in")
    }

    func testKittenDeviceAddsKittens() {
        let app = launch("upgraded", ["-age-band", "kitten"])
        openPeople(app)
        el(app, "people.add").tap()
        XCTAssertTrue(el(app, "pickcat.generatedName").waitForExistence(timeout: Live.t(5)), "a dice name")
        XCTAssertFalse(el(app, "age.band.adult").exists, "a kitten picked someone's age")
        XCTAssertFalse(app.textFields["pickcat.name"].exists)
    }

    func testPersonFromBeforeAgesPicksABandFirst() {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-uitest-reset", "-seed-people", "-stub-accounts", "upgraded"]
        app.launch()
        XCTAssertTrue(el(app, "home.people").waitForExistence(timeout: Live.t(10)))
        openPeople(app)
        let ella = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'people.person.'")).firstMatch
        XCTAssertTrue(ella.waitForExistence(timeout: Live.t(5)))
        ella.tap()
        let grown = el(app, "age.band.adult")
        XCTAssertTrue(grown.waitForExistence(timeout: Live.t(5)), "no age pictures for a person with no band")
        grown.tap()
        XCTAssertTrue(app.textFields["pickcat.name"].waitForExistence(timeout: Live.t(5)), "a grown cat types a name")
    }

    func testHouseholdHoldSignsIn() {
        let app = launch("upgraded")
        openPeople(app)
        el(app, "people.signin").tap()
        XCTAssertTrue(until(5) { self.signedIn(self.el(app, "people.owner")) }, "the owner didn't sign in")
        el(app, "people.add").tap()
        let teen = el(app, "age.band.teen")
        XCTAssertTrue(teen.waitForExistence(timeout: Live.t(5)))
        teen.tap()
        XCTAssertTrue(el(app, "pickcat.dice").waitForExistence(timeout: Live.t(5)))
        el(app, "pickcat.dice").tap()
        _ = until(3) { app.keyboards.count == 0 }
        el(app, "pickcat.confirm").tap()
        let tile = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'people.person.'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: Live.t(5)))
        tile.press(forDuration: 1.2)
        let button = el(app, "people.signin.person")
        XCTAssertTrue(button.waitForExistence(timeout: Live.t(5)), "holding a cat offers that person sign-in")
        button.tap()
        XCTAssertTrue(until(5) { self.signedIn(tile) }, "the household person didn't sign in")
        XCTAssertTrue(signedIn(el(app, "people.owner")), "the owner is still the phone's account")

        // Their own account can be deleted from the app too.
        tile.press(forDuration: 1.2)
        let trash = el(app, "people.account.delete")
        XCTAssertTrue(trash.waitForExistence(timeout: Live.t(5)), "no way to delete their account")
        trash.tap()
        el(app, "delete.confirm").tap()
        let done = el(app, "settings.path.done")
        XCTAssertTrue(done.waitForExistence(timeout: Live.t(5)), "no Settings path after deleting")
        done.tap()
        XCTAssertTrue(until(5) { !self.signedIn(tile) }, "still signed in after deleting")
    }
}
