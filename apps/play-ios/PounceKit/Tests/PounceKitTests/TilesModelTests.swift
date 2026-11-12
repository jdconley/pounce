import Foundation
import Testing
@testable import PounceKit

@Suite struct RackOrderTests {
    static let rack = [t(7, .fish), t(2, .mouse), t(7, .mouse), yarnA, t(1, .bell), t(7, .bell), t(3, .mouse), t(4, .mouse)]

    private func order() -> RackOrder {
        var order = RackOrder()
        order.sync(Self.rack)
        return order
    }

    @Test func startsInTheServersOrder() {
        #expect(order().tiles == Self.rack)
        #expect(order().sort == nil)
    }

    @Test func sortsByNumberThenBackToFree() {
        var order = order()
        order.toggle(.number)
        #expect(order.sort == .number)
        #expect(order.tiles == [t(1, .bell), t(2, .mouse), t(3, .mouse), t(4, .mouse), t(7, .fish), t(7, .mouse), t(7, .bell), yarnA])
        order.toggle(.number)
        #expect(order.sort == nil)
        #expect(order.tiles == Self.rack)
    }

    @Test func sortsByToyAndSwitchesBetweenTheTwo() {
        var order = order()
        order.toggle(.toy)
        #expect(order.tiles == [t(7, .fish), t(2, .mouse), t(3, .mouse), t(4, .mouse), t(7, .mouse), t(1, .bell), t(7, .bell), yarnA])
        order.toggle(.number)
        #expect(order.sort == .number)
        order.toggle(.toy)
        #expect(order.sort == .toy)
        order.toggle(.toy)
        #expect(order.tiles == Self.rack)
    }

    @Test func aDrawnPieceLandsAtTheRightEndAndJoinsTheSortOnTheNextToggle() {
        var order = order()
        order.toggle(.number)
        order.sync(Self.rack + [t(1, .fish)])
        #expect(order.tiles.last == t(1, .fish))
        #expect(order.sort == .number)
        order.toggle(.toy)
        #expect(order.tiles.first == t(1, .fish))
        // Back in the free order it is at the right end too.
        order.toggle(.toy)
        #expect(order.tiles == Self.rack + [t(1, .fish)])
    }

    @Test func aPiecePlayedLeavesAndTheRestKeepTheirPlaces() {
        var order = order()
        order.sync(Self.rack.filter { $0 != yarnA })
        #expect(order.tiles == Self.rack.filter { $0 != yarnA })
    }

    @Test func draggingReordersAndMakesTheOrderThePlayersOwn() {
        var order = order()
        order.toggle(.number)
        let shown = order.tiles
        order.move([yarnA], toSlot: 0, shown: shown)
        #expect(order.tiles.first == yarnA)
        #expect(order.sort == nil)
        // The free order is now this one: a sort toggled on and off comes back to it.
        let mine = order.tiles
        order.toggle(.toy)
        order.toggle(.toy)
        #expect(order.tiles == mine)
    }

    @Test func severalPiecesMoveTogether() {
        var order = order()
        order.move([t(7, .mouse), t(7, .bell)], toSlot: 1, shown: order.tiles)
        #expect(order.tiles == [t(7, .fish), t(7, .mouse), t(7, .bell), t(2, .mouse), yarnA, t(1, .bell), t(3, .mouse), t(4, .mouse)])
        // Past the end clamps to the end.
        order.move([t(7, .fish)], toSlot: 99, shown: order.tiles)
        #expect(order.tiles.last == t(7, .fish))
        // Pieces it doesn't hold are ignored.
        let before = order
        order.move([t(13, .bell)], toSlot: 0, shown: order.tiles)
        #expect(order == before)
    }

    @Test func piecesOutOnTheRugKeepTheirPlacesWhenTheRestMove() {
        var order = order()
        // The Yarn and the bell 1 are on the rug this turn, so they aren't shown.
        let shown = order.shown(Self.rack.filter { $0 != yarnA && $0 != t(1, .bell) })
        #expect(shown == [t(7, .fish), t(2, .mouse), t(7, .mouse), t(7, .bell), t(3, .mouse), t(4, .mouse)])
        order.move([t(4, .mouse)], toSlot: 0, shown: shown)
        #expect(order.shown(Self.rack) == [t(4, .mouse), t(7, .fish), t(2, .mouse), t(7, .mouse), yarnA, t(1, .bell), t(7, .bell), t(3, .mouse)])
        // Dropped after the last piece shown, not after the ones that are out.
        order.move([t(7, .fish)], toSlot: 99, shown: order.shown(Self.rack.filter { $0 != yarnA && $0 != t(3, .mouse) }))
        #expect(order.tiles.last == t(3, .mouse))
    }

