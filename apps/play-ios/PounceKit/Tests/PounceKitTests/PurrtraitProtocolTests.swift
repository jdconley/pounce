import Foundation
import Testing
@testable import PounceKit

/// Purrtrait's wire against play-api's samples from real rooms
/// (`apps/play-api/fixtures/protocol/purrtrait-*.json`).
@Suite struct PurrtraitProtocolTests {
    private func fixture(_ name: String) throws -> ServerMessage {
        let json = try #require(try Fixtures.purrtraitServerMessages().first { $0.name == name }, "no purrtrait fixture \(name)").json
        return try Codec.decode(json)
    }

    private func room(_ name: String) throws -> RoomView {
        guard case .snapshot(_, _, let room) = try fixture(name) else { throw Fixtures.FixtureError.malformed(name) }
        return room
    }

    private func event(_ name: String) throws -> PurrEvent {
        guard case .event(_, .purrtrait(let event)) = try fixture(name) else { throw Fixtures.FixtureError.malformed(name) }
        return event
    }

    private func jsonEqual(_ a: String, _ b: String) throws -> Bool {
        let x = try JSONSerialization.jsonObject(with: Data(a.utf8)) as! NSObject
        let y = try JSONSerialization.jsonObject(with: Data(b.utf8)) as! NSObject
        return x.isEqual(y)
    }

    // MARK: server to client

    @Test func decodesEveryPurrtraitFixture() throws {
        let fixtures = try Fixtures.purrtraitServerMessages()
        #expect(fixtures.count >= 40)
        for (name, json) in fixtures {
            #expect(throws: Never.self, "\(name)") { _ = try Codec.decode(json) }
        }
    }

    @Test func aLobbyNamesItsGameAndTimer() throws {
        let host = try room("snapshot-lobby-host")
        #expect(host.isPurrtrait)
        #expect(host.purrtrait == nil)
        #expect(host.options?.timer == 90)
        #expect(host.purrTimer == 90)
        #expect(host.near == nil)
        #expect(host.youAreHost)
    }

    @Test func onlyTheScreensSnapshotCarriesTheNearKey() throws {
        for name in ["snapshot-lobby-screen", "snapshot-choosing-screen", "snapshot-drawing-screen", "snapshot-reveal-screen"] {
            let screen = try room(name)
            let near = try #require(screen.near, "\(name)")
            #expect(RoomCode.isValidNearKey(near.key), "\(name)")
            #expect(near.code.count == RoomCode.easelLength, "\(name)")
            #expect(near.code == screen.code + near.key.prefix(3), "\(name)")
        }
        for name in ["snapshot-lobby-host", "snapshot-lobby-guest", "snapshot-drawing-drawer", "snapshot-drawing-guesser"] {
            #expect(try room(name).near == nil, "\(name)")
        }
    }

    @Test func theDrawerSeesTwoWordsWhileChoosing() throws {
        let view = try #require(try room("snapshot-choosing-drawer").purrtrait)
        #expect(view.phase == .choosing)
        #expect(view.drawer == 0)
        #expect(view.choices == PurrChoices(easy: "robot", tricky: "thunder"))
        #expect(view.word == nil)
        #expect(!view.youDraw)
        #expect(view.remainingMs == 8000)
        // Before the pick every device holding the drawer's seat has the words.
        #expect(try room("snapshot-choosing-drawer-other-device").purrtrait?.choices != nil)
        #expect(try room("snapshot-choosing-kitten-drawer").purrtrait?.choices == PurrChoices(easy: "robot", tricky: "store"))
    }

    @Test func noWordReachesAGuesserOrTheTV() throws {
        for name in ["snapshot-choosing-guesser", "snapshot-choosing-screen", "snapshot-drawing-guesser", "snapshot-drawing-screen",
                     "snapshot-drawing-drawer-other-device", "snapshot-paused-guesser"] {
            let view = try #require(try room(name).purrtrait, "\(name)")
            #expect(view.choices == nil, "\(name)")
            #expect(view.word == nil, "\(name)")
            #expect(!view.youDraw, "\(name)")
            #expect(view.last == nil, "\(name)")
        }
    }

    @Test func theDrawersDeviceHasTheWordWhileDrawing() throws {
        let room = try room("snapshot-drawing-drawer")
        let view = try #require(room.purrtrait)
        #expect(view.phase == .drawing)
        #expect(view.word == "thunder")
        #expect(view.youDraw)
        #expect(view.group == .outside)
        #expect(view.level == .tricky)
        #expect(view.remainingMs == 75000)
        #expect(view.turn == "1:0")
        #expect(room.liveTurn == 0)
        #expect(PurrTableModel(room: room)?.screen == .draw(seat: 0, word: "thunder"))
        // The drawer's other device watches the TV like everyone else.
        #expect(PurrTableModel(room: try self.room("snapshot-drawing-drawer-other-device"))?.screen == .watch)
    }

