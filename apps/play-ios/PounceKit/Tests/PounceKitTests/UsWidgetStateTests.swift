import Foundation
import Testing
@testable import PounceKit

@Suite struct UsWidgetStateTests {
    let la = widgetCalendar()
    let noon = at(2026, 11, 5, 12)

    private func state(_ view: StreakView, at date: Date? = nil, snapshotAt: Date? = nil, pair: String? = nil) -> UsWidgetState {
        let s = widgetSnapshot([view], now: snapshotAt ?? noon, names: ["GH2VD": "Couch Cats"])
        return UsWidgetState.make(s, pair: pair, at: date ?? noon, calendar: la)
    }

    @Test func poses() {
        var paused = streakView(count: 4)
        paused.pausedUntil = "2026-11-07"
        #expect(state(paused).poses == (.asleep, .asleep))
        #expect(state(streakView(me: true, them: true, kept: true)).poses == (.celebrate, .celebrate))
        #expect(state(streakView(me: true, theirMove: ["GH2VD"])).poses == (.celebrate, .awake), "my half done, their move")
        #expect(state(streakView(me: true)).poses == (.celebrate, .idle))
        #expect(state(streakView(myMove: ["GH2VD"])).poses == (.awake, .idle), "my move: theirs looks at me")
        #expect(state(streakView(theirMove: ["GH2VD"])).poses == (.idle, .awake))
        #expect(state(streakView()).poses == (.idle, .idle))
    }

    @Test func eveningIsEager() {
        let evening = at(2026, 11, 5, 20, 30)
        #expect(state(streakView(count: 6), at: evening).poses == (.awake, .awake))
        #expect(state(streakView(count: 6, me: true), at: evening).poses == (.celebrate, .awake))
        #expect(state(streakView(count: 6), at: at(2026, 11, 5, 19, 59)).poses == (.idle, .idle))
        #expect(state(streakView(count: 0, best: 0), at: evening).poses == (.idle, .idle), "nothing to keep yet")
        #expect(state(streakView(count: 6, me: true, them: true, kept: true), at: evening).poses == (.celebrate, .celebrate))
    }

    @Test func ring() {
        #expect(state(streakView()).ring == 0)
        #expect(state(streakView(me: true)).ring == 0.5)
        #expect(state(streakView(them: true)).ring == 0.5)
        #expect(state(streakView(me: true, them: true)).ring == 1)
        #expect(state(streakView(kept: true)).ring == 1)
    }

    @Test func testRolloverGreysToday() {
        let kept = streakView(count: 9, me: true, them: true, kept: true)
        let late = state(kept, at: at(2026, 11, 6, 3, 59))
        #expect(late.kept && late.meIn && late.count == 9, "03:59 is still the same day")
        let next = state(kept, at: at(2026, 11, 6, 4, 0))
        #expect(!next.kept && !next.meIn && !next.themIn && next.ring == 0)
        #expect(next.count == 9, "the count stays: the server settles it, the widget never says a day was missed")
    }

    @Test func testPauseEndsAtRollover() {
        var paused = streakView(count: 4)
        paused.pausedUntil = "2026-11-05"
        #expect(state(paused, at: at(2026, 11, 6, 3, 0)).mode == .paused)
        let after = state(paused, at: at(2026, 11, 6, 4, 0))
        #expect(after.mode == .normal)
        #expect(after.poses == (.idle, .idle))
    }

    @Test func winbackKeepsItsMode() {
        var view = streakView(count: 9)
        view.winback = .init(kept: 1)
        #expect(state(view).mode == .winback(kept: 1))
    }

    @Test func partnerChoice() {
        let s = widgetSnapshot([streakView("pr_mia", count: 9), streakView("pr_kiki", count: 3, partner: .init(name: "Kiki", cat: 6))])
        #expect(UsWidgetState.make(s, pair: nil, at: noon, calendar: la).partner?.name == "Mia")
        #expect(UsWidgetState.make(s, pair: "pr_kiki", at: noon, calendar: la).partner?.name == "Kiki")
        #expect(UsWidgetState.make(s, pair: "pr_gone", at: noon, calendar: la).partner?.name == "Mia")
        #expect(UsWidgetState.make(s, pair: nil, at: noon, calendar: la).me == widgetOwner.face)
    }

    @Test func empty() {
        #expect(UsWidgetState.make(nil, pair: nil, at: noon, calendar: la).kind == .empty)
        let none = UsWidgetState.make(widgetSnapshot([]), pair: nil, at: noon, calendar: la)
        #expect(none.kind == .empty)
        #expect(none.me == widgetOwner.face, "your own cat waits on the condo")
        #expect(none.url == WidgetLink.app.url)
    }

    @Test func tables() {
        let s = widgetSnapshot(
            [streakView(myMove: ["GH2VD"], theirMove: ["K9PQR", "M3W7Z", "GH2VD"])],
            names: ["GH2VD": "Couch Cats", "K9PQR": "Kitchen"])
        let tables = UsWidgetState.make(s, pair: nil, at: noon, calendar: la).tables
        #expect(tables == [
            .init(code: "GH2VD", name: "Couch Cats", mine: true),
            .init(code: "K9PQR", name: "Kitchen", mine: false),
        ])
        let unnamed = UsWidgetState.make(widgetSnapshot([streakView(theirMove: ["M3W7Z"])]), pair: nil, at: noon, calendar: la)
        #expect(unnamed.tables == [.init(code: "M3W7Z", name: TableName.fallback(code: "M3W7Z"), mine: false)])
    }

    @Test func tapOpensYourMoveElseUs() {
        #expect(state(streakView(myMove: ["GH2VD"])).url == WidgetLink.table("GH2VD").url)
        #expect(state(streakView(theirMove: ["GH2VD"])).url == WidgetLink.us(pair: "pr_mia").url)
    }

    @Test func pounceButton() {
        func with(_ p: PounceState) -> StreakView { var v = streakView(); v.pounce = p; return v }
        #expect(state(streakView()).pounce == .ready)
        #expect(state(with(PounceState(sent: true))).pounce == .sent(quiet: false))
        #expect(state(with(PounceState(sent: true, quiet: true))).pounce == .sent(quiet: true))
        #expect(state(with(PounceState(resting: true))).pounce == .resting)
        #expect(state(with(PounceState(answer: .no))).pounce == .answered(.no))
    }

    @Test func pounceCheckLastsAnHourFromTheSend() {
        var view = streakView()
        view.pounce = PounceState(sent: true)
        var s = widgetSnapshot([view], now: noon)
        s.pounced["pr_mia"] = at(2026, 11, 5, 11, 30)
        #expect(UsWidgetState.make(s, pair: nil, at: at(2026, 11, 5, 12, 29), calendar: la).pounce == .sent(quiet: false))
        #expect(UsWidgetState.make(s, pair: nil, at: noon, calendar: la).pounceExpires == at(2026, 11, 5, 12, 30))
        #expect(UsWidgetState.make(s, pair: nil, at: at(2026, 11, 5, 12, 30), calendar: la).pounce == .ready)
        // Without a local send time, the hour runs from the snapshot.
        s.pounced = [:]
        #expect(UsWidgetState.make(s, pair: nil, at: at(2026, 11, 5, 12, 59), calendar: la).pounce == .sent(quiet: false))
        #expect(UsWidgetState.make(s, pair: nil, at: at(2026, 11, 5, 13, 0), calendar: la).pounce == .ready)
        #expect(state(streakView()).pounceExpires == nil)
    }
}

extension UsWidgetState {
    var poses: (WidgetPose, WidgetPose) { (myPose, theirPose) }
}