    @Test func shownCoversPiecesTheOrderHasNotSeen() {
        let order = order()
        #expect(order.shown([t(13, .bell), t(7, .fish)]) == [t(7, .fish), t(13, .bell)])
    }

    @Test func readySetsShowOnlyInASortedView() {
        var order = order()
        #expect(order.readySets(in: order.tiles).isEmpty)
        order.toggle(.number)
        // 2, 3, 4 mouse happen to sit together, and 7 fish, 7 mouse, 7 bell are a match. The Yarn
        // after them is not pulled in.
        #expect(order.readySets(in: order.tiles) == [1..<4, 4..<7])
        order.toggle(.toy)
        // 2, 3, 4 mouse sit together: a row. The 7 after them isn't part of it.
        #expect(order.readySets(in: order.tiles) == [1..<4])
    }

    @Test func applySortsWhateverTheTogglesSay() {
        var order = order()
        order.apply(.toy)
        order.apply(.toy)
        #expect(order.sort == .toy)
        #expect(order.tiles.first == t(7, .fish))
    }

    @Test func survivesEncoding() throws {
        var order = order()
        order.toggle(.number)
        var again = try JSONDecoder().decode(RackOrder.self, from: JSONEncoder().encode(order))
        #expect(again == order)
        again.toggle(.number)
        #expect(again.tiles == Self.rack)
    }
}

@Suite struct TilesHintsTests {
    @Test func findsRowsAndMatchesInARack() {
        let rack = [t(3, .fish), t(4, .fish), t(5, .fish), t(9, .fish), t(9, .mouse), t(9, .bell), t(1, .bell), yarnA]
        let runsFirst = TilesHints.findSets(rack, runsFirst: true)
        #expect(runsFirst == [[t(3, .fish), t(4, .fish), t(5, .fish)], [t(9, .fish), t(9, .mouse), t(9, .bell)]])
        #expect(TilesHints.points(runsFirst) == 39)
        #expect(TilesHints.findSets(rack, runsFirst: false).count == 2)
        #expect(TilesHints.findSets([t(1, .fish), t(2, .fish), yarnA], runsFirst: true).isEmpty)
    }

    @Test func theOrderMattersAndTheBetterOneWins() {
        // 7-8-9 fish and three 9s share the fish 9: only one of them can be made.
        let rack = [t(7, .fish), t(8, .fish), t(9, .fish), t(9, .mouse), t(9, .bell)]
        #expect(TilesHints.findSets(rack, runsFirst: true) == [[t(7, .fish), t(8, .fish), t(9, .fish)]])
        #expect(TilesHints.findSets(rack, runsFirst: false) == [[t(9, .fish), t(9, .mouse), t(9, .bell)]])
        #expect(TilesHints.bestSets(rack) == [[t(9, .fish), t(9, .mouse), t(9, .bell)]])
    }

