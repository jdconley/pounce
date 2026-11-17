import Foundation
import Testing
@testable import PounceKit

/// A TV's kept table and sound setting, in a scratch defaults suite.
@Suite("A TV's kept values")
struct ScreenKeepTests {
    private static func fresh() -> (DefaultsScreenKeep, String) {
        let suite = "pounce.tests.screenkeep.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return (DefaultsScreenKeep(suite: suite), suite)
    }

    @Test func aNewTVKeepsNoTableAndHasSoundOn() async {
        let (keep, suite) = Self.fresh()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(await keep.load() == ScreenKept(room: nil, soundOn: true))
    }

    @Test func itKeepsTheTableAndTheSoundAndForgetsTheTable() async {
        let (keep, suite) = Self.fresh()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        await keep.keep(room: "BCDFG")
        await keep.keep(soundOn: false)
        #expect(await DefaultsScreenKeep(suite: suite).load() == ScreenKept(room: "BCDFG", soundOn: false))
        await keep.keep(room: nil)
        #expect(await DefaultsScreenKeep(suite: suite).load() == ScreenKept(room: nil, soundOn: false))
    }

    @Test func somethingThatIsNotARoomCodeIsNeverKept() async {
        let (keep, suite) = Self.fresh()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        await keep.keep(room: "BCDFG")
        await keep.keep(room: "nope!")
        #expect(await keep.load().room == nil)
        UserDefaults(suiteName: suite)?.set("AAAAA", forKey: "tv.room")
        #expect(await keep.load().room == nil)
    }
}
