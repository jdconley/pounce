import Testing
@testable import PounceKit

/// The screen stays on while a table is live, and sleeps again once it isn't.
@Suite struct KeepAwakeTests {
    @Test func aPhoneStaysAwakeOnlyWhileItsGameIsPlayed() {
        #expect(KeepAwake.phone(atTable: true, status: .playing))
        #expect(!KeepAwake.phone(atTable: true, status: .lobby))
        #expect(!KeepAwake.phone(atTable: true, status: .over))  // game over, sitting there
        #expect(!KeepAwake.phone(atTable: false, status: .playing))  // left the table
        #expect(!KeepAwake.phone(atTable: true, status: nil))
    }

    @Test func aTVStaysAwakeInTheLobbyAndThroughTheGame() {
        #expect(KeepAwake.tv(atTable: true, status: .lobby))
        #expect(KeepAwake.tv(atTable: true, status: .playing))
        #expect(!KeepAwake.tv(atTable: true, status: .over))
        #expect(!KeepAwake.tv(atTable: false, status: .playing))  // home, or the board
    }
}
