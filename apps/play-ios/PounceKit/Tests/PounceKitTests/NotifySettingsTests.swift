import Foundation
import Testing
@testable import PounceKit

/// The synced notification settings (spec §12.3, §12.6, §14.1), mirroring play-api's
/// `src/notify/settings.ts` and `src/notify/schedule.ts`.
@Suite struct NotifySettingsTests {
    private func t(_ h: Int, _ m: Int = 0) -> ClockTime { ClockTime(h: h, m: m) }

    @Test func adultDefaults() {
        let s = NotifySettings.defaults(band: .adult)
        #expect(s == NotifySettings(
            reminders: true, auto: true, weekday: t(19, 30), weekend: t(19, 30), quietStart: t(22), quietEnd: t(8),
            lastChance: true))
        #expect(NotifySettings.defaults(band: nil) == s)
    }

    @Test func teenDefaultsAreGentle() {
        let s = NotifySettings.defaults(band: .teen)
        #expect(!s.reminders && !s.auto && !s.lastChance)
        #expect(s.quietStart == t(21) && s.quietEnd == t(8))
        #expect(s.weekday == t(19, 30))
    }

    @Test func kittenGetsNothingFromTheServer() {
        let s = NotifySettings.defaults(band: .kitten)
        #expect(!s.reminders && !s.auto && !s.lastChance)
        let set: SyncSection = [NotifyKey.reminders: SyncEntry(v: .bool(true), at: 5), NotifyKey.auto: SyncEntry(v: .bool(true), at: 5)]
        let r = NotifySettings.resolve(set, band: .kitten)
        #expect(!r.reminders && !r.auto)
    }

    @Test func syncedValuesOverrideAndMalformedFallBack() {
        let section: SyncSection = [
            NotifyKey.reminders: SyncEntry(v: .bool(true), at: 1),
            NotifyKey.weekday: SyncEntry(v: .object(["h": .number(7), "m": .number(15)]), at: 1),
            NotifyKey.weekend: SyncEntry(v: .object(["h": .number(25), "m": .number(0)]), at: 1),
            NotifyKey.quietStart: SyncEntry(v: .string("late"), at: 1),
            NotifyKey.lastChance: SyncEntry(v: .number(1), at: 1),
        ]
        let s = NotifySettings.resolve(section, band: .teen)
        #expect(s.reminders)
        #expect(!s.auto)
        #expect(s.weekday == t(7, 15))
        #expect(s.weekend == t(19, 30))
        #expect(s.quietStart == t(21))
        #expect(!s.lastChance)
    }

    @Test func clockTimesWrapAndEncodeAsTheServerReadsThem() {
        #expect(ClockTime(minutes: -15) == t(23, 45))
        #expect(ClockTime(minutes: 24 * 60 + 30) == t(0, 30))
        #expect(t(19, 30).minutes == 1170)
        #expect(t(7, 5).text == "07:05")
        #expect(t(19, 30).json == .object(["h": .number(19), "m": .number(30)]))
    }

    @Test func quietHours() {
        #expect(NotifySettings.inQuiet(23 * 60, start: t(22), end: t(8)))
        #expect(NotifySettings.inQuiet(7 * 60 + 59, start: t(22), end: t(8)))
        #expect(!NotifySettings.inQuiet(8 * 60, start: t(22), end: t(8)))
        #expect(!NotifySettings.inQuiet(21 * 60 + 59, start: t(22), end: t(8)))
        #expect(!NotifySettings.inQuiet(23 * 60, start: t(22), end: t(22)))
    }

    /// The same cases as play-api's `clampReminder` test.
    @Test func reminderClampMatchesTheServer() {
        let adult = NotifySettings.defaults(band: .adult)
        #expect(adult.clamped(t(21, 30)) == t(20))
        #expect(adult.clamped(t(6)) == t(8))
        #expect(adult.clamped(t(1)) == t(20))
        #expect(adult.clamped(t(12)) == t(12))
        var morning = adult
        morning.quietStart = t(10)
        morning.quietEnd = t(12)
        #expect(morning.clamped(t(19, 30)) == t(8))
        #expect(NotifySettings.defaults(band: .teen).clamped(t(19, 30)) == t(19))
    }

    @Test func testClampWrapsMidnight() {
        var s = NotifySettings.defaults(band: .adult)
        s.quietStart = t(23)
        s.quietEnd = t(1)
        #expect(s.clamped(t(0, 30)) == t(21))
        #expect(s.clamped(t(20, 45)) == t(20, 45))
    }

    @Test func testDegenerateQuietMatchesServer() {
        var s = NotifySettings.defaults(band: .adult)
        s.quietEnd = s.quietStart
        #expect(s.clamped(t(21, 30)) == t(20))
        #expect(s.clamped(t(12)) == t(12))
    }

    @Test func lastChanceIsNinetyMinutesBeforeQuiet() {
        #expect(NotifySettings.defaults(band: .adult).lastChanceTime == t(20, 30))
    }

    @Test func kittenReminderIsFixed() {
        #expect(KittenReminder.time == t(17))
        #expect(KittenReminder.id == "kitten-daily")
    }
}