    @Test func thePausedClockSaysSo() throws {
        let room = try room("snapshot-paused-guesser")
        let view = try #require(room.purrtrait)
        #expect(view.paused)
        #expect(view.remainingMs == 65000)
        #expect(PurrTableModel(room: room)?.deadline(arrived: Date()) == nil)
        #expect(try self.room("snapshot-paused-drawer").purrtrait?.word == "thunder")
    }

    @Test func theRevealNamesTheWordAndWhoGotIt() throws {
        let view = try #require(try room("snapshot-reveal-guesser").purrtrait)
        #expect(view.phase == .reveal)
        #expect(view.last == PurrLast(word: "thunder", guesser: 2, points: 2))
        #expect(view.scores == [2, 0, 2, 0])
        #expect(view.remainingMs == nil)
        #expect(try room("snapshot-reveal-time-up-screen").purrtrait?.last == PurrLast(word: "eat", guesser: nil, points: 0))
        let removed = try #require(try room("snapshot-reveal-seat-removed-screen").purrtrait)
        #expect(removed.out == [false, false, false, true])
        #expect(removed.isOut(3))
    }

    @Test func gameOverHasItsWinnersAndWhoLeft() throws {
        let room = try room("snapshot-over-player")
        let view = try #require(room.purrtrait)
        #expect(view.phase == .over)
        #expect(view.drawer == nil)
        #expect(view.winners == [0])
        #expect(view.scores == [6, 3, 3, 0])
        #expect(view.out == [false, false, false, true])
        #expect(room.liveTurn == nil)
        #expect(PurrTableModel(room: room)?.screen == .over)
        #expect(PurrTableModel(room: room)?.standings.first?.seat == 0)
        #expect(try self.room("snapshot-over-stalled").purrtrait?.winners == [0, 1])
    }

    @Test func eventsDecode() throws {
        #expect(try event("event-turn") == .turn(drawer: 1, round: 1))
        #expect(try event("event-chosen") == .chosen(drawer: 0, group: .outside, level: .tricky))
        #expect(try event("event-guessed") == .guessed(drawer: 0, guesser: 2, points: 2, word: "thunder"))
        #expect(try event("event-missed-time") == .missed(drawer: 1, word: "eat", reason: .time))
        #expect(try event("event-missed-gaveUp") == .missed(drawer: 2, word: "builder", reason: .gaveUp))
        #expect(try event("event-missed-left") == .missed(drawer: 3, word: "cupcake", reason: .left))
        #expect(try event("event-over") == .over(winners: [0], scores: [6, 3, 3, 0]))
    }

    @Test func inkMessagesDecode() throws {
        guard case .ink(let seat, let turn, let ops) = try fixture("ink") else { Issue.record("not ink"); return }
        #expect(seat == 0)
        #expect(turn == "1:0")
        #expect(InkDrawing(ops: ops).strokes.first?.points.count == 9)
        guard case .inkSync(let syncTurn, let synced) = try fixture("inkSync") else { Issue.record("not inkSync"); return }
        #expect(syncTurn == "1:0")
        #expect(InkDrawing(ops: synced).strokes.map(\.id) == [0, 1, 2])
        #expect(try fixture("inkResend") == .inkResend(turn: "1:0"))
    }

    @Test func newErrorsDecode() throws {
        #expect(try fixture("error-easel_full") == .error(.easelFull))
        #expect(try fixture("error-not_near") == .error(.notNear))
        #expect(try fixture("error-removed") == .error(.removed))
        #expect(try fixture("error-no_screen") == .error(.noScreen))
    }

