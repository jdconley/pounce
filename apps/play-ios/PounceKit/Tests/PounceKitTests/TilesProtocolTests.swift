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
        #expect(fixtures.count == 35)
        for (name, json) in fixtures {
            #expect(throws: Never.self, "\(name)") { _ = try Codec.decode(json) }
        }
    }

    @Test func aTilesLobbyNamesItsGameAndHasNoViewYet() throws {
        let room = try room("snapshot-lobby")
        #expect(room.status == .lobby)
        #expect(room.gameId == GameID.tiles)
        #expect(room.isTiles)
        #expect(room.game == nil)
        #expect(room.tiles == nil)
        // A tile game lobby has four seats.
        #expect(room.seats.count == 4)
        #expect(TilesTableModel(room: room) == nil)
    }

    @Test func aDealtTableHasMyRackUnderAStringKey() throws {
        let room = try room("snapshot-playing-with-rack")
        #expect(room.gameId == GameID.tiles)
        #expect(room.game == nil)
        #expect(room.retire == RetireView(seat: 1, wait: 259_200_000))
        let view = try #require(room.tiles)
        #expect(view.status == .playing)
        #expect(view.turn == 1)
        #expect(view.turns == 0)
        #expect(view.table.isEmpty)
        #expect(view.poolCount == 106 - 42)
        #expect(view.rackCounts == [14, 14, 14])
        #expect(Array(view.racks.keys) == [0])
        #expect(view.racks[0] == [82, 45, 87, 23, 17, 29, 99, 50, 10, 61, 39, 68, 19, 44])
        #expect(view.opened == [false, false, false])
        #expect(view.passed == [false, false, false])
        #expect(view.forfeited == [false, false, false])
        #expect(view.winners.isEmpty)
        #expect(view.scores == [0, 0, 0])
        #expect(view.endReason == nil)
        #expect(room.liveTurn == 1)
    }

    @Test func aPhoneWithNoSeatGetsNoRack() throws {
        let view = try #require(try room("snapshot-playing-no-rack").tiles)
        #expect(view.racks.isEmpty)
        #expect(view.rackCounts == [14, 14, 14])
    }

    @Test func everySnapshotsRugIsRowsAndMatchesAndEveryRackMatchesItsCount() throws {
        for (name, json) in try Fixtures.tilesServerMessages() {
            guard case .snapshot(_, _, let room) = try Codec.decode(json), let view = room.tiles else { continue }
            let onRug = Array(view.table.joined())
            #expect(Set(onRug).count == onRug.count, "\(name)")
            #expect(view.table.allSatisfy { TilesRules.readSet($0) != nil }, "\(name)")
            for (seat, rack) in view.racks {
                #expect(rack.count == view.rackCounts[seat], "\(name)")
                #expect(room.seats[seat].yours, "\(name)")
                #expect(Set(rack).isDisjoint(with: Set(onRug)), "\(name)")
            }
            #expect(view.rackCounts.count == room.seats.count, "\(name)")
        }
    }

    @Test func openedAndRearrangedTables() throws {
        let opened = try #require(try room("snapshot-playing-opened").tiles)
        #expect(opened.table == [[8, 9, 10]])
        #expect(opened.opened == [true, false])
        #expect(opened.rackCounts == [11, 14])
        #expect(opened.turns == 1)
        let rearranged = try #require(try room("snapshot-playing-rearranged").tiles)
        #expect(rearranged.table == [[8, 9, 10, 11], [3, 42, 55]])
        #expect(rearranged.opened == [true, true])
        #expect(rearranged.racks[0]?.count == 11)
    }

    @Test func finishedGamesCarryTheirReason() throws {
        let over = try room("snapshot-over-out")
        #expect(over.status == .over)
        #expect(over.liveTurn == nil)
        let out = try #require(over.tiles)
        #expect(out.status == .gameOver)
        #expect(out.endReason == .out)
        #expect(out.winners == [1])
        #expect(out.rackCounts[1] == 0)
        #expect(out.scores == [-95, 95])
        let blocked = try #require(try room("snapshot-over-blocked").tiles)
        #expect(blocked.endReason == .blocked)
        #expect(blocked.poolCount == 0)
        #expect(blocked.passed == [true, true])
    }

    @Test func forfeitedAndPassedSeatsShow() throws {
        let view = try #require(try room("snapshot-playing-forfeited").tiles)
        #expect(view.forfeited == [false, true, false])
        #expect(view.isOut(1))
        #expect(view.rackCounts[1] == 0)
        #expect(view.turn == 2)
        let passed = try #require(try room("snapshot-playing-passed").tiles)
        #expect(passed.passed == [true, false])
        #expect(passed.hasPassed(0))
        #expect(passed.poolCount == 0)
    }

    @Test func aDrawShowsItsPieceOnlyToTheDrawer() throws {
        #expect(try event("event-drew-own") == .drew(seat: 1, tile: 17, poolCount: 77))
        #expect(try event("event-drew-other") == .drew(seat: 0, tile: nil, poolCount: 76))
    }

    @Test func aPlayCarriesTheWholeRugAndWhatWasPlaced() throws {
        #expect(try event("event-played-opening") == .played(seat: 0, table: [[8, 9, 10]], placed: [8, 9, 10], opened: true))
        #expect(try event("event-played") == .played(seat: 1, table: [[8, 9, 10, 11], [104, 32, 58]], placed: [11], opened: false))
    }

    @Test func theOtherEventsDecode() throws {
        #expect(try event("event-turn") == .turn(seat: 0))
        #expect(try event("event-passed") == .passed(seat: 1))
        #expect(try event("event-forfeited") == .forfeited(seat: 1))
        #expect(try event("event-gameOver-out") == .gameOver(winners: [1], reason: .out, scores: [-35, 60, -25], left: [35, 0, 25]))
        // A shared win: each winner collects in full.
        #expect(try event("event-gameOver-blocked") == .gameOver(winners: [0, 1], reason: .blocked, scores: [2, 2, -9], left: [7, 7, 9]))
        #expect(try event("event-gameOver-forfeit") == .gameOver(winners: [0], reason: .forfeit, scores: [0, 0], left: [41, 0]))
        // Presence travels as it always has, in a tile game room too.
        #expect(try fixture("event-presence") == .event(seq: 14, event: .presence(seat: 1, presence: .away)))
    }

    @Test func tilesErrorsKeepTheirCodes() throws {
        let codes: [ErrorCode] = [
            .badAction, .poolEmpty, .poolNotEmpty, .badPiece, .duplicatePiece, .missingPiece, .notYourPiece,
            .nothingPlayed, .badSet, .tableTouched, .openingTooLow, .notYourTurn, .gameOver, .forfeited,
            // The room's own: Play again at a table whose game the server no longer deals.
            .gameOff,
        ]
        let fixtures = try Fixtures.tilesServerMessages().filter { $0.name.hasPrefix("error-") }
        #expect(fixtures.count == codes.count)
        for code in codes {
            #expect(try fixture("error-\(code.rawValue)") == .error(code))
        }
        // Every refusal of a play has an error code of the same name.
        for error in TilesPlayError.allCases {
            #expect(codes.contains(ErrorCode(rawValue: error.rawValue)))
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
        let json = try #require(try Fixtures.tilesServerMessages().first { $0.name == "snapshot-over-out" }).json
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
        switch name {
        case "act-draw": return .actTiles(seat: 1, action: .draw)
        case "act-pass": return .actTiles(seat: 1, action: .pass)
        case "act-forfeit": return .actTiles(seat: 1, action: .forfeit)
        case "act-play-opening": return .actTiles(seat: 0, action: .play(table: [[8, 9, 10]]))
        case "act-play-id":
            return .actTiles(
                seat: 1, action: .play(table: [[8, 9, 10, 11], [3, 42, 55]]), id: "0f8fad5b-d9cb-469f-a165-70867728950e")
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

/// The live table at a tile game table (tile game spec §9.2): `phase` stays (the server sends
/// 1), each seat adds `progress` and the state says what it counts.
@Suite struct TilesLiveTableTests {
    @Test func aTileGameTablesStateCarriesPiecesLeft() throws {
        let json = #"{"table":"Couch Cats","seats":[{"cat":1,"phase":1,"name":"JD","bot":false,"me":true,"progress":9},{"cat":3,"phase":1,"bot":true,"me":false,"progress":14}],"turn":0,"mine":true,"progressKind":"pieces"}"#
        let state = try JSONDecoder().decode(LiveTableState.self, from: Data(json.utf8))
        #expect(state.countsPieces)
        #expect(state.seats.map(\.progress) == [9, 14])
        #expect(state.seats.map(\.phase) == [1, 1])
        let again = try JSONDecoder().decode(LiveTableState.self, from: JSONEncoder().encode(state))
        #expect(again == state)
    }

    @Test func aCatTowerTablesStateHasNoProgressAndEncodesNone() throws {
        let json = #"{"table":"Couch Cats","seats":[{"cat":1,"phase":3,"name":"JD","bot":false,"me":true}],"turn":0,"mine":true}"#
        let state = try JSONDecoder().decode(LiveTableState.self, from: Data(json.utf8))
        #expect(!state.countsPieces)
        #expect(state.progressKind == nil)
        #expect(state.seats[0].progress == nil)
        #expect(state.seats[0].phase == 3)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        #expect(object?["progressKind"] == nil)
        #expect(((object?["seats"] as? [[String: Any]])?.first?["progress"]) == nil)
    }
}
