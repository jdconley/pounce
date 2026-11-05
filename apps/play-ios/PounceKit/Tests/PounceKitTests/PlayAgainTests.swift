import Testing
@testable import PounceKit

@Suite struct PlayAgainTests {
    private func room(look: Look? = .standard, status: RoomStatus = .over, rematch: String? = nil) -> RoomView {
        RoomView(code: "BCDFG", status: status, youAreHost: true, seats: [], look: look, rematch: rematch)
    }

    @Test func unavailableWithoutLook() {
        #expect(!PlayAgain.available(room(look: nil)))
        #expect(!PlayAgain.available(room(status: .playing)))
        #expect(!PlayAgain.available(nil))
        #expect(PlayAgain.available(room()))
        var again = PlayAgain()
        #expect(again.tap(room: room(look: nil), rematch: nil) == .none)
    }

    @Test func sendsOnce() {
        var again = PlayAgain()
        #expect(again.tap(room: room(), rematch: nil) == .send)
        #expect(again.tap(room: room(), rematch: nil) == .none)
        #expect(again.waiting)
        #expect(again.arrived(code: "NWCDF") == "NWCDF", "the phone that asked goes to the new table")
    }

    @Test func refusedLetsItBeAskedAgain() {
        var again = PlayAgain()
        _ = again.tap(room: room(), rematch: nil)
        again.refused()
        #expect(!again.waiting)
        #expect(again.tap(room: room(), rematch: nil) == .send)
    }

    @Test func jumpsWhenAlreadyDealt() {
        var again = PlayAgain()
        #expect(again.tap(room: room(rematch: "QRSTV"), rematch: nil) == .jump("QRSTV"))
        #expect(again.tap(room: room(), rematch: "NWCDF") == .jump("NWCDF"))
    }

    @Test func othersJumpByTap() {
        var again = PlayAgain()
        #expect(again.arrived(code: "NWCDF") == nil, "someone else dealt it: no jump until a tap")
        #expect(again.tap(room: room(), rematch: "NWCDF") == .jump("NWCDF"))
    }
}

@Suite struct LookTrayTests {
    @Test func offersDefaultsAndOwnUnlocks() {
        let unlocked = StreakView.Unlocks(backs: ["back-crown"], rugs: ["rug-fish-pond"])
        let rugs = LookTray.rugs(unlocked: unlocked, current: Look(rug: "rug-fish-pond", back: "back-crown"))
        #expect(rugs.map(\.id) == ["rug-classic", "rug-fish-pond"])
        #expect(rugs.map(\.selected) == [false, true])
        let backs = LookTray.backs(unlocked: unlocked, current: .standard)
        #expect(backs.map(\.id) == ["back-violet-paw", "back-crown"])
        #expect(backs.first?.selected == true)
    }

    @Test func catalogOrderAndUnknownIdsDropped() {
        let unlocked = StreakView.Unlocks(
            backs: ["back-golden-yarn", "back-yarn-swirl", "back-from-the-future"], rugs: ["rug-royal-violet", "rug-night-sky"])
        #expect(LookTray.backs(unlocked: unlocked, current: nil).map(\.id) == ["back-violet-paw", "back-yarn-swirl", "back-golden-yarn"])
        #expect(LookTray.rugs(unlocked: unlocked, current: nil).map(\.id) == ["rug-classic", "rug-night-sky", "rug-royal-violet"])
    }
}