    /// A dev server running its clock fast scales the times: `29702.97` ms still reads.
    @Test func fractionalMillisecondsStillDecode() throws {
        let near = try JSONDecoder().decode(RoomNear.self, from: Data(#"{"key":"22RFPDW2","code":"68H2D22R","expiresIn":29702.97}"#.utf8))
        #expect(near.expiresIn == 29703)
        var json = try #require(try Fixtures.purrtraitServerMessages().first { $0.name == "snapshot-drawing-guesser" }).json
        json = json.replacingOccurrences(of: #""remainingMs":75000"#, with: #""remainingMs":74999.6"#)
        #expect(json.contains("74999.6"))
        guard case .snapshot(_, _, let room) = try Codec.decode(json) as ServerMessage else { Issue.record("not a snapshot"); return }
        #expect(room.purrtrait?.remainingMs == 75000)
    }

    @Test func anUnknownGroupOrEventIsNotABrokenRoom() throws {
        let json = #"{"t":"event","seq":3,"event":{"kind":"purrtrait","event":{"type":"confetti","drawer":0}}}"#
        #expect(try Codec.decode(json) == .event(seq: 3, event: .purrtrait(.unknown("confetti"))))
        let group = try JSONDecoder().decode(PurrGroup.self, from: Data(#""spaceships""#.utf8))
        #expect(group == .other)
    }

    @Test func aBadInkOpIsRejected() {
        for bad in [#"["s",0,0,1,384]"#, #"["p"]"#, #"["s",0,0,1,384,210,3]"#, #"["u",1,2]"#, #"["c",1]"#, #"["z",1]"#] {
            #expect(throws: (any Error).self, "\(bad)") { _ = try JSONDecoder().decode(InkOp.self, from: Data(bad.utf8)) }
        }
    }

    // MARK: client to server

    @Test func everyClientMessageMatchesItsFixture() throws {
        let fixtures = Dictionary(uniqueKeysWithValues: try Fixtures.purrtraitClientMessages().map { ($0.name, $0.json) })
        let cases: [(String, ClientMessage)] = [
            ("setOptions", .setOptions(RoomOptions(timer: 90))),
            ("act-choose-easy", .actPurrtrait(seat: 0, action: .choose(.easy))),
            ("act-choose-tricky", .actPurrtrait(seat: 0, action: .choose(.tricky))),
            ("act-gotIt", .actPurrtrait(seat: 0, action: .gotIt(2))),
            ("act-giveUp", .actPurrtrait(seat: 0, action: .giveUp)),
            ("act-forfeit", .actPurrtrait(seat: 1, action: .forfeit)),
            ("ink", .ink(seat: 0, turn: "1:0", ops: [
                .stroke(id: 4, color: 0, width: 1, start: InkPoint(384, 210), deltas: [InkPoint(3, -1), InkPoint(4, 0)]),
                .extend(id: 4, deltas: [InkPoint(2, 2), InkPoint(1, 3)]),
            ])),
            ("ink-undo", .ink(seat: 0, turn: "1:0", ops: [.undo(id: 4)])),
            ("ink-clear", .ink(seat: 0, turn: "1:0", ops: [.clear])),
            ("ink-resend", .ink(seat: 0, turn: "1:0", ops: [
                .clear, .stroke(id: 7, color: 0, width: 1, start: InkPoint(384, 300), deltas: [InkPoint(40, 0), InkPoint(30, 30)]),
            ])),
            ("ink-resend-last", .ink(seat: 0, turn: "1:0", ops: [
                .stroke(id: 8, color: 0, width: 1, start: InkPoint(340, 280), deltas: [InkPoint(-20, -40)]),
            ], last: true)),
            ("ink-resend-single", .ink(seat: 0, turn: "1:0", ops: [
                .clear, .stroke(id: 7, color: 0, width: 1, start: InkPoint(384, 300), deltas: [InkPoint(40, 0)]),
            ], last: true)),
            ("remove", .remove(seat: 3)),
        ]
        #expect(Set(cases.map(\.0)) == Set(fixtures.keys), "a client fixture has no case here, or a case no fixture")
        for (name, message) in cases {
            let want = try #require(fixtures[name], "no client fixture \(name)")
            #expect(try jsonEqual(Codec.encode(message), want), "\(name)")
        }
    }

    @Test func theSocketURLCarriesTheNearKey() {
        let config = APIConfig(baseURL: URL(string: "http://localhost:8798")!)
        #expect(config.socketURL(code: "BCDFG", near: "BBBBQMK6").absoluteString == "ws://localhost:8798/v1/rooms/BCDFG/ws?near=BBBBQMK6")
        #expect(config.socketURL(code: "BCDFG").absoluteString == "ws://localhost:8798/v1/rooms/BCDFG/ws")
    }

    @Test func aRefusedPhoneSaysWhy() {
        #expect(RoomSocket.refusal(.denied("removed")) == .removed)
        #expect(RoomSocket.refusal(.denied("not_near")) == .notNear)
        #expect(RoomSocket.refusal(.forbidden) == nil)
        #expect(RoomSocket.refusal(.notFound) == nil)
    }

    @Test func theNextDrawerWrapsIntoRoundTwoAndStopsAtTheEnd() {
        var view = PurrView(seats: 3, phase: .drawing, drawer: 2, order: [0, 1, 2], scores: [0, 0, 0])
        #expect(view.nextDrawer == 0)
        view.round = 2
        #expect(view.nextDrawer == nil)
        view.drawer = 1
        #expect(view.nextDrawer == 2)
    }

    @Test func theTVsLinkIsTheEaselLink() {
        #expect(DeepLink.parse(URL(string: "https://play.conleychaos.com/e/BCDFG?near=BBBBQMK6")!) == .easel(code: "BCDFG", near: "BBBBQMK6"))
        #expect(DeepLink.parse(URL(string: "https://play.conleychaos.com/e/BCDFG")!) == .easel(code: "BCDFG", near: nil))
        #expect(DeepLink.parse(URL(string: "pounce-dev://e/BCDFG?near=BBBBQMK6")!, allowDevScheme: true) == .easel(code: "BCDFG", near: "BBBBQMK6"))
        #expect(DeepLink.parse(URL(string: "https://play.conleychaos.com/e/BCDFG?near=BBBBQMK6&move=y")!) == nil)
        #expect(DeepLink.easelURL(code: "BCDFG", near: "BBBBQMK6").absoluteString == "https://play.conleychaos.com/e/BCDFG?near=BBBBQMK6")
    }
}
