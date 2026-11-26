import Foundation
import Testing
@testable import PounceKit

@Suite struct BirdwatchProtocolTests {
    private func fixture(_ name: String) throws -> ServerMessage {
        let json = try #require(try Fixtures.birdwatchServerMessages().first { $0.name == name }, "no birdwatch fixture \(name)").json
        return try Codec.decode(json)
    }

    private func room(_ name: String) throws -> RoomView {
        guard case .snapshot(_, _, let room) = try fixture(name) else { throw Fixtures.FixtureError.malformed(name) }
        return room
    }

    private func event(_ name: String) throws -> BirdEvent {
        guard case .event(_, .birdwatch(let event)) = try fixture(name) else { throw Fixtures.FixtureError.malformed(name) }
        return event
    }

    private func jsonEqual(_ a: String, _ b: String) throws -> Bool {
        let x = try JSONSerialization.jsonObject(with: Data(a.utf8)) as! NSObject
        let y = try JSONSerialization.jsonObject(with: Data(b.utf8)) as! NSObject
        return x.isEqual(y)
    }

    // MARK: server to client

    @Test func decodesEveryBirdwatchFixture() throws {
        let fixtures = try Fixtures.birdwatchServerMessages()
        #expect(fixtures.count == 54)
        for (name, json) in fixtures {
            #expect(throws: Never.self, "\(name)") { _ = try Codec.decode(json) }
        }
    }

    @Test func aLobbyNamesItsGameAndRuleSet() throws {
        let room = try room("snapshot-lobby")
        #expect(room.isBirdwatch)
        #expect(room.birdwatch == nil)
        #expect(room.options == RoomOptions(rules: .tucker))
        #expect(room.birdRules == .tucker)
        #expect(room.seats.count == 6)
        #expect(room.seats[4].kind == .closed)
    }

    @Test func biddingOnMyMoveCarriesTheRange() throws {
        let room = try room("snapshot-bidding-your-move")
        let view = try #require(room.birdwatch)
        #expect(view.rules == .official)
        #expect(view.phase == .bidding)
        #expect(view.turn == 1)
        #expect(view.teams == [[0, 2], [1, 3]])
        #expect(view.hands[1] == [4, 6, 9, 24, 38, 49, 50, 53, 56])
        #expect(view.bidRange == BirdBidRange(min: 70, max: 120, step: 5))
        #expect(view.bids == [nil, nil, nil, nil])
        #expect(view.playable == nil)
        #expect(room.liveTurn == 1)
        #expect(room.birdRules == .official)
    }

    @Test func theNestComesOnlyToTheBidWinner() throws {
        let winner = try #require(try room("snapshot-nest-bid-winner").birdwatch)
        #expect(winner.phase == .nest)
        #expect(winner.fromNest == [11, 40, 47, 54, 55])
        #expect(winner.hands[1]?.count == 14)
        #expect(winner.handCounts == [9, 14, 9, 9])
        let waiting = try #require(try room("snapshot-nest-waiting").birdwatch)
        #expect(waiting.fromNest == nil)
        #expect(waiting.putBack == nil)
    }

    @Test func playCarriesPlayable() throws {
        let view = try #require(try room("snapshot-play-follow").birdwatch)
        #expect(view.phase == .play)
        let playable = try #require(view.playable)
        #expect(!playable.isEmpty)
        let hand = try #require(view.hands.values.first)
        #expect(Set(playable).isSubset(of: Set(hand)))
        #expect(try room("snapshot-play-watching").birdwatch?.playable == nil)
    }

    @Test func fivePlayersHideThePartnerUntilTheCardIsPlayed() throws {
        let call = try #require(try room("snapshot-five-partner-call").birdwatch)
        #expect(call.isFive)
        #expect(call.phase == .partner)
        #expect(call.partnerChoices?.contains(56) == true)
        let mine = try #require(try room("snapshot-five-you-are-partner").birdwatch)
        #expect(mine.youArePartner == 3)
        #expect(mine.partner == nil)
        let hidden = try #require(try room("snapshot-five-partner-hidden").birdwatch)
        #expect(hidden.called == 0)
        #expect(hidden.partner == nil)
        #expect(hidden.youArePartner == nil)
        let shown = try #require(try room("snapshot-five-partner-shown").birdwatch)
        #expect(shown.partner == 3)
    }

    @Test func aSeatAHouseCatTookOverKeepsItsPerson() throws {
        let room = try room("snapshot-six-house-cat")
        #expect(room.seats[2].isTakenOver)
        #expect(room.seats[2].person != nil)
        #expect(room.birdwatch?.rules == .friesen)
        #expect(room.birdwatch?.teams == [[0, 3], [1, 4], [2, 5]])
        let over = try self.room("snapshot-over-left")
        #expect(over.status == .over)
        #expect(over.birdwatch?.endReason == .left)
        let allTaken = over.seats.allSatisfy { $0.isTakenOver }
        #expect(allTaken)
        #expect(over.liveTurn == nil)
    }

