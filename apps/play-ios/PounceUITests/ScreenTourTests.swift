import XCTest

/// A tour of the app's screens for copy and fit reviews: each stop launches a demo (no server),
/// taps its way to one screen and saves `<name>-<orientation>.png`. Skipped unless the runner
/// names a folder:
///
///     TEST_RUNNER_TOUR_DIR=/some/dir \
///     TEST_RUNNER_TOUR_ONLY='lobby,table-menu' \
///     TEST_RUNNER_TOUR_ORIENTATIONS=portrait,landscape \
///     xcodebuild test ... -only-testing:PounceUITests/ScreenTourTests
///
/// `TOUR_ONLY` picks stops by name (default: all of them). Home and How to play aren't on it.
/// Text size is the simulator's (`xcrun simctl ui <device> content_size <size>`).
@MainActor
final class ScreenTourTests: XCTestCase {
    private struct Stop {
        let name: String
        let args: [String]
        var wait: TimeInterval = 3
        var steps: (ScreenTourTests, XCUIApplication) -> Void = { _, _ in }
    }

    private static let reset = ["-uitest-reset", "-seed-people", "-age-band", "adult"]

    private var stops: [Stop] {
        let r = Self.reset
        let us = r + ["-demo-streaks", "-show-us"]
        return [
            // First run.
            Stop(name: "age-keypad", args: ["-uitest-reset", "-age-range", "declined"]),
            Stop(name: "age-confirm", args: ["-uitest-reset", "-age-range", "declined"]) { t, app in
                for d in "1990" { t.tapId(app, "age.key.\(d)") }
                t.tapId(app, "age.confirm")
            },
            Stop(name: "pickcat", args: ["-uitest-reset", "-age-band", "adult"]),
            Stop(name: "pickcat-kitten", args: ["-uitest-reset", "-age-band", "kitten"]),
            // Join.
            Stop(name: "join", args: r + ["-show-join"]),
            Stop(name: "join-offline", args: r + ["-open-link", "pounce-dev://j/BCDFG"], wait: 6),
            // Lobby.
            Stop(name: "lobby", args: r + ["-demo", "lobby"]),
            Stop(name: "lobby-ready", args: r + ["-demo", "lobbyReady"]),
            Stop(name: "lobby-family", args: r + ["-demo", "lobbyFamily"]),
            Stop(name: "lobby-kitten", args: ["-uitest-reset", "-seed-people", "-age-band", "kitten", "-demo-kitten", "locked", "-demo", "lobby"]),
            Stop(name: "lobby-seatmenu", args: r + ["-demo", "lobby"]) { t, app in t.tapId(app, "lobby.seat.3") },
            Stop(name: "lobby-start", args: r + ["-demo", "lobby"]) { t, app in t.tapId(app, "lobby.start") },
            // The table.
            Stop(name: "table", args: r + ["-demo", "table"]),
            Stop(name: "table-tip-goal", args: r + ["-demo", "table", "-tips"]),
            Stop(name: "table-tip-draw", args: r + ["-demo", "table", "-tips"]) { t, app in t.tapId(app, "coach.ok") },
            Stop(name: "table-note", args: r + ["-demo", "table"], wait: 0.6) { t, app in
                t.tapAt(app, 0.5, 0.86)
            },
            Stop(name: "table-other", args: r + ["-demo", "other"]),
            Stop(name: "table-hit", args: r + ["-demo", "hit"]),
            Stop(name: "table-crowded", args: r + ["-demo", "crowded"]),
            Stop(name: "table-tower", args: r + ["-demo", "table", "-show-tower"]),
            Stop(name: "table-scores", args: r + ["-demo", "table", "-show-scoreboard"]),
            Stop(name: "table-menu", args: r + ["-demo", "table"]) { t, app in t.tapId(app, "table.menu") },
            Stop(name: "table-forfeit", args: r + ["-demo", "table"]) { t, app in
                t.tapId(app, "table.menu")
                t.tapId(app, "menu.forfeit")
            },
            Stop(name: "table-look", args: r + ["-demo", "table", "-show-look"]),
            Stop(name: "table-names", args: r + ["-demo", "table"]) { t, app in
                t.tapId(app, "table.menu")
                t.tapId(app, "menu.names")
            },
            Stop(name: "table-name", args: r + ["-demo", "table"]) { t, app in
                t.tapId(app, "table.menu")
                t.tapId(app, "menu.name")
            },
            Stop(name: "table-move", args: r + ["-demo", "table"]) { t, app in
                t.tapId(app, "table.menu")
                t.tapId(app, "menu.move")
            },
            Stop(name: "player", args: r + ["-demo-streaks", "-demo", "table", "-show-player", "1"]),
            Stop(name: "player-bot", args: r + ["-demo", "lobbyFamily", "-show-player", "3"]),
            Stop(name: "player-report", args: r + ["-demo", "table", "-show-player", "1"]) { t, app in t.tapId(app, "player.report") },
            Stop(name: "player-block", args: r + ["-demo", "table", "-show-player", "1"]) { t, app in t.tapId(app, "player.block") },
            Stop(name: "nudge", args: r + ["-demo", "nudge", "-show-player", "2"]),
            Stop(name: "nudge-wait", args: r + ["-demo", "nudgeWait", "-show-player", "2"]),
            Stop(name: "retire", args: r + ["-demo", "retire", "-show-player", "2"]),
            Stop(name: "retire-confirm", args: r + ["-demo", "retire", "-show-player", "2"]) { t, app in t.tapId(app, "player.retire") },
            Stop(name: "nudged", args: r + ["-demo", "nudged"], wait: 6.5),
            Stop(name: "forfeited", args: r + ["-demo", "forfeited"], wait: 2),
            Stop(name: "notplaying-out", args: r + ["-demo", "table", "-show-notplaying", "out"]),
            Stop(name: "notplaying-started", args: r + ["-demo", "table", "-show-notplaying", "started"]),
            Stop(name: "curtain", args: r + ["-demo", "curtain"]),
            Stop(name: "peek", args: r + ["-demo", "peek"]),
            Stop(name: "over", args: r + ["-demo", "over"], wait: 5),
            Stop(name: "weak", args: r + ["-demo", "weak"], wait: 4),
            Stop(name: "reconnecting", args: r + ["-demo", "reconnecting"], wait: 4),
            Stop(name: "seatlink", args: r + ["-demo", "seatLink"], wait: 4),
            // The tile game.
            Stop(name: "tiles", args: r + ["-demo", "tiles"]),
            Stop(name: "tiles-loupe", args: r + ["-demo", "tiles-loupe"]),
            Stop(name: "tiles-pass", args: r + ["-demo", "tiles-pass"]),
            Stop(name: "tiles-curtain", args: r + ["-demo", "tiles-curtain"]),
            Stop(name: "tiles-over", args: r + ["-demo", "tiles-over"], wait: 4),
            Stop(name: "tiles-over-off", args: r + ["-demo", "tiles-over", "-tiles-game-off"], wait: 4) { t, app in
                t.tapId(app, "tiles.over.again")
            },
            Stop(name: "tiles-menu", args: r + ["-demo", "tiles"]) { t, app in t.tapId(app, "table.menu") },
            Stop(name: "tiles-forfeit", args: r + ["-demo", "tiles"]) { t, app in
                t.tapId(app, "table.menu")
                t.tapId(app, "menu.forfeit")
            },
            // Settings and account.
            Stop(name: "gear", args: r + ["-show-gear"]),
            Stop(name: "gear-signedin", args: r + ["-stub-accounts", "signed-in", "-show-gear"]),
            Stop(name: "gear-account", args: r + ["-stub-accounts", "signed-in", "-show-gear"]) { t, app in
                t.tapId(app, "settings.page.account")
            },
            Stop(name: "gear-quiet", args: r + ["-show-gear"]) { t, app in t.tapId(app, "settings.page.quietHours") },
            Stop(name: "gear-merge", args: r + ["-stub-accounts", "merged", "-show-gear", "-show-merge"]),
            Stop(name: "delete-account", args: r + ["-stub-accounts", "signed-in", "-show-gear"]) { t, app in
                t.tapId(app, "settings.page.account")
                t.tapId(app, "gear.delete")
            },
            Stop(name: "delete-guest", args: r + ["-stub-accounts", "upgraded", "-show-gear"]) { t, app in
                t.tapId(app, "settings.page.account")
                t.tapId(app, "gear.delete")
            },
            Stop(name: "deleted-guest", args: r + ["-stub-accounts", "upgraded", "-show-gear"]) { t, app in
                t.tapId(app, "settings.page.account")
                t.tapId(app, "gear.delete")
                t.tapId(app, "delete.confirm")
            },
            Stop(name: "settings-path", args: r + ["-stub-accounts", "signed-in", "-show-gear"]) { t, app in
                t.tapId(app, "settings.page.account")
                t.tapId(app, "gear.delete")
                t.tapId(app, "delete.confirm")
            },
            Stop(name: "people", args: r + ["-show-people"]),
            Stop(name: "household-age", args: r + ["-show-people", "-show-household-age"]),
            Stop(name: "people-add", args: r + ["-show-people"]) { t, app in t.tapId(app, "people.add") },
            // Streaks.
            Stop(name: "us", args: us),
            Stop(name: "us-gift", args: us + ["-show-gift"], wait: 4),
            Stop(name: "us-notify", args: us + ["-show-notify"]),
            Stop(name: "us-notify-kitten", args: ["-uitest-reset", "-seed-people", "-age-band", "kitten", "-demo-streaks", "-show-us", "-show-notify"]),
            Stop(name: "us-pounce", args: us + ["-show-pounce"]),
            Stop(name: "us-link", args: r + ["-demo-streaks", "-show-link"]),
            Stop(name: "us-pause", args: us) { t, app in t.tapId(app, "us.pause") },
            Stop(name: "us-bubble", args: us) { t, app in t.pressId(app, "us.pair.0") },
            Stop(name: "us-leave", args: us) { t, app in
                t.pressId(app, "us.pair.0")
                t.tapId(app, "us.leave")
            },
            Stop(name: "trophies", args: r + ["-demo-streaks", "-show-trophies"]),
            Stop(name: "invite", args: r + ["-demo-streaks", "-show-invite"], wait: 4),
            Stop(name: "invite-kitten", args: ["-uitest-reset", "-seed-people", "-age-band", "kitten", "-demo-streaks", "-show-invite"], wait: 4),
            // Kittens and parents.
            Stop(name: "kitten-locked", args: ["-uitest-reset", "-seed-people", "-age-band", "kitten", "-demo-kitten", "locked", "-show-gear"]),
            Stop(name: "kitten-held", args: ["-uitest-reset", "-seed-people", "-age-band", "kitten", "-demo-kitten", "held", "-kitten-held", "-show-gear"]),
            Stop(name: "kitten-pending", args: ["-uitest-reset", "-seed-people", "-age-band", "kitten", "-demo-kitten", "pending", "-show-gear"]),
            Stop(name: "kitten-on", args: ["-uitest-reset", "-seed-people", "-age-band", "kitten", "-demo-kitten", "on", "-show-gear"]),
            Stop(name: "kittens", args: r + ["-stub-accounts", "signed-in", "-demo-kittens", "-show-gear"]) { t, app in t.tapId(app, "gear.kittens") },
            Stop(name: "kittens-add", args: r + ["-stub-accounts", "signed-in", "-demo-kittens", "-show-gear"]) { t, app in
                t.tapId(app, "gear.kittens")
                t.tapId(app, "kittens.add")
            },
            Stop(name: "kittens-notice", args: r + ["-stub-accounts", "signed-in", "-demo-kittens", "-show-gear"]) { t, app in
                t.tapId(app, "gear.kittens")
                t.tapId(app, "kittens.phone.0")
            },
            // Updates.
            Stop(name: "update-table", args: r + ["-demo-update", "table"], wait: 4),
            Stop(name: "update-table-none", args: r + ["-demo-update", "table", "-update-latest", "none"], wait: 4),
            Stop(name: "update-required", args: r + ["-demo-update", "required"]),
            Stop(name: "update-required-kitten", args: ["-uitest-reset", "-seed-people", "-age-band", "kitten", "-demo-update", "required"]),
            Stop(name: "update-account", args: r + ["-stub-accounts", "signed-in", "-demo-update", "required", "-show-update-account"]),
        ]
    }

