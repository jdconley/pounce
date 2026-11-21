import XCTest

/// Tonight's board against a real server: the TV app on `POUNCE_DAILY_SERVER` (default
/// `http://127.0.0.1:8808`, a local `wrangler dev` with `DAILY=on`, `DAILY_TEST=on`, `TV=on`), and
/// this test as the phone over plain HTTP (docs/daily-protocol.md). It links a board by the code
/// the TV shows, offers a run (Not now, then Watch), watches it to its end, sees the result land
/// on the board, and unlinks from the TV's menu; and it watches each daily game live. Skipped when
/// the server isn't there.
@MainActor
final class BoardLiveTests: XCTestCase {
    private let server = URL(string: ProcessInfo.processInfo.environment["POUNCE_DAILY_SERVER"] ?? "http://127.0.0.1:8808")!

    override func setUp() {
        continueAfterFailure = false
    }

    func testLinkABoardWatchARunSeeTheResultAndUnlink() async throws {
        let phone = try await Phone.make(server: server, name: "Mom", cat: 3)

        let app = launch()
        try await link(app, phone)
        XCTAssertTrue(el(app, "tv.board.game.test").waitForExistence(timeout: Live.t(10)), "the board has no test game")

        // Show on TV: the card, with Not now focused. Not now, then the offer again, then Watch.
        let started = try await phone.call("POST", "/v1/daily/test/start")
        XCTAssertEqual(started.status, 200)
        let run = try XCTUnwrap(started.json["run"] as? String)
        let target = try XCTUnwrap((started.json["puzzle"] as? [String: Any])?["target"] as? Int)
        let answer1 = try await phone.call("PUT", "/v1/daily/runs/\(run)/tv", ["on": true])
        XCTAssertEqual(answer1.status, 204)
        XCTAssertTrue(el(app, "tv.watch.card").waitForExistence(timeout: Live.t(10)), "no watch card")
        XCTAssertTrue(waitForFocus(app, "tv.watch.notNow"), "Not now isn't the card's focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(until(5) { !self.el(app, "tv.watch.card").exists }, "Not now didn't close the card")

        let answer2 = try await phone.call("PUT", "/v1/daily/runs/\(run)/tv", ["on": false])
        XCTAssertEqual(answer2.status, 204)
        let answer3 = try await phone.call("PUT", "/v1/daily/runs/\(run)/tv", ["on": true])
        XCTAssertEqual(answer3.status, 204)
        XCTAssertTrue(el(app, "tv.watch.card").waitForExistence(timeout: Live.t(10)), "no second watch card")
        XCTAssertTrue(waitForFocus(app, "tv.watch.notNow"))
        press(app, .left, to: "tv.watch.watch")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(el(app, "tv.watch.view.test").waitForExistence(timeout: Live.t(5)), "Watch shows no run")
        let count = el(app, "tv.watch.count")
        XCTAssertTrue(until(5) { self.value(count) == "0" }, "the run's first frame isn't drawn")
        let answer4 = try await phone.call("POST", "/v1/daily/runs/\(run)/moves", ["from": 0, "moves": [["k": "step", "n": 1]]])
        XCTAssertEqual(answer4.status, 200)
        XCTAssertTrue(until(5) { self.value(count) == "1" }, "a move didn't reach the TV")

        // The run ends: its result over it, then the board with the row cheering.
        let rest = (2...target).map { ["k": "step", "n": $0] }
        let answer5 = try await phone.call("POST", "/v1/daily/runs/\(run)/moves", ["from": 1, "moves": rest])
        XCTAssertEqual(answer5.status, 200)
        XCTAssertTrue(el(app, "tv.watch.ended").waitForExistence(timeout: Live.t(5)), "no result over the watched run")
        XCTAssertTrue(el(app, "tv.board.row.test.me").waitForExistence(timeout: Live.t(12)), "the result isn't on the board")
        XCTAssertTrue(el(app, "tv.board.dish.me").exists, "the Dish doesn't count it")

        // Unlink from the TV's menu: home, and a relaunch stays home.
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(app, "tv.menu.playAGame"))
        press(app, .down, to: "tv.menu.sound")
        press(app, .down, to: "tv.menu.unlink")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForFocus(app, "tv.poster.cat-tower", timeout: 10), "Unlink didn't go home")
        app.terminate()
        app.launch()
        XCTAssertTrue(el(app, "tv.poster.board").waitForExistence(timeout: Live.t(15)))
        XCTAssertFalse(el(app, "tv.board").exists, "the board came back after Unlink")
    }
    /// Each daily game, watched live: the card, the game's own view (from `DailyWatchGames`, not
    /// the placeholder) redrawn by a move, `watchEnd` with its result, and the board again. The
    /// phone's board counts the TV. `TV_SHOTS_DIR` keeps `appletv-watch-<game>.png`.
    func testEachDailyGameIsWatchedLive() async throws {
        let phone = try await Phone.make(server: server, name: "Mom", cat: 3)
        let app = launch()
        try await link(app, phone)
        let board = try await phone.call("GET", "/v1/daily/board")
        XCTAssertEqual(board.json["tvs"] as? Int, 1, "the phone's board doesn't count the TV")

        for (game, title) in [("sniff", "Sniff"), ("nine-lives", "Nine Lives"), ("cat-nap", "Cat Nap"), ("box-fort", "Box Fort")] {
            let started = try await phone.call("POST", "/v1/daily/\(game)/start")
            XCTAssertEqual(started.status, 200, "\(game) isn't on the server")
            let run = try XCTUnwrap(started.json["run"] as? String)
            let seq = started.json["seq"] as? Int ?? 0
            let move = try firstMove(game, puzzle: started.json["puzzle"] as? [String: Any] ?? [:], state: started.json["state"] as? [String: Any] ?? [:])
            let on = try await phone.call("PUT", "/v1/daily/runs/\(run)/tv", ["on": true])
            XCTAssertEqual(on.status, 204)
            XCTAssertTrue(el(app, "tv.watch.card").waitForExistence(timeout: Live.t(10)), "no watch card for \(title)")
            XCTAssertTrue(waitForFocus(app, "tv.watch.notNow"), "Not now isn't the card's focus")
            press(app, .left, to: "tv.watch.watch")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(el(app, "tv.watch.view.\(game)").waitForExistence(timeout: Live.t(5)), "Watch shows no \(title) run")
            // The game's own view, decoded from the first frame: never the placeholder.
            XCTAssertTrue(until(5) { !self.el(app, "tv.watch.placeholder").exists }, "\(title) shows the placeholder")
            try await Task.sleep(for: .seconds(1))
            let before = stage()
            let sent = try await phone.call("POST", "/v1/daily/runs/\(run)/moves", ["from": seq, "moves": [move]])
            XCTAssertEqual(sent.json["ok"] as? Bool, true, "\(title)'s first move was refused: \(sent.json)")
            XCTAssertTrue(until(5) { self.stage() != before }, "\(title)'s next frame didn't redraw it")
            try await Task.sleep(for: .seconds(1))
            shot("watch-\(game)")
            // The end: `watchEnd`, its result over the last frame, then the board.
            if sent.json["result"] is NSNull || sent.json["result"] == nil {
                let gaveUp = try await phone.call("POST", "/v1/daily/runs/\(run)/giveup")
                XCTAssertEqual(gaveUp.status, 200)
            }
            XCTAssertTrue(el(app, "tv.watch.ended").waitForExistence(timeout: Live.t(5)), "no result over \(title)'s run")
            XCTAssertTrue(until(12) { !self.el(app, "tv.watch.ended").exists && self.el(app, "tv.board").exists }, "the board didn't come back after \(title)")
        }
        app.terminate()
    }

    /// The TV app on the server, muted (speed 1 plays real sound).
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Live.arguments() + ["-settings.soundOn", "<false/>", "-tv.soundOn", "<false/>"]
        app.launchEnvironment["POUNCE_API_BASE_URL"] = server.absoluteString
        app.launch()
        return app
    }

    /// From home (unlinking a board kept from an earlier run), Tonight's board's link panel, and
    /// `phone` links the board by the code it shows.
    private func link(_ app: XCUIApplication, _ phone: Phone) async throws {
        if el(app, "tv.board").waitForExistence(timeout: Live.t(4)) {
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(waitForFocus(app, "tv.menu.playAGame"))
            press(app, .down, to: "tv.menu.sound")
            press(app, .down, to: "tv.menu.unlink")
            XCUIRemote.shared.press(.select)
        }
        // Home: the Dish is on, so Tonight's board is the third poster.
        XCTAssertTrue(el(app, "tv.poster.board").waitForExistence(timeout: Live.t(15)), "no Tonight's board poster: is the server's DAILY on?")
        XCTAssertTrue(waitForFocus(app, "tv.poster.cat-tower", timeout: 10))
        press(app, .down, to: "tv.poster.tiles")
        press(app, .down, to: "tv.poster.board")
        XCUIRemote.shared.press(.select)
        let codeLabel = el(app, "tv.boardLink.code")
        var code = ""
        XCTAssertTrue(until(15) {
            code = (self.label(codeLabel) ?? "").replacingOccurrences(of: "Code", with: "").replacingOccurrences(of: " ", with: "")
            return code.count == 6
        }, "the link panel shows no code")
        let linked = try await phone.call("POST", "/v1/screens/link", ["code": code, "board": true])
        XCTAssertEqual(linked.status, 200)
        XCTAssertTrue(el(app, "tv.board").waitForExistence(timeout: Live.t(10)), "the TV didn't show the board")
    }

    /// The watch stage as drawn: the screen below the run's top bar.
    private func stage() -> Data {
        let screen = XCUIScreen.main.screenshot().image
        guard let cg = screen.cgImage else { return Data() }
        let scale = CGFloat(cg.height) / screen.size.height
        let crop = CGRect(x: 0, y: 200 * scale, width: CGFloat(cg.width), height: CGFloat(cg.height) - 200 * scale)
        guard let part = cg.cropping(to: crop) else { return Data() }
        return UIImage(cgImage: part).pngData() ?? Data()
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let note = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        note.name = "appletv-\(name)"
        note.lifetime = .keepAlways
        add(note)
        if let dir = ProcessInfo.processInfo.environment["TV_SHOTS_DIR"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("appletv-\(name).png"))
        }
    }

    /// A first move each game accepts from its start: Sniff's guess, a 1 in Nine Lives' first open
    /// cell (a clash is legal), an x on Cat Nap's first cell, and a Box Fort piece where it fits.
    private func firstMove(_ game: String, puzzle: [String: Any], state: [String: Any]) throws -> [String: Any] {
        switch game {
        case "sniff":
            return ["k": "guess", "word": "large"]
        case "nine-lives":
            let givens = try XCTUnwrap(puzzle["givens"] as? [Int])
            return ["k": "set", "i": try XCTUnwrap(givens.firstIndex(of: 0)), "d": 1]
        case "cat-nap":
            return ["k": "mark", "cells": [0], "to": "x"]
        case "box-fort":
            let rug = try XCTUnwrap(state["rug"] as? [Int])
            let pieces = try XCTUnwrap(state["pieces"] as? [[String: Any]])
            let placed = state["placed"] as? [Bool] ?? []
            let size = 8
            for (slot, piece) in pieces.enumerated() where !(placed.indices.contains(slot) && placed[slot]) {
                let cells = (piece["cells"] as? [[Int]]) ?? []
                for row in 0..<size {
                    for col in 0..<size {
                        let fits = cells.allSatisfy { c in
                            let r = row + c[0], k = col + c[1]
                            return r < size && k < size && rug[r * size + k] == 0
                        }
                        if fits { return ["k": "place", "slot": slot, "row": row, "col": col] }
                    }
                }
            }
            throw XCTSkip("no Box Fort placement fits")
        default:
            throw XCTSkip("no first move for \(game)")
        }
    }
}

