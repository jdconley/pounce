import Foundation
import Testing
@testable import PounceKit

@Suite struct ProtocolTests {
    // MARK: helpers

    private func fixture(_ name: String) throws -> String {
        guard let found = try Fixtures.serverMessages().first(where: { $0.name == name }) else {
            throw Fixtures.FixtureError.malformed("no server fixture \(name)")
        }
        return found.json
    }

    private func jsonObject(_ text: String) throws -> NSObject {
        let any = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        return any as! NSObject
    }

    private func jsonEqual(_ a: String, _ b: String) throws -> Bool {
        try jsonObject(a).isEqual(try jsonObject(b))
    }

    private let alice = Person(id: "11111111-1111-4111-8111-111111111111", name: "Alice", cat: 0)

    private func sample(_ name: String) throws -> ClientMessage {
        switch name {
        case "claim": return .claim(seat: 0, person: alice)
        case "configure-open": return .configure(seat: 1, kind: .open)
        case "configure-bot": return .configure(seat: 2, kind: .bot)
        case "configure-closed": return .configure(seat: 3, kind: .closed)
        case "start": return .start
        case "act-draw-deck": return .act(seat: 0, action: .draw(.deck))
        case "act-draw-discard": return .act(seat: 0, action: .draw(.discard))
        case "act-layDown":
            return .act(seat: 0, action: .layDown([LayGroup(cards: [4, 28, 52]), LayGroup(cards: [8, 32, 56])]))
        case "act-layDown-runStart":
            return .act(seat: 0, action: .layDown([LayGroup(cards: [9, 10, 11, 96], runStart: 9)]))
        case "act-hit": return .act(seat: 0, action: .hit(card: 76, target: HitTarget(seat: 1, group: 0)))
        case "act-discard": return .act(seat: 0, action: .discard(card: 11, skipTarget: nil))
        case "act-discard-skip": return .act(seat: 0, action: .discard(card: 104, skipTarget: 2))
        case "act-nextRound": return .act(seat: 0, action: .nextRound)
        case "presence-active": return .presence(.active)
        case "presence-background": return .presence(.background)
        case "moveSeat": return .moveSeat(seat: 1)
        case "claimMove": return .claimMove(code: "BCDFGH")
        case "leave": return .leave(seat: 1)
        case "rename": return .rename(seat: 1, name: "Mo")
        default: throw Fixtures.FixtureError.malformed("no sample for client fixture \(name)")
        }
    }

    // MARK: fixtures

    @Test func decodesEveryServerFixture() throws {
        for (name, json) in try Fixtures.serverMessages() {
            #expect(throws: Never.self, "\(name)") { _ = try Codec.decode(json) }
        }
    }

    @Test func playingSnapshotHasStringKeyedHand() throws {
        guard case .snapshot(let p, _, let room) = try Codec.decode(fixture("snapshot-playing-with-hand")) else {
            Issue.record("not a snapshot"); return
        }
        #expect(p == 1)
        #expect(room.game?.hands.keys.sorted() == [0])
        #expect(room.game?.hands[0]?.count == 11 || room.game?.hands[0]?.count == 10)
    }

    @Test func otherSeatsDeckDrawHasNoCard() throws {
        guard case .event(_, .game(.drew(_, .deck, let card))) = try Codec.decode(fixture("event-drew-deck-other")) else {
            Issue.record("not a drew event"); return
        }
        #expect(card == nil)
    }

    @Test func encodesEveryClientFixture() throws {
        let fixtures = try Fixtures.clientMessages()
        #expect(fixtures.count == 19)
        for (name, json) in fixtures {
            #expect(try jsonEqual(Codec.encode(sample(name)), json), "\(name)")
        }
    }

    @Test func unknownErrorCodeStillDecodes() throws {
        #expect(try Codec.decode(#"{"t":"error","code":"new_thing"}"#) == .error(ErrorCode(rawValue: "new_thing")))
    }

    @Test func knownErrorCodesMatchServerStrings() throws {
        #expect(try Codec.decode(try fixture("error-room_closed")) == .error(.roomClosed))
        #expect(try Codec.decode(try fixture("error-bad_code")) == .error(.badCode))
        #expect(ErrorCode.botStalled.rawValue == "bot_stalled")
        #expect(ErrorCode.tooManyAttempts.rawValue == "too_many_attempts")
        #expect(ErrorCode.notYourTurn.rawValue == "not_your_turn")
        #expect(ErrorCode.badStep.rawValue == "bad_step")
        #expect(ErrorCode.seatsOpen.rawValue == "seats_open")
        #expect(ErrorCode.notEnoughPlayers.rawValue == "not_enough_players")
    }

