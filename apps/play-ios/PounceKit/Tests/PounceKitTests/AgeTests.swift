import Foundation
import Testing
@testable import PounceKit

@Suite struct AgeTests {
    private let calendar = Calendar(identifier: .gregorian)
    /// 4 November 2026, the spec's date.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))! }

    // MARK: Declared Age Range

    @Test func testRangesMapToBands() {
        #expect(AgeBand.from(lowerBound: nil, upperBound: 12) == .kitten)
        #expect(AgeBand.from(lowerBound: 0, upperBound: 12) == .kitten)
        #expect(AgeBand.from(lowerBound: 13, upperBound: 17) == .teen)
        #expect(AgeBand.from(lowerBound: 13, upperBound: nil) == .teen)
        #expect(AgeBand.from(lowerBound: 18, upperBound: nil) == .adult)
        #expect(AgeBand.from(lowerBound: nil, upperBound: nil) == nil)
    }

    @Test func testAnOpenLowerBoundCountsAsTheYoungest() {
        // "17 or under" could be a child: the youngest the person can be decides.
        #expect(AgeBand.from(lowerBound: nil, upperBound: 17) == .kitten)
    }

    // MARK: birth year

    @Test func testBirthYearsAtTheEdges() {
        #expect(AgeBand.from(birthYear: 2014, now: now, calendar: calendar) == .kitten)
        #expect(AgeBand.from(birthYear: 2013, now: now, calendar: calendar) == .kitten)
        #expect(AgeBand.from(birthYear: 2012, now: now, calendar: calendar) == .teen)
        #expect(AgeBand.from(birthYear: 2008, now: now, calendar: calendar) == .teen)
        #expect(AgeBand.from(birthYear: 2007, now: now, calendar: calendar) == .adult)
        #expect(AgeBand.from(birthYear: 1950, now: now, calendar: calendar) == .adult)
    }

    @Test func testFourDigitsMakeAYear() {
        var entry = BirthYearEntry()
        for d in [1, 9, 9, 0] { entry.type(d) }
        #expect(entry.digits == "1990")
        #expect(entry.year(now: now, calendar: calendar) == 1990)
    }

    @Test func testFutureYearIsNil() {
        var entry = BirthYearEntry()
        for d in [2, 0, 3, 0] { entry.type(d) }
        #expect(entry.year(now: now, calendar: calendar) == nil)
    }

    @Test func testThisYearIsAYear() {
        var entry = BirthYearEntry()
        for d in [2, 0, 2, 6] { entry.type(d) }
        #expect(entry.year(now: now, calendar: calendar) == 2026)
    }

    @Test func testTooOldIsNil() {
        var entry = BirthYearEntry()
        for d in [1, 9, 0, 6] { entry.type(d) }
        #expect(entry.year(now: now, calendar: calendar) == 1906)
        entry = BirthYearEntry()
        for d in [1, 9, 0, 5] { entry.type(d) }
        #expect(entry.year(now: now, calendar: calendar) == nil)
    }

    @Test func testLeadingZeroIsNil() {
        var entry = BirthYearEntry()
        for d in [0, 1, 9, 9] { entry.type(d) }
        #expect(entry.year(now: now, calendar: calendar) == nil)
    }

    @Test func testThreeDigitsIsNil() {
        var entry = BirthYearEntry()
        for d in [1, 9, 9] { entry.type(d) }
        #expect(entry.year(now: now, calendar: calendar) == nil)
    }

    @Test func testFifthDigitIgnored() {
        var entry = BirthYearEntry()
        for d in [1, 9, 9, 0, 7] { entry.type(d) }
        #expect(entry.digits == "1990")
    }

    @Test func testDeleteOnEmpty() {
        var entry = BirthYearEntry()
        entry.delete()
        #expect(entry.digits.isEmpty)
        entry.type(4)
        entry.type(2)
        entry.delete()
        #expect(entry.digits == "4")
    }

    @Test func testOnlyDigitsAreTyped() {
        var entry = BirthYearEntry()
        entry.type(12)
        entry.type(-1)
        #expect(entry.digits.isEmpty)
    }

    // MARK: record

    @Test func testRecheckAfterAWeek() {
        let record = AgeRecord(band: .kitten, source: .keypad, checkedAt: now)
        #expect(!record.needsRecheck(now: now.addingTimeInterval(6 * 86_400)))
        #expect(record.needsRecheck(now: now.addingTimeInterval(7 * 86_400)))
    }

    @Test func testMemoryStoreKeepsTheRecord() {
        let store = MemoryAgeRecordStore()
        #expect(store.load() == nil)
        let record = AgeRecord(band: .teen, source: .declared, checkedAt: now)
        store.save(record)
        #expect(store.load() == record)
    }

    // MARK: limits

    @Test func testKittenLimits() {
        let limits = AgeLimits(band: .kitten)
        #expect(!limits.signInOffered)
        #expect(!limits.uploadsPushToken)
        // The local turn reminder is on the device only, so a kitten's starts on.
        #expect(limits.turnReminderDefault)
        #expect(!limits.typedNames)
        #expect(!limits.sharesLinks)
    }

    @Test func testUnknownBandIsLimitedLikeAKitten() {
        var unknown = AgeLimits(band: nil)
        #expect(!unknown.turnReminderDefault)
        unknown.turnReminderDefault = true
        #expect(unknown == AgeLimits(band: .kitten))
    }

    // MARK: correction