/// A phone on the Daily Dish, over plain HTTP: a device of its own and one person on it.
private struct Phone {
    let server: URL
    let token: String
    let person: String
    let address: String

    struct Answer {
        let status: Int
        let json: [String: Any]
    }

    static func make(server: URL, name: String, cat: Int) async throws -> Phone {
        let address = "10.251.\(Int.random(in: 0...250)).\(Int.random(in: 1...250))"
        var mint = URLRequest(url: server.appendingPathComponent("v1/devices"))
        mint.httpMethod = "POST"
        mint.setValue(address, forHTTPHeaderField: "cf-connecting-ip")
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: mint)
        } catch {
            throw XCTSkip("no server at \(server.absoluteString): start one with DAILY=on, DAILY_TEST=on, TV=on")
        }
        let token = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["token"] as? String)
        let person = UUID().uuidString.lowercased()
        var key = Data(count: 32)
        for i in 0..<32 { key[i] = UInt8.random(in: 0...255) }
        let keyText = key.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let phone = Phone(server: server, token: token, person: person, address: address)
        let profile = try await phone.call("PUT", "/v1/devices/me/profile", [
            "timeZone": "America/Los_Angeles", "ageBand": "adult",
            "people": [["id": person, "name": name, "cat": cat, "key": keyText]],
        ], asPerson: false)
        XCTAssertEqual(profile.status, 200)
        return phone
    }

    func call(_ method: String, _ path: String, _ body: [String: Any]? = nil, asPerson: Bool = true) async throws -> Answer {
        var parts = URLComponents(url: server.appendingPathComponent(String(path.dropFirst())), resolvingAgainstBaseURL: false)!
        if asPerson { parts.queryItems = [URLQueryItem(name: "person", value: person)] }
        var request = URLRequest(url: parts.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(address, forHTTPHeaderField: "cf-connecting-ip")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return Answer(status: (response as? HTTPURLResponse)?.statusCode ?? 0, json: json)
    }
}