    @Test func twinsMakeTwoSets() {
        let rack = [t(3, .fish), t(4, .fish), t(5, .fish), t(3, .fish, 1), t(4, .fish, 1), t(5, .fish, 1)]
        #expect(TilesHints.findSets(rack, runsFirst: true).count == 2)
        let fours = [t(4, .fish), t(4, .fish, 1), t(4, .mouse), t(4, .mouse, 1), t(4, .feather), t(4, .bell)]
        let groups = TilesHints.findSets(fours, runsFirst: false)
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { TilesRules.readSet($0) != nil })
    }

    @Test func everySetFoundIsASet() {
        var rng = TilesDraftTests.Rng(state: 3)
        for _ in 0..<300 {
            let rack = Array(Array(0..<Tile.count).shuffled(using: &rng).prefix(Int.random(in: 3...30, using: &rng)))
            for runsFirst in [true, false] {
                let sets = TilesHints.findSets(rack, runsFirst: runsFirst)
                #expect(sets.allSatisfy { TilesRules.readSet($0) != nil })
                #expect(Set(sets.joined()).count == sets.joined().count)
                #expect(Set(sets.joined()).isSubset(of: Set(rack)))
            }
        }
    }

    @Test func hintsANewSetThenAPieceThatFits() {
        let table = [[t(3, .fish), t(4, .fish), t(5, .fish)]]
        var draft = TilesDraft(table: table, rack: [t(6, .fish), t(9, .fish), t(9, .mouse), t(9, .bell), t(1, .bell)], opened: true)
        #expect(TilesHints.next(draft) == .newSet([t(9, .fish), t(9, .mouse), t(9, .bell)]))
        draft.move([t(9, .fish), t(9, .mouse), t(9, .bell)], to: .newSet())
        #expect(TilesHints.next(draft) == .fits(tile: t(6, .fish), set: 0))
        draft.move([t(6, .fish)], to: .set(0))
        #expect(TilesHints.next(draft) == nil)
    }

    @Test func beforeOpeningItOnlyHintsOnceThirtyIsInReach() {
        let table = [[t(3, .fish), t(4, .fish), t(5, .fish)]]
        let low = TilesDraft(table: table, rack: [t(6, .fish), t(1, .mouse), t(2, .mouse), t(3, .mouse)], opened: false)
        #expect(TilesHints.next(low) == nil)
        var enough = TilesDraft(
            table: table, rack: [t(6, .fish), t(10, .mouse), t(11, .mouse), t(12, .mouse), t(1, .bell), t(2, .bell), t(3, .bell)], opened: false)
        #expect(TilesHints.next(enough) == .newSet([t(10, .mouse), t(11, .mouse), t(12, .mouse)]))
        enough.move([t(10, .mouse), t(11, .mouse), t(12, .mouse)], to: .newSet())
        #expect(TilesHints.next(enough) == .newSet([t(1, .bell), t(2, .bell), t(3, .bell)]))
        // It never points at a locked set.
        enough.move([t(1, .bell), t(2, .bell), t(3, .bell)], to: .newSet())
        #expect(TilesHints.next(enough) == nil)
    }

    @Test func fitsSaysWhetherAPieceCanJoin() {
        let row = [t(3, .fish), t(4, .fish), t(5, .fish)]
        #expect(TilesHints.fits([t(6, .fish)], in: row))
        #expect(TilesHints.fits([t(2, .fish)], in: row))
        #expect(TilesHints.fits([yarnA], in: row))
        #expect(!TilesHints.fits([t(7, .fish)], in: row))
        #expect(!TilesHints.fits([t(6, .mouse)], in: row))
        #expect(TilesHints.fits([t(6, .fish), t(7, .fish)], in: row))
    }
}