@MainActor @Suite struct NotifySettingsStoreTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("notify-\(UUID().uuidString).json")
    }

    @Test func setWritesAnEntryAndMarksItUnsent() {
        let store = NotifySettingsStore(file: file())
        store.set(NotifyKey.reminders, .bool(false), now: 10)
        #expect(store.entries[NotifyKey.reminders] == SyncEntry(v: .bool(false), at: 10))
        #expect(store.settings(band: .adult).reminders == false)
        let patch = store.pendingPatch(band: .adult)
        #expect(patch == StatePatch(settings: [NotifyKey.reminders: SyncEntry(v: .bool(false), at: 10)]))
        store.sent(patch!)
        #expect(store.pendingPatch(band: .adult) == nil)
    }

    @Test func aValueChangedWhileSendingStaysUnsent() {
        let store = NotifySettingsStore(file: file())
        store.set(NotifyKey.auto, .bool(false), now: 10)
        let patch = store.pendingPatch(band: .adult)!
        store.set(NotifyKey.auto, .bool(true), now: 20)
        store.sent(patch)
        #expect(store.pendingPatch(band: .adult)?.settings?[NotifyKey.auto]?.v == .bool(true))
    }

    @Test func testUnsentSurvivesFailure() {
        let url = file()
        do {
            let store = NotifySettingsStore(file: url)
            store.set(NotifyKey.weekday, ClockTime(h: 7, m: 0).json, now: 10)
            store.set(NotifyKey.weekday, ClockTime(h: 7, m: 30).json, now: 11)
        }
        let again = NotifySettingsStore(file: url)
        #expect(again.pendingPatch(band: .teen)?.settings?[NotifyKey.weekday] == SyncEntry(v: ClockTime(h: 7, m: 30).json, at: 11))
        #expect(again.settings(band: .teen).weekday == ClockTime(h: 7, m: 30))
    }

    @Test func testKittenSendsNothing() {
        let store = NotifySettingsStore(file: file())
        store.set(NotifyKey.reminders, .bool(true), now: 10)
        #expect(store.pendingPatch(band: .kitten) == nil)
        #expect(store.pendingPatch(band: nil) == nil)
        #expect(store.values(band: .kitten).isEmpty)
        #expect(store.values(band: .adult) == [NotifyKey.reminders: .bool(true)])
    }

    /// Review fix: a signed-in device whose band isn't known yet must not read as "every key went
    /// away" in the account's settings ledger (which would write nulls over the account's choices).
    @Test func anUnknownBandKeepsTheLedgerValues() {
        let store = NotifySettingsStore(file: file())
        store.set(NotifyKey.quietStart, ClockTime(h: 23, m: 0).json, now: 10)
        #expect(store.values(band: nil) == [NotifyKey.quietStart: ClockTime(h: 23, m: 0).json])
    }

    @Test func takeRemoteKeepsTheNewer() {
        let store = NotifySettingsStore(file: file())
        store.set(NotifyKey.reminders, .bool(false), now: 50)
        store.takeRemote([
            NotifyKey.reminders: SyncEntry(v: .bool(true), at: 40),
            NotifyKey.lastChance: SyncEntry(v: .bool(false), at: 60),
            "soundOn": SyncEntry(v: .bool(false), at: 99),
        ])
        #expect(store.entries[NotifyKey.reminders]?.v == .bool(false))
        #expect(store.entries[NotifyKey.lastChance] == SyncEntry(v: .bool(false), at: 60))
        #expect(store.entries["soundOn"] == nil)
        // A remote write that is newer than a local unsent one wins and isn't sent back.
        store.takeRemote([NotifyKey.reminders: SyncEntry(v: .bool(true), at: 70)])
        #expect(store.entries[NotifyKey.reminders]?.v == .bool(true))
        #expect(store.pendingPatch(band: .adult) == nil)
    }
}

@Suite struct PushPolicyNotifyTests {
    @Test func testKittenNeverRegisters() {
        #expect(!PushPolicy.registersRemote(band: .kitten))
        #expect(!PushPolicy.registersRemote(band: nil))
        #expect(PushPolicy.registersRemote(band: .teen))
        #expect(PushPolicy.registersRemote(band: .adult))
    }

    @Test func theFullPromptIsOfferedUntilAllowed() {
        #expect(PushPolicy.offersFullPrompt(.provisional))
        #expect(PushPolicy.offersFullPrompt(.denied))
        #expect(PushPolicy.offersFullPrompt(.notDetermined))
        #expect(!PushPolicy.offersFullPrompt(.authorized))
        #expect(!PushPolicy.offersFullPrompt(.ephemeral))
    }
}