    // MARK: server message details

    @Test func lobbySnapshotSeatsAndAbsentPerson() throws {
        guard case .snapshot(_, let seq, let room) = try Codec.decode(fixture("snapshot-lobby")) else {
            Issue.record("not a snapshot"); return
        }
        #expect(seq == 3)
        #expect(room.status == .lobby)
        #expect(room.game == nil)
        #expect(room.seats[0].person == Person(id: "11111111-1111-4111-8111-111111111111", name: "Alice", cat: 0))
        #expect(room.seats[1].yours)
        #expect(room.seats[2].kind == .bot)
        #expect(room.seats[2].person == nil)
        #expect(room.seats[2].presence == nil)
    }

    @Test func spectatorSnapshotHasEmptyHands() throws {
        guard case .snapshot(_, _, let room) = try Codec.decode(fixture("snapshot-playing-no-hand")) else {
            Issue.record("not a snapshot"); return
        }
        #expect(room.game?.hands.isEmpty == true)
        #expect(room.game?.laid.count == room.game?.handCounts.count)
    }

    @Test func eventsDecodeToExpectedCases() throws {
        #expect(try Codec.decode(fixture("event-presence")) == .event(seq: 2, event: .presence(seat: 1, presence: .away)))
        #expect(try Codec.decode(fixture("event-roundStarted"))
            == .event(seq: 3, event: .game(.roundStarted(round: 2, dealer: 1))))
        #expect(try Codec.decode(fixture("event-drew-deck-own"))
            == .event(seq: 4, event: .game(.drew(seat: 1, from: .deck, card: 17))))
        #expect(try Codec.decode(fixture("event-drew-discard"))
            == .event(seq: 6, event: .game(.drew(seat: 1, from: .discard, card: 40))))
        #expect(try Codec.decode(fixture("event-hit"))
            == .event(seq: 8, event: .game(.hit(seat: 0, card: 76, target: HitTarget(seat: 1, group: 0),
                                                group: .set(cards: [4, 28, 52, 76], value: 5)))))
        #expect(try Codec.decode(fixture("event-discarded"))
            == .event(seq: 9, event: .game(.discarded(seat: 1, card: 11, skipTarget: nil))))
        #expect(try Codec.decode(fixture("event-discarded-skip"))
            == .event(seq: 10, event: .game(.discarded(seat: 0, card: 104, skipTarget: 2))))
        #expect(try Codec.decode(fixture("event-skipped")) == .event(seq: 11, event: .game(.skipped(seat: 2))))
        #expect(try Codec.decode(fixture("event-turn")) == .event(seq: 12, event: .game(.turn(seat: 0))))
        #expect(try Codec.decode(fixture("event-reshuffled"))
            == .event(seq: 13, event: .game(.reshuffled(deckCount: 94))))
        #expect(try Codec.decode(fixture("event-roundOver"))
            == .event(seq: 14, event: .game(.roundOver(wentOut: 1, points: [35, 0, 40], advanced: [1],
                                                       scores: [35, 0, 40], phase: [0, 1, 0]))))
        #expect(try Codec.decode(fixture("event-roundOver-nobody"))
            == .event(seq: 15, event: .game(.roundOver(wentOut: nil, points: [20, 45, 30], advanced: [],
                                                       scores: [20, 45, 30], phase: [0, 0, 0]))))
        #expect(try Codec.decode(fixture("event-gameOver")) == .event(seq: 16, event: .game(.gameOver(winners: [1]))))
        #expect(try Codec.decode(fixture("moveCode")) == .moveCode(seat: 1, code: "BCDFGH"))
    }

    @Test func futureProtocolSnapshotIsUnsupportedNotRejected() throws {
        #expect(try Codec.decode(#"{"t":"snapshot","protocol":2,"seq":1,"room":{"weird":true}}"#)
            == .unsupportedProtocol(2))
        // Protocol 1 still decodes the room, and a broken protocol-1 room still throws.
        guard case .snapshot(1, _, _) = try Codec.decode(fixture("snapshot-lobby")) else {
            Issue.record("protocol 1 snapshot did not decode"); return
        }
        #expect(throws: (any Error).self) {
            _ = try Codec.decode(#"{"t":"snapshot","protocol":1,"seq":1,"room":{"weird":true}}"#)
        }
    }

    @Test func malformedAndUnknownMessagesThrow() {
        #expect(throws: (any Error).self) { _ = try Codec.decode("not json") }
        #expect(throws: (any Error).self) { _ = try Codec.decode(#"{"t":"mystery"}"#) }
        #expect(throws: (any Error).self) { _ = try Codec.decode(#"{"t":"event","seq":1,"event":{"kind":"nope"}}"#) }
    }

    // MARK: run / coat / laid paths (fixtures only cover sets and null laid)

    private let richGameJSON = """
    {"t":"snapshot","protocol":1,"seq":9,"room":{"code":"BCDFG","status":"playing","youAreHost":false,
    "seats":[{"kind":"human","person":{"id":"11111111-1111-4111-8111-111111111111","name":"Alice","cat":0},"yours":true,"presence":"awake"},
             {"kind":"bot","yours":false,"presence":null}],
    "game":{"round":3,"dealer":1,"turn":0,"step":"play","status":"playing","deckCount":50,"discardTop":null,
    "discardCount":0,"phase":[2,3],"scores":[10,20],
    "laid":[[{"kind":"run","cards":[9,10,11,96],"start":9,"end":12}],
            [{"kind":"coat","cards":[0,1,2,3],"coat":"tabby"},{"kind":"set","cards":[4,28,52],"value":5}]],
    "handCounts":[4,3],"hands":{"0":[1,2,3,4]},"pendingSkip":[false,true],"winners":[]}}}
    """

    @Test func decodesRunCoatAndLaidGroups() throws {
        guard case .snapshot(_, _, let room) = try Codec.decode(richGameJSON), let game = room.game else {
            Issue.record("not a game snapshot"); return
        }
        #expect(game.laid[0] == [.run(cards: [9, 10, 11, 96], start: 9, end: 12)])
        #expect(game.laid[1] == [.coat(cards: [0, 1, 2, 3], coat: .tabby), .set(cards: [4, 28, 52], value: 5)])
        #expect(game.discardTop == nil)
        #expect(game.pendingSkip == [false, true])
        #expect(game.hands == [0: [1, 2, 3, 4]])
    }

    @Test func gameViewRoundTripsWithNullAndNonNullLaid() throws {
        let game = GameView(
            round: 1, dealer: 0, turn: 1, step: .play, status: .playing, deckCount: 70, discardTop: 12,
            discardCount: 3, phase: [0, 0, 0], scores: [0, 5, 0],
            laid: [nil, [.run(cards: [9, 10, 11], start: 9, end: 11), .coat(cards: [1, 2], coat: .gray)], nil],
            handCounts: [10, 6, 10], hands: [0: [1, 2], 2: [3]], pendingSkip: [false, false, false], winners: [])
        let data = try JSONEncoder().encode(game)
        #expect(try JSONDecoder().decode(GameView.self, from: data) == game)

        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hands = try #require(object["hands"] as? [String: [Int]])
        #expect(hands == ["0": [1, 2], "2": [3]])
        let laid = try #require(object["laid"] as? [Any])
        #expect(laid[0] is NSNull)
        #expect(!(laid[1] is NSNull))
    }

    @Test func roomViewRoundTrips() throws {
        guard case .snapshot(_, _, let room) = try Codec.decode(richGameJSON) else {
            Issue.record("not a snapshot"); return
        }
        let again = try JSONDecoder().decode(RoomView.self, from: JSONEncoder().encode(room))
        #expect(again == room)
    }

    @Test func gameEventsRoundTripIncludingRunGroup() throws {
        let events: [GameEvent] = [
            .laidDown(seat: 1, groups: [.run(cards: [9, 10, 11, 96], start: 9, end: 12), .coat(cards: [0, 1], coat: .calico)]),
            .hit(seat: 0, card: 12, target: HitTarget(seat: 1, group: 0), group: .run(cards: [8, 9], start: 8, end: 9)),
            .drew(seat: 0, from: .deck, card: nil),
            .discarded(seat: 0, card: 105, skipTarget: 1),
            .roundOver(wentOut: nil, points: [1], advanced: [], scores: [1], phase: [0]),
        ]
        for event in events {
            let again = try JSONDecoder().decode(GameEvent.self, from: JSONEncoder().encode(event))
            #expect(again == event)
        }
    }

    @Test func absentOptionalsAreOmittedWhenEncoding() throws {
        let drew = try JSONEncoder().encode(GameEvent.drew(seat: 2, from: .deck, card: nil))
        #expect(try jsonEqual(String(decoding: drew, as: UTF8.self),
                              #"{"kind":"drew","seat":2,"from":"deck"}"#))
        let discard = try Codec.encode(.act(seat: 0, action: .discard(card: 11, skipTarget: nil)))
        #expect(!discard.contains("skipTarget"))
        let lay = try Codec.encode(.act(seat: 0, action: .layDown([LayGroup(cards: [1])])))
        #expect(!lay.contains("runStart"))
    }
}
