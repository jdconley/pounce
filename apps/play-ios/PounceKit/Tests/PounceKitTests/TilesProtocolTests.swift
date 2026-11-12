import Foundation
import Testing
@testable import PounceKit

@Suite struct TilesProtocolTests {
    private func fixture(_ name: String) throws -> ServerMessage {
        let json = try #require(try Fixtures.tilesServerMessages().first { $0.name == name }, "no tiles fixture \(name)").json
        return try Codec.decode(json)
    }

    private func room(_ name: String) throws -> RoomView {
        guard case .snapshot(_, _, let room) = try fixture(name) else { throw Fixtures.FixtureError.malformed(name) }
        return room
    }

    private func event(_ name: String) throws -> TilesEvent {
        guard case .event(_, .tiles(let event)) = try fixture(name) else { throw Fixtures.FixtureError.malformed(name) }
        return event
    }

    private func jsonEqual(_ a: String, _ b: String) throws -> Bool {
        let x = try JSONSerialization.jsonObject(with: Data(a.utf8)) as! NSObject
        let y = try JSONSerialization.jsonObject(with: Data(b.utf8)) as! NSObject
        return x.isEqual(y)
    }

    // MARK: server to client

    @Test func decodesEveryTilesFixture() throws {
        let fixtures = try Fixtures.tilesServerMessages()
        #expect(fixtures.count == 26)
        for (name, json) in fixtures {
            #expect(throws: Never.self, "\(name)") { _ = try Codec.decode(json) }
        }
    }

    @Test func aDealtTableHasMyRackUnderAStringKey() throws {
        let room = try room("snapshot-tiles-dealt-two")
        #expect(room.gameId == GameID.tiles)
        #expect(room.isTiles)
        #expect(room.game == nil)
        let view = try #require(room.tiles)
        #expect(view.status == .playing)
        #expect(view.turns == 0)
        #expect(view.table.isEmpty)
        #expect(view.poolCount == 106 - 28)
        #expect(view.rackCounts == [14, 14])
        #expect(Array(view.racks.keys) == [0])
        #expect(view.racks[0]?.count == 14)
        #expect(view.opened == [false, false])
        #expect(view.passed == [false, false])
        #expect(view.forfeited == [false, false])
        #expect(view.winners.isEmpty)
        #expect(view.scores == [0, 0])
        #expect(view.endReason == nil)
    }

    @Test func aPhoneWithTwoSeatsGetsBothRacksAndOneWithNoneGetsNone() throws {
        let both = try #require(try room("snapshot-tiles-two-seats-here").tiles)
        #expect(both.racks.keys.sorted() == [0, 1])
        #expect(both.racks[0]?.count == both.rackCounts[0])
        #expect(both.racks[1]?.count == both.rackCounts[1])
        let none = try #require(try room("snapshot-tiles-no-seat-here").tiles)
        #expect(none.racks.isEmpty)
    }