    @Test func theFinishedGameHasItsHistory() throws {
        let view = try #require(try room("snapshot-over-target").birdwatch)
        #expect(view.status == .over)
        #expect(view.turn == nil)
        #expect(view.winners == [0, 2])
        #expect(view.endReason == .target)
        #expect(view.history == [BirdHandResult(
            hand: 1, bidder: 1, bid: 70, partner: nil, trump: .fish, made: false, taken: [55, 65], change: [55, -70],
            totals: [345, 210])])
        #expect(view.putBack == [11, 40, 47, 54, 55])
    }

    @Test func eventsDecode() throws {
        #expect(try event("event-dealt-own") == .dealt(hand: 2, dealer: 1, handCounts: [9, 9, 9, 9], hands: [0: [4, 6, 9, 17, 18, 30, 33, 41, 56]]))
        #expect(try event("event-dealt-screen") == .dealt(hand: 2, dealer: 1, handCounts: [9, 9, 9, 9], hands: [:]))
        #expect(try event("event-bid") == .bid(seat: 2, amount: 85))
        #expect(try event("event-passed") == .passed(seat: 3))
        #expect(try event("event-bidWon") == .bidWon(seat: 2, amount: 85))
        #expect(try event("event-nest-own") == .nest(seat: 2, cards: [7, 21, 44, 50, 55]))
        #expect(try event("event-nest-other") == .nest(seat: 2, cards: nil))
        #expect(try event("event-putBack-own") == .putBack(seat: 2, count: 5, cards: [5, 7, 19, 32, 46]))
        #expect(try event("event-putBack-other") == .putBack(seat: 2, count: 5, cards: nil))
        #expect(try event("event-trump") == .trump(seat: 2, suit: .feather))
        #expect(try event("event-called") == .called(seat: 2, card: 42))
        #expect(try event("event-turn") == .turn(seat: 2))
        #expect(try event("event-played") == .played(seat: 2, card: 56))
        #expect(try event("event-partner") == .partner(seat: 4))
        #expect(try event("event-trick") == .trick(
            winner: 3, cards: [.init(seat: 1, card: 23), .init(seat: 2, card: 27), .init(seat: 3, card: 4), .init(seat: 0, card: 19)],
            points: 25))
        guard case .handOver(let result, _) = try event("event-handOver") else { Issue.record("no handOver"); return }
        #expect(result.made)
        #expect(result.totals == [145, 210])
        #expect(try event("event-gameOver-target") == .gameOver(winners: [1, 3], scores: [145, 310], reason: .target))
        #expect(try event("event-gameOver-left") == .gameOver(winners: [], scores: [40, 75], reason: .left))
        guard case .event(_, .houseCat(let seat)) = try fixture("event-houseCat") else { Issue.record("no houseCat"); return }
        #expect(seat == 2)
    }

    @Test func newErrorsDecode() throws {
        guard case .error(let code) = try fixture("error-must_follow") else { Issue.record("not an error"); return }
        #expect(code == .mustFollow)
        guard case .error(let low) = try fixture("error-bid_too_low") else { Issue.record("not an error"); return }
        #expect(low == .bidTooLow)
    }

    @Test func everyEventRoundTrips() throws {
        for (name, json) in try Fixtures.birdwatchServerMessages() where name.hasPrefix("event-") {
            guard case .event(_, let event) = try Codec.decode(json) as ServerMessage else { continue }
            let again = try JSONDecoder().decode(RoomEvent.self, from: try JSONEncoder().encode(event))
            #expect(again == event, "\(name)")
        }
    }

    @Test func everySnapshotsViewRoundTrips() throws {
        for (name, json) in try Fixtures.birdwatchServerMessages() {
            guard case .snapshot(_, _, let room) = try Codec.decode(json) as ServerMessage, let view = room.birdwatch else { continue }
            let again = try JSONDecoder().decode(BirdView.self, from: try JSONEncoder().encode(view))
            #expect(again == view, "\(name)")
        }
    }

    // MARK: client to server

    @Test func everyClientMessageEncodesAsTheServerReadsIt() throws {
        let fixtures = try Fixtures.birdwatchClientMessages()
        let messages: [String: ClientMessage] = [
            "setOptions": .setOptions(RoomOptions(rules: .tucker)),
            "swapSeats": .swapSeats(1, 2),
            "act-bid": .actBirdwatch(seat: 1, action: .bid(85)),
            "act-pass": .actBirdwatch(seat: 1, action: .pass),
            "act-nest": .actBirdwatch(seat: 1, action: .nest([5, 7, 19, 32, 46])),
            "act-trump": .actBirdwatch(seat: 1, action: .trump(.bell)),
            "act-partner": .actBirdwatch(seat: 1, action: .partner(56)),
            "act-play": .actBirdwatch(seat: 1, action: .play(13), id: "0f8fad5b-d9cb-469f-a165-70867728950e"),
            "act-forfeit": .actBirdwatch(seat: 1, action: .forfeit),
        ]
        #expect(Set(fixtures.map(\.name)) == Set(messages.keys))
        for (name, json) in fixtures {
            let message = try #require(messages[name])
            let ours = String(decoding: try JSONEncoder().encode(message), as: UTF8.self)
            #expect(try jsonEqual(ours, json), "\(name): \(ours)")
        }
    }

    // MARK: cards

    @Test func cardIDs() {
        #expect(BirdCard(id: 56) == .bird)
        #expect(BirdCard(id: 13) == .suited(.fish, rank: 14))
        #expect(BirdCard(id: 14) == .suited(.mouse, rank: 1))
        #expect(BirdCard(id: 55) == .suited(.bell, rank: 14))
        #expect(BirdCard(id: 57) == nil)
        #expect(BirdCard(id: -1) == nil)
        for id in 0..<57 { #expect(BirdCard(id: id)?.id == id) }
        #expect([4, 9, 13, 0, 56, 6, 1].map { BirdCard(id: $0)!.points } == [5, 10, 10, 15, 20, 0, 0])
        // Every hand is worth 180 with the 1s, 120 without the 1s, 2s, 3s and 4s.
        #expect((0..<57).map { BirdCard(id: $0)!.points }.reduce(0, +) == 180)
        let official = (0..<57).filter { id in BirdCard(id: id).map { $0 == .bird || ($0.rank ?? 0) >= 5 } ?? false }
        #expect(official.count == 41)
        #expect(official.map { BirdCard(id: $0)!.points }.reduce(0, +) == 120)
    }
}
