import XCTest

/// Task 24 (needs the dev server and the host broker that runs `pounce-e2e` on the Mac; run it
/// with scripts/ui-tests.sh): the app hosts a table with a remote human (`pounce-e2e join` on "its own
/// phone"), a pass-and-play second person and a bot, and plays at least one full round by taps.
///
/// Seats: 0 this phone's owner, 1 the remote (first open seat), 2 a second person on this phone,
/// 3 the House Cat. The remote drops its socket after its 3rd action and stays away until the
/// test has seen its cat go away (`--reconnect-file`: each UI query can wait many seconds for
/// the app to idle, so a fixed 3 s spell is easy to miss); then it reconnects and the cat must
/// wake again. The curtain comes up for each of this phone's seats
/// (with the remote's turn between them). Backgrounding the app reconnects and the table plays on.
final class MixedSeatsTests: XCTestCase {
    private var remote: HostProcess?

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if let remote {
            remote.stop()
            let log = XCTAttachment(string: remote.output())
            log.name = "pounce-e2e join"
            log.lifetime = .keepAlways
            add(log)
        }
        remote = nil
    }

    private func remoteOutput() -> String { remote?.output() ?? "" }

    @MainActor
    func testAppPlusRemotePlusBot() throws {
        let restoreQuiescence = Quiescence.disable()
        addTeardownBlock { @MainActor in restoreQuiescence() }
        let app = Live.app()
        app.launchArguments.append("-log-timeline")
        app.launch()
        onboard(app)
        newGame(app)
        let code = lobbyCode(app)
        XCTAssertEqual(code.count, 5, "bad room code \(code)")
        // The remote stays away until this file exists; the test creates it once it saw "away".
        let reconnectSignal = NSTemporaryDirectory() + "reconnect-\(UUID().uuidString)"

        // The remote claims seat 1 (the first open one).
        remote = try HostProcess("e2e", ["join", code, "--name", "Remote", "--cat", "4", "--drop-after", "3",
                                       "--reconnect-file", reconnectSignal, "--base", Live.baseURL])
        let seat1 = el(app, "lobby.seat.1")
        XCTAssertTrue(until(30) { seat1.label.contains("on another phone") },
                      "the remote never sat: \(seat1.label)\n\(remoteOutput())")

        // A second person on this phone at (closed) seat 2, then a bot at seat 3.
        seatMenu(app, seat: 2, "here")
        addLocalPerson(app)
        let seat2 = el(app, "lobby.seat.2")
        XCTAssertTrue(until(10) { seat2.label.contains("on this phone") }, "no second local seat: \(seat2.label)")
        seatMenu(app, seat: 3, "bot")
        XCTAssertTrue(until(10) { self.el(app, "lobby.seat.3").label.contains("bot") })
        screenshot(app, "mixed-lobby")
        el(app, "lobby.start").tap()

        // Play until a round has ended and the next one is dealt, checking along the way.
        var curtainNames = Set<String>()
        var remoteLabels: [String] = []
        var sawAway = false, sawAwakeAfterAway = false
        var backgrounded = false, playedAfterBackground = false
        var turns = 0
        var firstRound = 0
        var roundOverSeen = false
        var stuckSince: Date?
        let deadline = Date().addingTimeInterval(Live.t(3600))
        func watchRemote(_ snap: UISnap) {
            guard let text = snap.label("table.opponent.1") else { return }
            if remoteLabels.last != text {
                remoteLabels.append(text)
                print("[mixed] seat 1: \(text)")
            }
            if text.contains("away"), !sawAway {
                sawAway = true
                screenshot(app, "mixed-remote-away")
                FileManager.default.createFile(atPath: reconnectSignal, contents: nil)
            }
            if sawAway, text.contains("awake") { sawAwakeAfterAway = true }
        }
        // One whole-app snapshot per poll, every 2 s at normal speed (see `playTurnByTaps`).
        while Date() < deadline {
            guard let snap = UISnap(app) else {
                Thread.sleep(forTimeInterval: Live.poll(2))
                continue
            }
            if snap.exists("priming.notNow") {
                dismissPriming(app, snap)
                continue
            }
            if let name = holdCurtain(app, snap) {
                curtainNames.insert(name)
                Thread.sleep(forTimeInterval: Live.pace(1))
                continue
            }
            watchRemote(snap)
            guard let d = snap.debug else {
                Thread.sleep(forTimeInterval: Live.poll(2))
                continue
            }
            if firstRound == 0 { firstRound = d.round }
            if d.status == "roundOver" || d.round > firstRound { roundOverSeen = true }
            if roundOverSeen, d.round > firstRound, d.status == "playing", sawAwakeAfterAway,
               curtainNames.count >= 2, playedAfterBackground {
                break
            }
            // Stuck check: this phone's turn, the hand face down, no curtain to hold. The turn and
            // hand come from the scene and the curtain from SwiftUI, so only time while the shell
            // has synced the store's latest seq counts; while it lags (a starved machine) force a
            // frame and wait.
            let looksStuck = snap.value("table.turn") == "mine" && d.status == "playing"
                && snap.label("table.hand.0") == "Card"
            if looksStuck, !d.shellCaughtUp {
                print("[mixed] shell behind the store: stage seq \(d.stageSeq), store seq \(d.storeSeq), pass \(d.pass)")
                _ = XCUIScreen.main.screenshot()
                stuckSince = nil
            } else if looksStuck {
                if stuckSince == nil { stuckSince = Date() }
                if let since = stuckSince, Date().timeIntervalSince(since) > Live.t(120) {
                    screenshot(app, "mixed-stuck")
                    let tree = XCTAttachment(string: app.debugDescription)
                    tree.name = "mixed-stuck-tree"
                    tree.lifetime = .keepAlways
                    add(tree)
                    XCTFail("seat \(d.turn)'s turn: hand face down and no curtain for \(Int(Live.t(120))) s (stage seq \(d.stageSeq), store seq \(d.storeSeq), pass \(d.pass))")
                    break
                }
            } else {
                stuckSince = nil
            }
            if playTurnByTaps(app, snap, observe: watchRemote) {
                turns += 1
                if backgrounded { playedAfterBackground = true }
                // Once the remote is back, go to the background and return: the socket drops
                // and reconnects, and the table must still play.
                if sawAwakeAfterAway, !backgrounded {
                    XCUIDevice.shared.press(.home)
                    Thread.sleep(forTimeInterval: 3)
                    app.activate()
                    backgrounded = true
                    XCTAssertTrue(el(app, "screen-table").waitForExistence(timeout: Live.t(15)), "no table after returning")
                    screenshot(app, "mixed-after-background")
                }
            } else {
                Thread.sleep(forTimeInterval: Live.poll(2))
            }
        }
        screenshot(app, "mixed-end")
        let summary = """
            turns by taps \(turns), rounds \(firstRound)→\(UISnap(app)?.debug?.round ?? -1), curtain names \(curtainNames.sorted()), \
            remote labels \(remoteLabels), backgrounded \(backgrounded), played after \(playedAfterBackground)
            """
        let note = XCTAttachment(string: summary)
        note.name = "mixed summary"
        note.lifetime = .keepAlways
        add(note)
        print("[mixed] \(summary)")
        XCTAssertTrue(sawAway, "the remote's cat never went away: \(remoteLabels)\n\(remoteOutput())")
        XCTAssertTrue(sawAwakeAfterAway, "the remote's cat never woke after the drop: \(remoteLabels)")
        XCTAssertGreaterThanOrEqual(curtainNames.count, 2, "the curtain didn't come up for both local seats: \(curtainNames)")
        XCTAssertTrue(playedAfterBackground, "no turn played after the app came back from the background")
        XCTAssertTrue(roundOverSeen, "no round ended within the time limit")
        XCTAssertTrue(remoteOutput().contains("reconnected"), "the remote didn't reconnect:\n\(remoteOutput())")
    }
}
