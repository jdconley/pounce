import Foundation
import Testing
@testable import PounceKit

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
        #expect(fixtures.count >= 20)
        for (name, json) in fixtures {
            #expect(throws: Never.self, "\(name)") { _ = try Codec.decode(json) }
        }
    }

    @Test func aLobbyNamesItsGameAndTimer() throws {
        let phone = try room("snapshot-lobby-phone")
        #expect(phone.isPurrtrait)
        #expect(phone.purrtrait == nil)
        #expect(phone.options?.timer == 60)
        #expect(phone.purrTimer == 60)
        #expect(phone.near == nil)
        #expect(phone.seats.count == 10)
    }

    @Test func onlyTheScreensSnapshotCarriesTheNearKey() throws {
        let screen = try room("snapshot-lobby-screen")
        #expect(screen.near == RoomNear(key: "H4TR9WQZ", code: "KQ7XPMH4", expiresIn: 21000))
        #expect(screen.purrTimer == 90)
    }

    @Test func theDrawerSeesTwoWordsWhileChoosing() throws {
        let view = try #require(try room("snapshot-choosing-drawer").purrtrait)
        #expect(view.phase == .choosing)
        #expect(view.drawer == 0)
        #expect(view.choices == PurrChoices(easy: "pizza", tricky: "sandcastle"))
        #expect(view.word == nil)
        #expect(!view.youDraw)
        #expect(view.remainingMs == 9400)
    }

    @Test func aGuesserSeesNoWordEver() throws {
        for name in ["snapshot-choosing-guesser", "snapshot-drawing-guesser", "snapshot-drawing-screen-paused"] {
            let view = try #require(try room(name).purrtrait)
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
        #expect(view.word == "pizza")
        #expect(view.youDraw)
        #expect(view.group == .food)
        #expect(view.level == .easy)
        #expect(view.turn == "1:0")
        #expect(room.liveTurn == 0)
    }

    @Test func thePausedClockSaysSo() throws {
        let view = try #require(try room("snapshot-drawing-screen-paused").purrtrait)
        #expect(view.paused)
        #expect(view.remainingMs == 41000)
    }

    @Test func theRevealNamesTheWordAndWhoGotIt() throws {
        let view = try #require(try room("snapshot-reveal").purrtrait)
        #expect(view.phase == .reveal)
        #expect(view.last == PurrLast(word: "pizza", guesser: 1, points: 1))
        #expect(view.scores == [1, 1, 0])
    }

    @Test func gameOverSharesATie() throws {
        let room = try room("snapshot-over")
        let view = try #require(room.purrtrait)
        #expect(view.phase == .over)
        #expect(view.drawer == nil)
        #expect(view.winners == [0, 1])
        #expect(view.last?.guesser == nil)
        #expect(room.liveTurn == nil)
    }

    @Test func eventsDecode() throws {
        #expect(try event("event-turn") == .turn(drawer: 1, round: 1))
        #expect(try event("event-chosen") == .chosen(drawer: 0, group: .food, level: .easy))
        #expect(try event("event-guessed") == .guessed(drawer: 0, guesser: 1, points: 1, word: "pizza"))
        #expect(try event("event-missed") == .missed(drawer: 0, word: "pizza", reason: .time))
        #expect(try event("event-over") == .over(winners: [0, 1], scores: [5, 5, 3]))
    }

    @Test func inkMessagesDecode() throws {
        #expect(try fixture("ink") == .ink(seat: 0, turn: "1:0", ops: [
            .stroke(id: 0, color: 0, width: 1, start: InkPoint(384, 210), deltas: [InkPoint(3, -1), InkPoint(4, 0)]),
            .extend(id: 0, deltas: [InkPoint(2, 2), InkPoint(1, 3)]),
            .undo(id: 0),
            .clear,
        ]))
        #expect(try fixture("inkSync") == .inkSync(turn: "1:0", ops: [
            .stroke(id: 4, color: 5, width: 2, start: InkPoint(100, 100), deltas: [InkPoint(10, 0), InkPoint(10, 0)]),
        ]))
        #expect(try fixture("inkResend") == .inkResend(turn: "1:0"))
    }

    @Test func newErrorsDecode() throws {
        #expect(try fixture("error-easel-full") == .error(.easelFull))
        #expect(try fixture("error-not-near") == .error(.notNear))
        #expect(try fixture("error-removed") == .error(.removed))
        #expect(try fixture("error-no-screen") == .error(.noScreen))
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
            ("act-choose-easy", .actPurrtrait(seat: 0, action: .choose(.easy))),
            ("act-choose-tricky", .actPurrtrait(seat: 0, action: .choose(.tricky))),
            ("act-gotIt", .actPurrtrait(seat: 0, action: .gotIt(2))),
            ("act-giveUp", .actPurrtrait(seat: 0, action: .giveUp)),
            ("act-forfeit", .actPurrtrait(seat: 1, action: .forfeit)),
            ("ink", .ink(seat: 3, turn: "2:5", ops: [
                .stroke(id: 0, color: 0, width: 1, start: InkPoint(384, 210), deltas: [InkPoint(3, -1)]),
                .extend(id: 0, deltas: [InkPoint(2, 2)]), .undo(id: 0), .clear,
            ])),
            ("remove", .remove(seat: 4)),
            ("setOptions-timer", .setOptions(RoomOptions(timer: 45))),
        ]
        for (name, message) in cases {
            let want = try #require(fixtures[name], "no client fixture \(name)")
            #expect(try jsonEqual(Codec.encode(message), want), "\(name)")
        }
    }

    @Test func theSocketURLCarriesTheNearKey() {
        let config = APIConfig(baseURL: URL(string: "http://localhost:8798")!)
        #expect(config.socketURL(code: "KQ7XPM", near: "H4TR9WQZ").absoluteString == "ws://localhost:8798/v1/rooms/KQ7XPM/ws?near=H4TR9WQZ")
        #expect(config.socketURL(code: "KQ7XPM").absoluteString == "ws://localhost:8798/v1/rooms/KQ7XPM/ws")
    }

    @Test func aRefusedPhoneSaysWhy() {
        #expect(RoomSocket.refusal(.denied("removed"), near: "K") == .removed)
        #expect(RoomSocket.refusal(.denied("not_near"), near: nil) == .notNear)
        #expect(RoomSocket.refusal(.forbidden, near: "K") == .notNear)
        #expect(RoomSocket.refusal(.forbidden, near: nil) == nil)
        #expect(RoomSocket.refusal(.notFound, near: nil) == nil)
    }

    @Test func theNextDrawerWrapsIntoRoundTwoAndStopsAtTheEnd() {
        var view = PurrView(seats: 3, phase: .drawing, drawer: 2, order: [0, 1, 2], scores: [0, 0, 0])
        #expect(view.nextDrawer == 0)
        view.round = 2
        #expect(view.nextDrawer == nil)
        view.drawer = 1
        #expect(view.nextDrawer == 2)
    }
}