    func testTour() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["TOUR_DIR"], !dir.isEmpty else { throw XCTSkip("no TOUR_DIR") }
        let only = Set((env["TOUR_ONLY"] ?? "").split(separator: ",").map(String.init))
        let orientations = (env["TOUR_ORIENTATIONS"] ?? "portrait").split(separator: ",").map(String.init)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for stop in stops where only.isEmpty || only.contains(stop.name) {
            for orientation in orientations {
                XCUIDevice.shared.orientation = orientation == "landscape" ? .landscapeLeft : .portrait
                let app = XCUIApplication()
                app.launchArguments = Live.arguments(speed: 1) + stop.args
                // No server: every stop is a demo; anything that asks one gets nothing back.
                app.launchEnvironment["POUNCE_API_BASE_URL"] = env["TOUR_BASE_URL"] ?? "http://127.0.0.1:9"
                app.launch()
                Thread.sleep(forTimeInterval: 2.5)
                stop.steps(self, app)
                Thread.sleep(forTimeInterval: stop.wait)
                let png = XCUIScreen.main.screenshot().pngRepresentation
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(stop.name)-\(orientation).png"))
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// Taps the element once it shows (by its middle, so a SpriteKit element works too).
    fileprivate func tapId(_ app: XCUIApplication, _ id: String) {
        let e = el(app, id)
        guard e.waitForExistence(timeout: 6) else { return }
        Thread.sleep(forTimeInterval: 0.8)
        // Below the fold in a scrolling sheet: scroll it up into view first.
        for _ in 0..<4 where !e.isHittable && e.frame.minY > app.frame.maxY - 40 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.6)
        }
        if e.isHittable { e.tap() } else { tap(app, e.frame) }
        Thread.sleep(forTimeInterval: 1)
    }

    fileprivate func pressId(_ app: XCUIApplication, _ id: String) {
        let e = el(app, id)
        guard e.waitForExistence(timeout: 6) else { return }
        e.press(forDuration: 1)
        Thread.sleep(forTimeInterval: 1)
    }

    fileprivate func tapAt(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }
}