    @Test func everySnapshotAddsUpToThe106Pieces() throws {
        for (name, json) in try Fixtures.tilesServerMessages() {
            guard case .snapshot(_, _, let room) = try Codec.decode(json), let view = room.tiles else { continue }
            let onRug = view.table.joined().count
            // A forfeited rack is set aside and counted nowhere, and the blocked game's toy box
            // was emptied by hand to get there, so for those only an upper bound holds.
            let total = onRug + view.poolCount + view.rackCounts.reduce(0, +)
            let whole = !view.forfeited.contains(true) && !name.contains("passed") && !name.contains("blocked")
            if whole { #expect(total == 106, "\(name)") } else { #expect(total <= 106, "\(name)") }
            #expect(Set(view.table.joined()).count == onRug, "\(name)")
            #expect(view.table.allSatisfy { TilesRules.readSet($0) != nil }, "\(name)")
            for (seat, rack) in view.racks { #expect(rack.count == view.rackCounts[seat], "\(name)") }
        }
    }

    @Test func finishedGamesCarryTheirReason() throws {
        let out = try #require(try room("snapshot-tiles-over-out").tiles)
        #expect(out.status == .gameOver)
        #expect(out.endReason == .out)
        #expect(out.winners.count == 1)
        #expect(out.rackCounts[out.winners[0]] == 0)
        #expect(out.scores.reduce(0, +) == 0)
        #expect(try room("snapshot-tiles-over-out").status == .over)

        let blocked = try #require(try room("snapshot-tiles-over-blocked").tiles)
        #expect(blocked.endReason == .blocked)
        #expect(blocked.poolCount == 0)

        let forfeit = try #require(try room("snapshot-tiles-over-forfeit").tiles)
        #expect(forfeit.endReason == .forfeit)
        #expect(forfeit.forfeited == [false, true])
        #expect(forfeit.winners == [0])
        #expect(forfeit.scores == [0, 0])
    }

    @Test func forfeitedAndPassedSeatsShow() throws {
        let view = try #require(try room("snapshot-tiles-forfeited").tiles)
        let seat = try #require(view.forfeited.firstIndex(of: true))
        #expect(view.isOut(seat))
        #expect(view.rackCounts[seat] == 0)
        #expect(view.turn != seat)
        let passed = try #require(try room("snapshot-tiles-passed").tiles)
        #expect(passed.passed.filter { $0 }.count == 1)
        #expect(passed.poolCount == 0)
    }

    @Test func aDrawShowsItsPieceOnlyToTheDrawer() throws {
        guard case .drew(let seat, let tile, let poolCount) = try event("event-tiles-drew-own") else {
            Issue.record("not a drew event"); return
        }
        #expect(seat == 0)
        #expect(tile == 105)
        #expect(poolCount == 76)
        guard case .drew(let other, let hidden, _) = try event("event-tiles-drew-other") else {
            Issue.record("not a drew event"); return
        }
        #expect(other == 1)
        #expect(hidden == nil)
    }

    @Test func aPlayCarriesTheWholeRugAndWhatWasPlaced() throws {
        guard case .played(let seat, let table, let placed, let opened) = try event("event-tiles-played-opening") else {
            Issue.record("not a played event"); return
        }
        #expect(seat == 0)
        #expect(opened)
        #expect(table == [[44, 70, 83], [9, 74, 100]])
        #expect(placed == [44, 70, 83, 9, 74, 100])
        guard case .played(_, let later, let added, let again) = try event("event-tiles-played") else {
            Issue.record("not a played event"); return
        }
        #expect(!again)
        #expect(Set(added).isSubset(of: Set(later.joined())))
    }

    @Test func theOtherEventsDecode() throws {
        #expect(try event("event-tiles-turn") == .turn(seat: 1))
        guard case .passed = try event("event-tiles-passed") else { Issue.record("not passed"); return }
        guard case .forfeited = try event("event-tiles-forfeited") else { Issue.record("not forfeited"); return }
        #expect(try event("event-tiles-gameOver-out") == .gameOver(winners: [1], reason: .out, scores: [-18, 18], left: [18, 0]))
        #expect(try event("event-tiles-gameOver-blocked") == .gameOver(winners: [2], reason: .blocked, scores: [-40, -99, 102], left: [40, 99, 37]))
        #expect(try event("event-tiles-gameOver-forfeit") == .gameOver(winners: [0], reason: .forfeit, scores: [0, 0], left: [108, 0]))
    }

    @Test func tilesErrorsKeepTheirCodes() throws {
        #expect(try fixture("error-bad_set") == .error(.badSet))
        #expect(try fixture("error-opening_too_low") == .error(.openingTooLow))
        #expect(try fixture("error-table_touched") == .error(.tableTouched))
        #expect(try fixture("error-pool_empty") == .error(.poolEmpty))
        // Every refusal of a play has an error code of the same name.
        for error in TilesPlayError.allCases {
            #expect(try Codec.decode(#"{"t":"error","code":"\#(error.rawValue)"}"#) == .error(ErrorCode(rawValue: error.rawValue)))
        }
    }

    @Test func viewsAndEventsRoundTrip() throws {
        let encoder = JSONEncoder()
        for (name, json) in try Fixtures.tilesServerMessages() {
            switch try Codec.decode(json) {
            case .snapshot(_, _, let room):
                let again = try JSONDecoder().decode(RoomView.self, from: encoder.encode(room))
                #expect(again == room, "\(name)")
            case .event(_, let event):
                let again = try JSONDecoder().decode(RoomEvent.self, from: encoder.encode(event))
                #expect(again == event, "\(name)")
            default:
                break
            }
        }
    }

    @Test func aTilesEventUnderTheGameKindIsNotATilesEvent() {
        // The two games share event names: `played` is nothing Cat Tower knows, so it is dropped.
        let json = #"{"t":"event","seq":3,"event":{"kind":"game","event":{"kind":"played","seat":0,"table":[],"placed":[],"opened":false}}}"#
        #expect(throws: (any Error).self) { _ = try Codec.decode(json) }
        // And an unknown tiles event kind is dropped too, never misread.
        let unknown = #"{"t":"event","seq":3,"event":{"kind":"tiles","event":{"kind":"shuffled","seat":0}}}"#
        #expect(throws: (any Error).self) { _ = try Codec.decode(unknown) }
    }

    @Test func anEndReasonThisBuildDoesNotKnowReadsAsNone() throws {
        let json = try #require(try Fixtures.tilesServerMessages().first { $0.name == "snapshot-tiles-over-out" }).json
        let changed = json.replacingOccurrences(of: #""endReason":"out""#, with: #""endReason":"timeout""#)
        #expect(changed != json)
        guard case .snapshot(_, _, let room) = try Codec.decode(changed) else { Issue.record("not a snapshot"); return }
        #expect(room.tiles?.status == .gameOver)
        #expect(room.tiles?.endReason == nil)
    }

    // MARK: Cat Tower keeps its shape

    @Test func catTowerSnapshotsHaveNoGameIdAndReadAsCatTower() throws {
        for (name, json) in try Fixtures.serverMessages() {
            guard case .snapshot(_, _, let room) = try Codec.decode(json) else { continue }
            #expect(room.gameId == nil, "\(name)")
            #expect(room.tiles == nil, "\(name)")
            #expect(!room.isTiles, "\(name)")
        }
    }

    @Test func aCatTowerSnapshotThatNamesItsGameStillDecodes() throws {
        let json = try #require(try Fixtures.serverMessages().first { $0.name == "snapshot-playing-with-hand" }).json
        let named = json.replacingOccurrences(of: #""status":"playing""#, with: #""status":"playing","gameId":"cat-tower""#)
        #expect(named != json)
        guard case .snapshot(_, _, let room) = try Codec.decode(named), case .snapshot(_, _, let plain) = try Codec.decode(json) else {
            Issue.record("not a snapshot"); return
        }
        #expect(room.gameId == GameID.catTower)
        #expect(!room.isTiles)
        #expect(room.game == plain.game)
        #expect(room.tiles == nil)
    }

    @Test func aRoomViewWithoutTilesEncodesNoNewKeys() throws {
        let room = RoomView(code: "BCDFG", status: .lobby, youAreHost: true, seats: [])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(room)) as? [String: Any]
        #expect(object?["gameId"] == nil)
        #expect(object?["tiles"] == nil)
    }

    // MARK: client to server

    private func sample(_ name: String) throws -> ClientMessage {
        let nines = [8, 34, 86], row = [9, 10, 11]
        switch name {
        case "act-tiles-draw": return .actTiles(seat: 0, action: .draw)
        case "act-tiles-pass": return .actTiles(seat: 1, action: .pass)
        case "act-tiles-forfeit": return .actTiles(seat: 2, action: .forfeit)
        case "act-tiles-play": return .actTiles(seat: 0, action: .play(table: [nines, row]))
        case "act-tiles-play-id":
            return .actTiles(seat: 0, action: .play(table: [[104, 105, 35]]), id: "0F8C1D2E-3A4B-4C5D-8E6F-7A8B9C0D1E2F")
        default: throw Fixtures.FixtureError.malformed("no sample for tiles client fixture \(name)")
        }
    }

    @Test func encodesEveryTilesClientFixture() throws {
        let fixtures = try Fixtures.tilesClientMessages()
        #expect(fixtures.count == 5)
        for (name, json) in fixtures {
            #expect(try jsonEqual(Codec.encode(sample(name)), json), "\(name)")
        }
    }

    @Test func aTilesActIsTheSameEnvelopeAsACatTowerAct() throws {
        #expect(try Codec.encode(.actTiles(seat: 0, action: .draw)) == #"{"action":{"type":"draw"},"seat":0,"t":"act"}"#)
        #expect(try Codec.encode(.actTiles(seat: 3, action: .play(table: [[0, 1, 2]]), id: "m1"))
            == #"{"action":{"table":[[0,1,2]],"type":"play"},"id":"m1","seat":3,"t":"act"}"#)
        // Cat Tower's draw still names its pile.
        #expect(try Codec.encode(.act(seat: 0, action: .draw(.deck))) == #"{"action":{"from":"deck","type":"draw"},"seat":0,"t":"act"}"#)
    }
}
