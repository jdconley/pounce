import XCTest

/// The first-game coach (needs the dev server; run it with scripts/ui-tests.sh). Tips are off
/// under `-uitest-reset`, so these launch with `-tips` as well.
final class TutorialTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Two new people share this phone (pass and play) against a House Cat. Each one's first look
    /// at their hand starts with the goal tip, addressed to them; no tip ever shows twice to the
    /// same person, however many turns go by. The people play phase 1 for real (collect sets,
    /// lay down, hit) until the first round is over, so the later tips come up too. Every tip
    /// seen is screenshotted.
    @MainActor
    func testEachNewPersonGetsTheTipsOnce() throws {
        let restoreQuiescence = Quiescence.disable()
        addTeardownBlock { @MainActor in restoreQuiescence() }
        let app = Live.app()
        app.launchArguments.append("-tips")
        app.launch()
        onboard(app)
        newGame(app)
        seatMenu(app, seat: 1, "here")
        addLocalPerson(app)
        XCTAssertTrue(until(10) { self.el(app, "lobby.seat.1").label.contains("on this phone") }, "no second local seat")
        seatMenu(app, seat: 2, "bot")
        XCTAssertTrue(until(10) { self.el(app, "lobby.seat.2").label.contains("bot") }, "no bot at seat 2")
        el(app, "lobby.start").tap()

        // Whose hand is face up: the name on the last curtain held.
        var holder: String?
        var shown: [String: [String]] = [:]
        var screenshotted = Set<String>()
        var turns: [String: Int] = [:]
        var acted = false
        // The tip a "Got it" tap missed (the bubble was still springing in): still the same showing.
        var missed: String?
        var firstRound = 0, roundOver = false
        let deadline = Date().addingTimeInterval(Live.t(1500))
        while Date() < deadline {
            if roundOver, shown.count == 2, turns.values.count == 2, turns.values.allSatisfy({ $0 >= 3 }) { break }
            guard let snap = UISnap(app) else {
                Thread.sleep(forTimeInterval: 2)
                continue
            }
            if let tip = snap.value("coach.tip") {
                let who = holder ?? "?"
                if tip != missed {
                    XCTAssertFalse(shown[who, default: []].contains(tip), "\(who) saw the \(tip) tip twice: \(shown)")
                    shown[who, default: []].append(tip)
                }
                missed = nil
                if tip == "goal" {
                    let text = snap.label("coach.tip") ?? ""
                    XCTAssertTrue(text.contains(who), "the goal tip isn't for \(who): \(text)")
                    XCTAssertEqual(shown[who]?.first, "goal", "\(who)'s first tip wasn't the goal: \(shown)")
                }
                Thread.sleep(forTimeInterval: 1)  // the bubble springs in
                if screenshotted.insert(tip).inserted { screenshot(app, "tip-\(tip)") }
                guard let ok = (UISnap(app) ?? snap).frame("coach.ok") else { continue }
                tap(app, ok)
                acted = false  // the next tip may follow: wait for it before acting again
                if untilSnap(app, 5, every: 0.5, { $0.value("coach.tip") != tip }) == nil { missed = tip }
                continue
            }
            missed = nil
            if snap.exists("priming.notNow") {
                dismissPriming(app, snap)
                continue
            }
            if let name = holdCurtain(app, snap) {
                holder = name
                acted = false
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            if let d = snap.debug {
                if firstRound == 0 { firstRound = d.round }
                if d.status != "playing" || d.round > firstRound { roundOver = true }
            }
            guard let d = snap.debug, snap.value("table.turn") == "mine", d.settled, d.status == "playing",
                  let first = snap.label("table.hand.0"), first != "Card" else {
                Thread.sleep(forTimeInterval: 2)
                continue
            }
            if d.step == "draw", let deck = snap.frame("table.deck") {
                // Give a tip a moment to come up before acting (one appears ~1 s after the table settles).
                if !acted {
                    acted = true
                    Thread.sleep(forTimeInterval: 2.5)
                    continue
                }
                tap(app, deck)
                acted = false
                Thread.sleep(forTimeInterval: 2)
            } else if d.step == "play" {
                // Every move waits for the table to settle first, so a tip it brings on shows.
                if !acted {
                    acted = true
                    Thread.sleep(forTimeInterval: 2.5)
                    continue
                }
                acted = false
                if playOneMove(app, snap, handCount: d.handCount, laid: d.laid), let holder {
                    turns[holder, default: 0] += 1
                }
                Thread.sleep(forTimeInterval: 1.5)
            }
        }
        let summary = "tips by person \(shown), turns \(turns)"
        let note = XCTAttachment(string: summary)
        note.name = "tutorial summary"
        note.lifetime = .keepAlways
        add(note)
        print("[tutorial] \(summary)")
        XCTAssertEqual(shown.count, 2, "both people should get tips: \(shown)")
        for (who, tips) in shown {
            XCTAssertEqual(tips.first, "goal", "\(who) didn't start with the goal: \(tips)")
            XCTAssertTrue(tips.contains("draw"), "\(who) never got the draw tip: \(tips)")
        }
        XCTAssertTrue(turns.values.allSatisfy { $0 >= 3 }, "too few turns played: \(turns)")
    }

    /// The rules from Home's gear, and the pill that brings the tips back.
    @MainActor
    func testHowToPlayFromHome() throws {
        let app = Live.app()
        app.launch()
        onboard(app)
        el(app, "home.settings").tap()
        let rules = el(app, "settings.rules")
        XCTAssertTrue(rules.waitForExistence(timeout: Live.t(5)), "no How to play in the gear")
        rules.tap()
        XCTAssertTrue(el(app, "sheet-rules").waitForExistence(timeout: Live.t(5)), "no rules sheet")
        screenshot(app, "rules")
        // The pill sits under the ten phases.
        let replay = el(app, "rules.replay")
        XCTAssertTrue(until(10) {
            if replay.isHittable { return true }
            self.el(app, "sheet-rules").swipeUp()
            return replay.isHittable
        }, "no Show the tips again pill")
        replay.tap()
        el(app, "rules.close").tap()
        XCTAssertTrue(until(5) { !self.el(app, "sheet-rules").exists }, "the rules sheet didn't close")
    }

    /// A card as VoiceOver names it: "7, tabby", "Yarn, wild", "Cucumber, skip".
    private enum Face: Equatable {
        case number(Int), yarn, cucumber

        init?(_ label: String) {
            if label.hasPrefix("Yarn") {
                self = .yarn
            } else if label.hasPrefix("Cucumber") {
                self = .cucumber
            } else if let value = label.split(separator: ",").first.flatMap({ Int($0) }) {
                self = .number(value)
            } else {
                return nil
            }
        }

        var value: Int? {
            if case .number(let v) = self { return v }
            return nil
        }
    }

    /// One play-step move for a phase of sets, by taps: lay down a full phase, fill a tray (only
    /// once the whole phase can be made), hit a laid set, or else end the turn with a discard
    /// (a Cucumber first, at a glowing cat; then the loneliest number). True when it discarded.
    @MainActor
    private func playOneMove(_ app: XCUIApplication, _ snap: UISnap, handCount: Int, laid: Bool) -> Bool {
        let hand: [(id: String, face: Face)] = (0..<handCount).compactMap { i in
            let id = "table.hand.\(i)"
            return snap.label(id).flatMap(Face.init).map { (id, $0) }
        }
        func pick(_ id: String, then target: CGRect) {
            guard let card = snap.frame(id) else { return }
            tap(app, card)
            Thread.sleep(forTimeInterval: 0.6)
            tap(app, target)
        }
        if let layDown = snap.frame("table.laydown") {
            tap(app, layDown)
            return false
        }
        var counts: [Int: Int] = [:]
        for card in hand { if let v = card.face.value { counts[v, default: 0] += 1 } }
        let yarns = hand.filter { $0.face == .yarn }
        if !laid, let move = trayMove(snap, hand: hand, counts: counts, yarns: yarns.count) {
            pick(move.card, then: move.tray)
            return false
        }
        if laid {
            for (key, item) in snap.items where key.hasPrefix("table.group.") {
                let faces = (item.label.split(separator: ":", maxSplits: 1).last ?? "")
                    .split(separator: ";").compactMap { Face($0.trimmingCharacters(in: .whitespaces)) }
                let values = Set(faces.compactMap(\.value))
                guard values.count == 1, let v = values.first,
                      let card = hand.first(where: { $0.face == .number(v) }) else { continue }
                pick(card.id, then: item.frame)
                return false
            }
        }
        guard let pile = snap.frame("table.discard") else { return false }
        if let cucumber = hand.first(where: { $0.face == .cucumber }), let card = snap.frame(cucumber.id) {
            tap(app, card)
            Thread.sleep(forTimeInterval: 1)
            if let cat = UISnap(app)?.items.first(where: { $0.key.hasPrefix("table.opponent.") && $0.value.value == "glowing" }) {
                tap(app, cat.value.frame)
            } else {
                tap(app, pile)
            }
            return true
        }
        let numbers = hand.filter { $0.face.value != nil }
        guard let loneliest = numbers.min(by: { counts[$0.face.value!]! < counts[$1.face.value!]! }) ?? hand.first else {
            return false
        }
        pick(loneliest.id, then: pile)
        return true
    }

    /// The next card to put in a set tray, once the hand (plus what the trays hold) makes the whole
    /// phase: the tray's number, else a Yarn.
    @MainActor
    private func trayMove(_ snap: UISnap, hand: [(id: String, face: Face)], counts: [Int: Int], yarns: Int)
        -> (card: String, tray: CGRect)? {
        var trays: [(frame: CGRect, size: Int, held: [Face])] = []
        for i in 0..<4 {
            guard let label = snap.label("table.tray.\(i)"), let frame = snap.frame("table.tray.\(i)") else { break }
            guard label.contains("set of"), let size = label.split(separator: " ").last.flatMap({ Int($0) }) else {
                return nil
            }
            let held = (0..<12).compactMap { snap.label("table.traycard.\(i).\($0)").flatMap(Face.init) }
            trays.append((frame, size, held))
        }
        guard !trays.isEmpty else { return nil }
        // Each tray's number: what it holds, else the best one left in the hand.
        var taken = Set<Int>()
        var plan: [Int] = []
        for tray in trays {
            if let v = tray.held.compactMap(\.value).first {
                plan.append(v)
                taken.insert(v)
            } else {
                plan.append(-1)
            }
        }
        for (i, v) in plan.enumerated() where v == -1 {
            guard let best = counts.filter({ !taken.contains($0.key) }).max(by: { $0.value < $1.value })?.key else { return nil }
            plan[i] = best
            taken.insert(best)
        }
        let short = zip(trays, plan).map { tray, v in max(tray.size - tray.held.count - (counts[v] ?? 0), 0) }
        guard short.reduce(0, +) <= yarns else { return nil }
        for (i, tray) in trays.enumerated() where tray.held.count < tray.size {
            let card = hand.first { $0.face == .number(plan[i]) } ?? hand.first { $0.face == .yarn }
            if let card { return (card.id, tray.frame) }
        }
        return nil
    }
}