@Suite struct TilesTableModelTests {
    private func model(_ room: RoomView) throws -> TilesTableModel { try #require(TilesTableModel(room: room)) }

    @Test func aCatTowerRoomHasNoTilesModel() {
        #expect(TilesTableModel(room: RoomView(code: "BCDFG", status: .lobby, youAreHost: true, seats: [])) == nil)
    }

    @Test func seatsAndTurn() throws {
        let model = try model(DemoFixtures.tilesMid())
        #expect(model.seatCount == 4)
        #expect(model.mySeats == [0])
        #expect(!model.isMultiSeat)
        #expect(model.isLive)
        #expect(model.isMyTurn)
        #expect(model.currentSeat == 0)
        #expect(model.bottomSeat(revealed: nil) == 0)
        #expect(model.barSeats(bottom: 0) == [1, 2, 3])
        #expect(model.barSeats(bottom: nil) == [0, 1, 2, 3])
        #expect(model.rack(0)?.count == 9)
        #expect(model.rack(1) == nil)
        #expect(model.rackCount(1) == 6)
        #expect(model.rackCount(9) == 0)
        let other = try self.model(DemoFixtures.tilesOther())
        #expect(!other.isMyTurn)
        #expect(other.currentSeat == 2)
        #expect(other.barSeats(bottom: 2) == [3, 0, 1])
    }

    @Test func marksForTheTopBar() throws {
        let model = try model(DemoFixtures.tilesMid())
        #expect(model.marks(0) == .init(bot: false, notOpened: false, passed: false, forfeited: false, onTheMove: true, count: 9))
        #expect(model.marks(3) == .init(bot: true, notOpened: true, passed: false, forfeited: false, onTheMove: false, count: 8))
        let passing = try self.model(DemoFixtures.tilesPass())
        #expect(passing.marks(1).passed)
        #expect(!passing.marks(0).passed)
    }

    @Test func aSharedPhoneShowsNoRackUntilOneIsRevealed() throws {
        let model = try model(DemoFixtures.tilesCurtain())
        #expect(model.mySeats == [0, 2])
        #expect(model.isMultiSeat)
        #expect(model.bottomSeat(revealed: nil) == nil)
        #expect(model.bottomSeat(revealed: 2) == 2)
        #expect(model.bottomSeat(revealed: 1) == nil)
        #expect(model.rack(2)?.count == model.rackCount(2))
    }

    @Test func draftsOnlyForTheSeatOnTheMoveHere() throws {
        let model = try model(DemoFixtures.tilesMid())
        let draft = try #require(model.draft(for: 0))
        #expect(draft.opened)
        #expect(draft.poolHasPieces)
        #expect(draft.base == model.view.table)
        #expect(model.draft(for: 1) == nil)
        #expect(try self.model(DemoFixtures.tilesOther()).draft(for: 0) == nil)
        #expect(try self.model(DemoFixtures.tilesOver()).draft(for: 0) == nil)
        #expect(try #require(self.model(DemoFixtures.tilesEarly()).draft(for: 0)).opened == false)
        #expect(try #require(self.model(DemoFixtures.tilesPass()).draft(for: 0)).turnButton == .pass)
    }

    @Test func aDraftIsKeptWhileTheTurnIsTheSameAndDroppedWhenItMovesOn() throws {
        let model = try model(DemoFixtures.tilesMid())
        var draft = try #require(model.draft(for: 0))
        draft.move([DemoFixtures.tile(7, .fish)], to: .set(0))
        // A snapshot that changed nothing about the turn keeps the work.
        #expect(model.draft(for: 0, keeping: draft) == draft)
        // A saved one comes back the same way.
        #expect(model.draft(for: 0, saved: draft) == draft)
        // The rug changed (someone retired the seat, say): a fresh draft.
        var moved = DemoFixtures.tilesMid()
        moved.tiles?.table.removeLast()
        let fresh = try #require(try self.model(moved).draft(for: 0, keeping: draft, saved: draft))
        #expect(fresh.isUntouched)
        #expect(fresh.base == moved.tiles?.table)
    }

    @Test func forfeit() throws {
        let model = try model(DemoFixtures.tilesMid())
        #expect(model.forfeitSeat(shown: nil) == 0)
        #expect(model.forfeitOutcome(0) == .out)
        let two = try self.model(DemoFixtures.tilesLong())
        #expect(two.forfeitOutcome(0) == .ends(winner: 1))
        let shared = try self.model(DemoFixtures.tilesCurtain())
        #expect(shared.forfeitSeat(shown: 2) == 2)
        #expect(shared.forfeitSeat(shown: nil) == 0)
        #expect(try self.model(DemoFixtures.tilesOver()).forfeitSeat(shown: nil) == nil)
        var out = DemoFixtures.tilesMid()
        out.tiles?.forfeited[0] = true
        #expect(try self.model(out).isOutForMe)
        #expect(!model.isOutForMe)
    }

    @Test func standingsPutWinnersFirstAndForfeitsLast() throws {
        let over = try model(DemoFixtures.tilesOver())
        #expect(over.standings.first == 1)
        #expect(over.standings.count == 4)
        #expect(try self.model(DemoFixtures.tilesMid()).standings.isEmpty)
        var room = DemoFixtures.tilesOver()
        room.tiles?.forfeited[3] = true
        room.tiles?.scores[3] = 0
        #expect(try self.model(room).standings.last == 3)
        // Best score first among the rest.
        let scores = over.view.scores
        #expect(over.standings == over.standings.sorted { scores[$0] > scores[$1] })
    }

    @Test func theGenericTableModelFollowsATilesRoom() {
        // Pass-and-play and the shell read these from `TableModel`, whichever game it is.
        let model = TableModel(room: DemoFixtures.tilesCurtain())
        #expect(model.mySeats == [0, 2])
        #expect(model.isMyTurn)
        #expect(model.currentSeat == 0)
        #expect(model.myActiveSeats == [0, 2])
        var out = DemoFixtures.tilesCurtain()
        out.tiles?.forfeited[2] = true
        #expect(TableModel(room: out).myActiveSeats == [0])
        #expect(!TableModel(room: DemoFixtures.tilesOver()).isMyTurn)
        #expect(DemoFixtures.tilesOther().liveTurn == 2)
        #expect(DemoFixtures.tilesOver().liveTurn == nil)
    }
}

@Suite struct TilesRecapTests {
    @Test func collectsOtherSeatsPlaysAndClearsOnMine() {
        var recap = TilesRecap()
        recap.note(.played(seat: 1, table: [], placed: [1, 2, 3], opened: true), mine: [0])
        recap.note(.drew(seat: 2, tile: nil, poolCount: 40), mine: [0])
        recap.note(.played(seat: 3, table: [], placed: [9], opened: false), mine: [0])
        #expect(recap.steps == [.init(seat: 1, placed: [1, 2, 3]), .init(seat: 3, placed: [9])])
        #expect(recap.owners[9] == .some(3))
        #expect(recap.owners[1] == .some(1))
        recap.note(.played(seat: 0, table: [], placed: [50], opened: false), mine: [0])
        #expect(recap.isEmpty)
    }