    @Test func testCorrectionOfferedOnlyWhileLimited() {
        #expect(!AgeCorrection.offered(nil))
        #expect(AgeCorrection.offered(AgeRecord(band: .kitten, source: .keypad, checkedAt: now)))
        #expect(AgeCorrection.offered(AgeRecord(band: .teen, source: .keypad, checkedAt: now)))
        #expect(AgeCorrection.offered(AgeRecord(band: .kitten, source: .declared, checkedAt: now)))
        #expect(!AgeCorrection.offered(AgeRecord(band: .adult, source: .keypad, checkedAt: now)))
    }

    @Test func testOnlyTheSystemsAnswerChangesTheBand() {
        let typed = AgeRecord(band: .kitten, source: .keypad, checkedAt: now)
        let later = now.addingTimeInterval(60)
        // Declined or unavailable: nothing changes, not even the date.
        #expect(AgeCorrection.corrected(typed, answer: nil, now: later) == typed)
        #expect(AgeCorrection.corrected(typed, answer: .adult, now: later)
            == AgeRecord(band: .adult, source: .declared, checkedAt: later))
        // Apple says kitten: still a kitten, now from the system.
        #expect(AgeCorrection.corrected(typed, answer: .kitten, now: later).band == .kitten)
    }

    // MARK: prompts

    @Test func testSignInPromptForSignedOutAdultsWithAPair() {
        #expect(SignInPrompt.shows(band: .adult, signedIn: false, offersSignIn: true, pairs: 1, dismissed: false))
        #expect(!SignInPrompt.shows(band: .adult, signedIn: false, offersSignIn: true, pairs: 0, dismissed: false))
        #expect(!SignInPrompt.shows(band: .adult, signedIn: true, offersSignIn: true, pairs: 1, dismissed: false))
        #expect(!SignInPrompt.shows(band: .adult, signedIn: false, offersSignIn: false, pairs: 1, dismissed: false))
        #expect(!SignInPrompt.shows(band: .adult, signedIn: false, offersSignIn: true, pairs: 1, dismissed: true))
        #expect(!SignInPrompt.shows(band: .teen, signedIn: false, offersSignIn: true, pairs: 1, dismissed: false))
        #expect(!SignInPrompt.shows(band: .kitten, signedIn: false, offersSignIn: true, pairs: 1, dismissed: false))
    }

    @Test func testKittenTablePromptOnTheKittensDevice() {
        #expect(KittenTablePrompt.forKitten(isKitten: true, consented: false, held: false) == .showCode)
        #expect(KittenTablePrompt.forKitten(isKitten: true, consented: true, held: false) == nil)
        #expect(KittenTablePrompt.forKitten(isKitten: true, consented: false, held: true) == nil)
        #expect(KittenTablePrompt.forKitten(isKitten: false, consented: false, held: false) == nil)
    }

    @Test func testKittenTablePromptOnTheParentsDevice() {
        let mochi = ParentKitten(id: "k_1", name: "Mochi", cat: 3, state: .pending, mode: .parent, people: [])
        let on = ParentKitten(id: "k_2", name: "Pickle", cat: 5, state: .on, mode: .parent, people: [])
        let seated = [Person(id: "p1", name: "Mochi", cat: 3), Person(id: "p2", name: "Pickle", cat: 5)]
        #expect(KittenTablePrompt.forParent(isParent: true, kittens: [on, mochi], others: seated)
            == .finish(kitten: "k_1", name: "Mochi"))
        #expect(KittenTablePrompt.forParent(isParent: false, kittens: [mochi], others: seated) == nil)
        #expect(KittenTablePrompt.forParent(isParent: true, kittens: [on], others: seated) == nil)
        // Same name, another cat: not this kitten.
        #expect(KittenTablePrompt.forParent(isParent: true, kittens: [mochi], others: [Person(id: "p", name: "Mochi", cat: 1)]) == nil)
    }

    @Test func testTeenAndAdultLimits() {
        for band in [AgeBand.teen, .adult] {
            let limits = AgeLimits(band: band)
            #expect(limits.signInOffered)
            #expect(limits.uploadsPushToken)
            #expect(limits.turnReminderDefault)
            #expect(limits.typedNames)
            #expect(limits.sharesLinks)
        }
    }

    @Test func testGeneratedNamesNeedNoChange() {
        #expect(!AgeLimits.needsGeneratedName("Mochi"))
        #expect(AgeLimits.needsGeneratedName("Ella"))
    }

    // MARK: significant change

    @Test func testSignificantChangeTable() {
        typealias S = SignificantChange
        #expect(S.action(requiresConsent: true, requiresNotice: false, band: .teen, isNewInstall: false, done: false) == .askParent)
        #expect(S.action(requiresConsent: true, requiresNotice: false, band: .kitten, isNewInstall: false, done: false) == .askParent)
        #expect(S.action(requiresConsent: true, requiresNotice: true, band: .adult, isNewInstall: false, done: false) == .notifyAdult)
        #expect(S.action(requiresConsent: false, requiresNotice: false, band: .teen, isNewInstall: false, done: false) == .none)
        #expect(S.action(requiresConsent: true, requiresNotice: true, band: .teen, isNewInstall: true, done: false) == .none)
        #expect(S.action(requiresConsent: true, requiresNotice: true, band: .teen, isNewInstall: false, done: true) == .none)
        #expect(S.action(requiresConsent: false, requiresNotice: true, band: .teen, isNewInstall: false, done: false) == .none)
    }
}