    @Test func aColdStartComparesRugs() {
        let recap = TilesRecap.since([[1, 2, 3]], now: [[1, 2, 3, 4], [20, 21, 22]])
        #expect(recap.steps == [.init(seat: nil, placed: [4, 20, 21, 22])])
        #expect(recap.owners[4] == .some(nil))
        #expect(TilesRecap.since([[1, 2, 3]], now: [[3, 2, 1]]).isEmpty)
        var cleared = recap
        cleared.clear()
        #expect(cleared.isEmpty)
    }
}

@Suite struct TilesDeviceStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tiles-store-\(UUID().uuidString)")
    }

    @Test func remembersOrdersDraftsAndTheLastRugAcrossInstances() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TilesDeviceStore(directory: dir)
        #expect(store.memory(code: "BCDFG") == TilesTableMemory())

        var order = RackOrder()
        order.sync([5, 3, 1])
        order.toggle(.number)
        var draft = TilesDraft(table: [[0, 1, 2]], rack: [3, 30, 56], opened: true)
        draft.move([3], to: .set(0))
        store.update(code: "BCDFG") { memory in
            memory.orders[0] = order
            memory.draft = .init(seat: 0, turns: 12, draft: draft)
            memory.lastTable = [[0, 1, 2]]
            memory.easy = true
        }

        let again = TilesDeviceStore(directory: dir).memory(code: "BCDFG")
        #expect(again.orders[0] == order)
        #expect(again.draft(seat: 0, turns: 12) == draft)
        #expect(again.lastTable == [[0, 1, 2]])
        #expect(again.easy == true)
        #expect(again.tricks == nil)
        // The turn moved on, or it is another seat's: no draft.
        #expect(again.draft(seat: 0, turns: 13) == nil)
        #expect(again.draft(seat: 1, turns: 12) == nil)
        #expect(TilesDeviceStore(directory: dir).memory(code: "OTHER") == TilesTableMemory())
    }

    @Test func removingATableForgetsIt() {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TilesDeviceStore(directory: dir)
        store.update(code: "BCDFG") { $0.easy = true }
        store.remove(code: "BCDFG")
        #expect(TilesDeviceStore(directory: dir).memory(code: "BCDFG") == TilesTableMemory())
    }

    @Test func keepsOnlyTheNewestTables() {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TilesDeviceStore(directory: dir)
        for i in 0..<(TilesDeviceStore.limit + 5) { store.update(code: "T\(i)") { $0.easy = true } }
        let again = TilesDeviceStore(directory: dir)
        #expect(again.memory(code: "T0").easy == nil)
        #expect(again.memory(code: "T4").easy == nil)
        #expect(again.memory(code: "T5").easy == true)
        #expect(again.memory(code: "T\(TilesDeviceStore.limit + 4)").easy == true)
    }

    @Test func aBrokenFileReadsAsEmpty() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("tiles.json"))
        let store = TilesDeviceStore(directory: dir)
        #expect(store.memory(code: "BCDFG") == TilesTableMemory())
        store.update(code: "BCDFG") { $0.tricks = true }
        #expect(TilesDeviceStore(directory: dir).memory(code: "BCDFG").tricks == true)
    }
}
