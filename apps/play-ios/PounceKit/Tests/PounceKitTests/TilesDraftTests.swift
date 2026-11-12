import Foundation
import Testing
@testable import PounceKit

/// Shorthand for piece ids in the tile game tests.
func t(_ value: Int, _ suit: TileSuit, _ copy: Int = 0) -> TileID { Tile.id(value, suit, copy: copy) }
let yarnA = Tile.yarnIDs[0]
let yarnB = Tile.yarnIDs[1]

@Suite struct TilesDraftTests {
    // A small table: fish 3-4-5-6, three 9s, and bell 5-6-Yarn-8.
    static let fishRow = [t(3, .fish), t(4, .fish), t(5, .fish), t(6, .fish)]
    static let nines = [t(9, .fish), t(9, .mouse), t(9, .bell)]
    static let bellRow = [t(5, .bell), t(6, .bell), yarnA, t(8, .bell)]
    static let table = [fishRow, nines, bellRow]
    static let rack = [
        t(7, .fish), t(2, .fish), t(9, .feather), t(7, .bell), t(10, .mouse), t(11, .mouse), t(12, .mouse),
        t(1, .feather), yarnB, t(13, .bell), t(5, .fish, 1),
    ]

    private func opened() -> TilesDraft { TilesDraft(table: Self.table, rack: Self.rack, opened: true) }
    private func unopened() -> TilesDraft { TilesDraft(table: Self.table, rack: Self.rack, opened: false) }

    private func ok(_ result: Result<Void, TilesDraft.Refusal>, _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
        if case .failure(let refusal) = result { Issue.record("refused: \(refusal) \(comment?.description ?? "")", sourceLocation: sourceLocation) }
    }

    private func refusal(_ result: Result<Void, TilesDraft.Refusal>) -> TilesDraft.Refusal? {
        if case .failure(let refusal) = result { return refusal }
        return nil
    }

    // MARK: a fresh draft

    @Test func aFreshDraftIsTheSnapshot() {
        let draft = opened()
        #expect(draft.sets.map(\.tiles) == Self.table)
        #expect(draft.sets.map(\.id) == [0, 1, 2])
        #expect(draft.rack == Self.rack)
        #expect(draft.placed.isEmpty)
        #expect(draft.isUntouched)
        #expect(!draft.canUndo)
        #expect(draft.turnButton == .draw)
        #expect(draft.action == .draw)
        #expect(draft.sets.allSatisfy { draft.state(of: $0.id) == .unchanged })
        #expect(draft.openingMeter == nil)
    }

    @Test func anEmptyPoolMakesTheButtonPass() {
        let draft = TilesDraft(table: Self.table, rack: Self.rack, opened: true, poolHasPieces: false)
        #expect(draft.turnButton == .pass)
        #expect(draft.action == .pass)
    }

    // MARK: rack to rug

    @Test func aRackPieceOnARowGoesWhereItsNumberBelongs() {
        var draft = opened()
        ok(draft.move([t(7, .fish)], to: .set(0)))
        #expect(draft.set(0)?.tiles == Self.fishRow + [t(7, .fish)])
        ok(draft.move([t(2, .fish)], to: .set(0)))
        #expect(draft.set(0)?.tiles == [t(2, .fish)] + Self.fishRow + [t(7, .fish)])
        #expect(draft.state(of: 0) == .changed)
        #expect(draft.placed == [t(2, .fish), t(7, .fish)])
        #expect(draft.isPlaced(t(7, .fish)))
        #expect(!draft.isPlaced(t(3, .fish)))
        #expect(!draft.rack.contains(t(7, .fish)))
        #expect(draft.turnButton == .play)
        #expect(draft.action == .play(table: [[t(2, .fish)] + Self.fishRow + [t(7, .fish)], Self.nines, Self.bellRow]))
    }

    @Test func aPieceOnAMatchGoesOnTheEnd() {
        var draft = opened()
        ok(draft.move([t(9, .feather)], to: .set(1)))
        #expect(draft.set(1)?.tiles == Self.nines + [t(9, .feather)])
        #expect(draft.state(of: 1) == .changed)
        #expect(draft.turnButton == .play)
    }

    @Test func aPieceThatFitsNowhereStillLandsAndTheSetShowsBroken() {
        var draft = opened()
        ok(draft.move([t(13, .bell)], to: .set(0)))
        #expect(draft.set(0)?.tiles == Self.fishRow + [t(13, .bell)])
        #expect(draft.state(of: 0) == .broken(.mixedSuits))
        #expect(draft.turnButton == .blocked(.brokenSet(0)))
        #expect(draft.action == nil)
        // A second 5 in the fish row: a row with a number twice.
        var twice = opened()
        ok(twice.move([t(5, .fish, 1)], to: .set(0)))
        #expect(twice.state(of: 0) == .broken(.gap))
        // A fourth 9 that repeats a toy.
        var again = TilesDraft(table: [Self.nines], rack: [t(9, .fish, 1)], opened: true)
        ok(again.move([t(9, .fish, 1)], to: .set(0)))
        #expect(again.state(of: 0) == .broken(.suitTwice))
    }

    @Test func rackPiecesOnEmptyRugMakeANewSetInOrder() {
        var draft = opened()
        ok(draft.move([t(12, .mouse), t(10, .mouse), t(11, .mouse)], to: .newSet()))
        #expect(draft.sets.count == 4)
        #expect(draft.sets.last?.tiles == [t(10, .mouse), t(11, .mouse), t(12, .mouse)])
        #expect(draft.sets.last?.id == 3)
        #expect(draft.state(of: 3) == .changed)
        #expect(draft.turnButton == .play)
        #expect(draft.newPoints == 33)
    }

    @Test func onePieceAloneIsAnUnfinishedSet() {
        var draft = opened()
        ok(draft.move([t(1, .feather)], to: .newSet()))
        #expect(draft.state(of: 3) == .broken(.tooShort))
        #expect(draft.turnButton == .blocked(.brokenSet(3)))
        ok(draft.move([t(13, .bell)], to: .set(3)))
        #expect(draft.state(of: 3) == .broken(.tooShort))
    }

    @Test func aNewSetCanGoBeforeAnother() {
        var draft = opened()
        ok(draft.move([t(1, .feather)], to: .newSet(at: 1)))
        #expect(draft.sets.map(\.id) == [0, 3, 1, 2])
    }

    // MARK: Yarn

    @Test func aYarnFillsTheGapWhenThereIsOne() {
        var draft = TilesDraft(table: [], rack: [t(3, .fish), t(5, .fish), yarnA, t(6, .fish)], opened: true)
        ok(draft.move([t(3, .fish), t(5, .fish), t(6, .fish)], to: .newSet()))
        #expect(draft.state(of: 0) == .broken(.gap))
        ok(draft.move([yarnA], to: .set(0)))
        #expect(draft.set(0)?.tiles == [t(3, .fish), yarnA, t(5, .fish), t(6, .fish)])
        #expect(draft.state(of: 0) == .changed)
    }

    @Test func aYarnWithNoGapTakesTheEndAsked() {
        var draft = opened()
        ok(draft.move([yarnB], to: .set(0, toward: .start)))
        #expect(draft.set(0)?.tiles == [yarnB] + Self.fishRow)
        #expect(TilesRules.readSet(draft.set(0)!.tiles) == .run(suit: .fish, start: 2, end: 6, points: 20))
        // The same Yarn moved to the other end of its own row.
        ok(draft.move([yarnB], to: .set(0, toward: .end)))
        #expect(draft.set(0)?.tiles == Self.fishRow + [yarnB])
        // With no side asked it takes the high end.
        var plain = opened()
        ok(plain.move([yarnB], to: .set(0)))
        #expect(plain.set(0)?.tiles == Self.fishRow + [yarnB])
    }

    @Test func aYarnNeverStandsBelowOneOrAboveThirteen() {
        let low = [t(1, .fish), t(2, .fish), t(3, .fish)]
        #expect(TilesDraft.arrange(low, adding: [yarnA], toward: .start) == low + [yarnA])
        let high = [t(11, .fish), t(12, .fish), t(13, .fish)]
        #expect(TilesDraft.arrange(high, adding: [yarnA], toward: .end) == [yarnA] + high)
        // All thirteen: nowhere to go, so it lands where asked and the set is broken.
        let all = (1...13).map { t($0, .fish) }
        #expect(TilesRules.readSet(TilesDraft.arrange(all, adding: [yarnA], toward: nil)) == nil)
    }

    @Test func aYarnAlreadyAtAnEndStaysThereWhenTheRowGrows() {
        // Yarn, 4, 5 (the Yarn is the 3) plus a 6: the Yarn keeps standing for 3.
        let row = [yarnA, t(4, .fish), t(5, .fish)]
        #expect(TilesDraft.arrange(row, adding: [t(6, .fish)], toward: nil) == row + [t(6, .fish)])
        // Plus a 7 instead: there is a gap now, and the Yarn is the only thing that can fill it.
        #expect(TilesDraft.arrange(row, adding: [t(7, .fish)], toward: nil) == [t(4, .fish), t(5, .fish), yarnA, t(7, .fish)])
    }

    @Test func aNaturalTakesAYarnsPlaceAndTheYarnMovesToTheEnd() {
        var draft = opened()
        ok(draft.move([t(7, .bell)], to: .set(2)))
        #expect(draft.set(2)?.tiles == [t(5, .bell), t(6, .bell), t(7, .bell), t(8, .bell), yarnA])
        #expect(TilesRules.readSet(draft.set(2)!.tiles) == .run(suit: .bell, start: 5, end: 9, points: 35))
        #expect(draft.turnButton == .play)
    }

    @Test func onePieceWithBothYarnReadsAsWhicheverIsWorthMore() {
        var draft = TilesDraft(table: [], rack: [t(10, .mouse), yarnA, yarnB], opened: false)
        ok(draft.move([yarnA, yarnB, t(10, .mouse)], to: .newSet()))
        // 10, Yarn, Yarn: the run 10-11-12 is 33, more than three 10s.
        #expect(draft.set(0)?.tiles == [t(10, .mouse), yarnA, yarnB])
        #expect(draft.newPoints == 33)
        #expect(draft.turnButton == .play)
        // 13 with both Yarn can only be three 13s (39).
        var top = TilesDraft(table: [], rack: [t(13, .mouse), yarnA, yarnB], opened: false)
        ok(top.move([t(13, .mouse), yarnA, yarnB], to: .newSet()))
        #expect(top.newPoints == 39)
    }

    @Test func twoYarnFillAGapOfTwo() {
        let row = TilesDraft.arrange([t(3, .fish), t(6, .fish)], adding: [yarnA, yarnB], toward: nil)
        #expect(row == [t(3, .fish), yarnA, yarnB, t(6, .fish)])
        // One Yarn can't bridge it: it goes on the end and the row stays broken.
        let short = TilesDraft.arrange([t(3, .fish), t(6, .fish)], adding: [yarnA], toward: nil)
        #expect(short == [t(3, .fish), t(6, .fish), yarnA])
        #expect(TilesRules.readSet(short) == nil)
    }

    // MARK: rug to rug (after opening)

    @Test func aTablePieceMovesToAnotherSet() {
        var draft = opened()
        // The 6 off the end of the fish row can't join the 9s validly, but it lands.
        ok(draft.move([t(6, .fish)], to: .set(1)))
        #expect(draft.set(0)?.tiles == [t(3, .fish), t(4, .fish), t(5, .fish)])
        #expect(draft.set(1)?.tiles == Self.nines + [t(6, .fish)])
        #expect(draft.placed.isEmpty)
        #expect(draft.turnButton == .blocked(.brokenSet(1)))
    }

    @Test func rearrangingWithoutPlacingIsNotAPlay() {
        var draft = TilesDraft(
            table: [(3...8).map { t($0, .fish) }], rack: [t(1, .bell)], opened: true)
        ok(draft.split(0, before: 3))
        #expect(draft.sets.map(\.tiles) == [[t(3, .fish), t(4, .fish), t(5, .fish)], [t(6, .fish), t(7, .fish), t(8, .fish)]])
        #expect(draft.sets.map(\.id) == [0, 1])
        #expect(draft.turnButton == .blocked(.nothingPlaced))
        #expect(draft.action == nil)
    }

    @Test func splittingARowAroundATwinMakesTwoRows() {
        var draft = TilesDraft(
            table: [(3...7).map { t($0, .fish) }], rack: [t(5, .fish, 1)], opened: true)
        ok(draft.split(0, before: 3))
        ok(draft.move([t(5, .fish, 1)], to: .set(1)))
        #expect(draft.sets.map(\.tiles) == [
            [t(3, .fish), t(4, .fish), t(5, .fish)], [t(5, .fish, 1), t(6, .fish), t(7, .fish)],
        ])
        #expect(draft.turnButton == .play)
        do { let r = refusal(draft.split(0, before: 0)); #expect(r == .unknown) }
        do { let r = refusal(draft.split(0, before: 3)); #expect(r == .unknown) }
        do { let r = refusal(draft.split(9, before: 1)); #expect(r == .unknown) }
    }

    @Test func joiningMovesAWholeSetOntoAnother() {
        var draft = TilesDraft(
            table: [[t(3, .fish), t(4, .fish), t(5, .fish)], [t(6, .fish), t(7, .fish), t(8, .fish)]],
            rack: [t(9, .fish)], opened: true)
        ok(draft.join(1, onto: 0))
        #expect(draft.sets.map(\.tiles) == [(3...8).map { t($0, .fish) }])
        #expect(draft.sets.map(\.id) == [0])
        do { let r = refusal(draft.join(0, onto: 0)); #expect(r == .unknown) }
        do { let r = refusal(draft.join(5, onto: 0)); #expect(r == .unknown) }
    }

    @Test func aSetLeftEmptyGoesAway() {
        var draft = opened()
        ok(draft.move(Self.nines, to: .set(0)))
        #expect(draft.sets.map(\.id) == [0, 2])
        #expect(draft.set(1) == nil)
    }

    @Test func aSetThatComesBackToItsPiecesGetsItsServerOrderBack() {
        // A match the server holds in an order of its own.
        let match = [t(9, .bell), t(9, .fish), t(9, .mouse)]
        var draft = TilesDraft(table: [match, Self.fishRow], rack: [t(7, .fish)], opened: true)
        ok(draft.move([t(9, .fish)], to: .set(1)))
        #expect(draft.state(of: 0) == .broken(.tooShort))
        ok(draft.move([t(9, .fish)], to: .set(0)))
        // Not the order the pieces were dropped in: the snapshot's, so the set is untouched again.
        #expect(draft.set(0)?.tiles == match)
        #expect(draft.state(of: 0) == .unchanged)
        #expect(draft.isUntouched)
        #expect(draft.turnButton == .draw)
    }

    @Test func splitAndRejoinedIsUntouchedAgain() {
        var draft = TilesDraft(table: [(3...8).map { t($0, .fish) }], rack: [t(1, .bell)], opened: true)
        ok(draft.split(0, before: 2))
        ok(draft.join(0, onto: 1))
        #expect(draft.sets.map(\.tiles) == [(3...8).map { t($0, .fish) }])
        #expect(draft.isUntouched)
        #expect(draft.state(of: draft.sets[0].id) == .unchanged)
    }

    // MARK: back to the rack

    @Test func aPiecePlacedThisTurnGoesBack() {
        var draft = opened()
        ok(draft.move([t(7, .fish)], to: .set(0)))
        ok(draft.takeBack([t(7, .fish)]))
        #expect(draft.rack == Self.rack)
        #expect(draft.isUntouched)
        #expect(draft.turnButton == .draw)
    }

    @Test func aPieceThatWasOnTheRugNeverGoesToTheRack() {
        var draft = opened()
        do { let r = refusal(draft.takeBack([t(3, .fish)])); #expect(r == .tablePiece) }
        // Not even in the same move as one that may.
        ok(draft.move([t(7, .fish)], to: .set(0)))
        let before = draft
        do { let r = refusal(draft.takeBack([t(7, .fish), t(6, .fish)])); #expect(r == .tablePiece) }
        #expect(draft == before)
        // The Yarn that was on the rug stays on the rug.
        do { let r = refusal(draft.takeBack([yarnA])); #expect(r == .tablePiece) }
    }

    @Test func unknownPiecesAndSetsAreRefused() {
        var draft = opened()
        do { let r = refusal(draft.move([t(1, .bell)], to: .newSet())); #expect(r == .unknown) }  // on nobody's rack here
        do { let r = refusal(draft.move([], to: .newSet())); #expect(r == .unknown) }
        do { let r = refusal(draft.move([t(7, .fish)], to: .set(42))); #expect(r == .unknown) }
        do { let r = refusal(draft.move([t(7, .fish)], to: .rack)); #expect(r == .nothing) }
        #expect(!draft.canUndo)
    }

    // MARK: before opening

    @Test func beforeOpeningTheRugIsLocked() {
        var draft = unopened()
        #expect(draft.sets.allSatisfy { draft.isLocked($0.id) })
        do { let r = refusal(draft.move([t(7, .fish)], to: .set(0))); #expect(r == .notOpened) }
        do { let r = refusal(draft.move([t(6, .fish)], to: .newSet())); #expect(r == .notOpened) }
        do { let r = refusal(draft.split(0, before: 2)); #expect(r == .notOpened) }
        do { let r = refusal(draft.join(0, onto: 1)); #expect(r == .notOpened) }
        #expect(draft.isUntouched)
        #expect(!draft.canUndo)
        // After opening nothing is locked.
        #expect(opened().sets.allSatisfy { !opened().isLocked($0.id) })
    }

    @Test func theOpeningMeterCountsOnlyValidNewSets() {
        var draft = unopened()
        #expect(draft.openingMeter?.points == 0)
        #expect(draft.openingMeter?.goal == 30)
        ok(draft.move([t(10, .mouse), t(11, .mouse)], to: .newSet()))
        #expect(draft.openingMeter?.points == 0)  // not a set yet
        #expect(draft.turnButton == .blocked(.brokenSet(3)))
        ok(draft.move([t(12, .mouse)], to: .set(3)))
        #expect(draft.openingMeter?.points == 33)
        #expect(draft.turnButton == .play)
        // New sets are free to change before they are sent.
        #expect(!draft.isLocked(3))
        ok(draft.move([t(12, .mouse)], to: .rack))
        #expect(draft.openingMeter?.points == 0)
    }

    @Test func anOpeningShortOfThirtyIsBlockedWithItsTotal() {
        let rack = [t(1, .feather), t(2, .feather), t(3, .feather), t(4, .mouse), t(4, .feather), t(4, .bell), t(8, .fish)]
        var draft = TilesDraft(table: Self.table, rack: rack, opened: false)
        ok(draft.move([t(1, .feather), t(2, .feather), t(3, .feather)], to: .newSet()))
        #expect(draft.turnButton == .blocked(.openingTooLow(6)))
        ok(draft.move([t(4, .mouse), t(4, .feather), t(4, .bell)], to: .newSet()))
        #expect(draft.turnButton == .blocked(.openingTooLow(18)))
        #expect(draft.action == nil)
    }

    @Test func exactlyThirtyOpens() {
        var draft = TilesDraft(table: Self.table, rack: [yarnB, t(10, .mouse), t(10, .feather)], opened: false)
        ok(draft.move([t(10, .mouse), t(10, .feather), yarnB], to: .newSet()))
        #expect(draft.openingMeter?.points == 30)
        #expect(draft.turnButton == .play)
    }

    // MARK: undo and reset

    @Test func undoStepsBackOneMoveAtATime() {
        var draft = opened()
        ok(draft.move([t(10, .mouse), t(11, .mouse), t(12, .mouse)], to: .newSet()))
        let afterOne = draft.sets
        ok(draft.move([t(7, .fish)], to: .set(0)))
        ok(draft.split(0, before: 2))
        #expect(draft.canUndo)
        do { let r = draft.undo(); #expect(r) }
        #expect(draft.set(0)?.tiles == Self.fishRow + [t(7, .fish)])
        do { let r = draft.undo(); #expect(r) }
        #expect(draft.sets == afterOne)
        // The three pieces went down as one move, so they come back as one.
        do { let r = draft.undo(); #expect(r) }
        #expect(draft.isUntouched)
        #expect(draft.rack == Self.rack)
        do { let r = draft.undo(); #expect(!r) }
    }

    @Test func idsAreNotReusedAfterUndo() {
        var draft = opened()
        ok(draft.move([t(1, .feather)], to: .newSet()))
        #expect(draft.sets.last?.id == 3)
        draft.undo()
        ok(draft.move([t(13, .bell)], to: .newSet()))
        #expect(draft.sets.last?.id == 4)
    }

    @Test func resetReturnsToTheSnapshot() {
        var draft = opened()
        ok(draft.move([t(7, .fish)], to: .set(0)))
        ok(draft.move(Self.nines, to: .set(2)))
        draft.reset()
        #expect(draft.sets.map(\.tiles) == Self.table)
        #expect(draft.sets.map(\.id) == [0, 1, 2])
        #expect(draft.rack == Self.rack)
        #expect(!draft.canUndo)
        #expect(draft.turnButton == .draw)
    }

    // MARK: tidy and the submission

    @Test func untouchedSetsAreSubmittedPieceForPieceInServerOrder() {
        // A match in an order the app would never choose, and a row.
        let match = [t(9, .bell), t(9, .fish), t(9, .mouse)]
        var draft = TilesDraft(table: [match, Self.fishRow], rack: [t(10, .mouse), t(11, .mouse), t(12, .mouse)], opened: false)
        ok(draft.move([t(10, .mouse), t(11, .mouse), t(12, .mouse)], to: .newSet()))
        #expect(draft.submission == [match, Self.fishRow, [t(10, .mouse), t(11, .mouse), t(12, .mouse)]])
        #expect(draft.turnButton == .play)
    }

    @Test func tidyOrdersRowsByToyThenNumberThenMatches() {
        let table = [Self.nines, Self.bellRow, Self.fishRow, [t(2, .mouse), t(2, .feather), t(2, .bell)]]
        var draft = TilesDraft(table: table, rack: [t(1, .fish), t(2, .fish)], opened: true)
        ok(draft.move([t(1, .fish)], to: .newSet()))
        #expect(draft.shownSets.map(\.id) == [0, 1, 2, 3, 4])
        draft.tidy = true
        // Fish row, bell row, then the 2s and the 9s, then the piece that isn't a set yet.
        #expect(draft.shownSets.map(\.id) == [2, 1, 3, 0, 4])
        #expect(draft.submission.first == Self.fishRow)
        #expect(draft.turnButton == .blocked(.brokenSet(4)))
        // Tidy is a view setting: undo doesn't touch it, and it survives reset.
        draft.undo()
        #expect(draft.tidy)
        // Tidied but otherwise untouched is still nothing to send.
        #expect(draft.turnButton == .draw)
    }

    @Test func aTidySubmissionBeforeOpeningStillLeavesTheRugUntouched() {
        var draft = TilesDraft(
            table: [Self.nines, Self.fishRow], rack: [t(10, .mouse), t(11, .mouse), t(12, .mouse)], opened: false)
        draft.tidy = true
        ok(draft.move([t(10, .mouse), t(11, .mouse), t(12, .mouse)], to: .newSet()))
        #expect(draft.submission == [Self.fishRow, [t(10, .mouse), t(11, .mouse), t(12, .mouse)], Self.nines])
        // Listing the rug's sets in another order is allowed before opening (spec §4.7).
        #expect(draft.turnButton == .play)
    }

    @Test func aRefusalPointsAtItsSets() {
        var draft = opened()
        ok(draft.move([t(13, .bell)], to: .set(0)))
        ok(draft.move([t(9, .feather)], to: .set(1)))
        #expect(draft.sets(refusedBy: .badSet) == [0])
        #expect(draft.sets(refusedBy: .tableTouched) == [0, 1])
        #expect(draft.sets(refusedBy: .openingTooLow).isEmpty)
    }

    // MARK: keeping a draft

    @Test func aDraftMatchesOnlyTheTurnItWasMadeFor() {
        let draft = opened()
        #expect(draft.matches(table: Self.table, rack: Self.rack, opened: true))
        #expect(draft.matches(table: Self.table, rack: Self.rack.reversed(), opened: true))
        #expect(!draft.matches(table: Self.table, rack: Self.rack, opened: false))
        #expect(!draft.matches(table: Self.table, rack: Self.rack + [t(1, .bell)], opened: true))
        #expect(!draft.matches(table: Self.table.reversed(), rack: Self.rack, opened: true))
    }

    @Test func aDraftSurvivesEncoding() throws {
        var draft = opened()
        ok(draft.move([t(7, .fish)], to: .set(0)))
        ok(draft.move([t(10, .mouse), t(11, .mouse)], to: .newSet()))
        draft.tidy = true
        var again = try JSONDecoder().decode(TilesDraft.self, from: JSONEncoder().encode(draft))
        #expect(again == draft)
        // Undo history comes back too.
        do { let r = again.undo(); #expect(r) }
        do { let r = again.undo(); #expect(r) }
        #expect(again.isUntouched)
    }

    // MARK: properties

    /// A deterministic generator for the property tests.
    struct Rng: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// A random legal position: some valid sets on the rug, a rack from what is left.
    static func position(_ rng: inout Rng) -> (table: [[TileID]], rack: [TileID]) {
        var free = Set(0..<Tile.count)
        var table: [[TileID]] = []
        for _ in 0..<Int.random(in: 0...9, using: &rng) {
            var set: [TileID] = []
            if Bool.random(using: &rng) {
                let suit = TileSuit.allCases.randomElement(using: &rng)!
                let length = Int.random(in: 3...6, using: &rng)
                let start = Int.random(in: 1...(14 - length), using: &rng)
                set = (start..<(start + length)).map { Tile.id($0, suit, copy: Int.random(in: 0...1, using: &rng)) }
            } else {
                let value = Int.random(in: 1...13, using: &rng)
                let suits = TileSuit.allCases.shuffled(using: &rng).prefix(Int.random(in: 3...4, using: &rng))
                set = suits.map { Tile.id(value, $0, copy: Int.random(in: 0...1, using: &rng)) }
            }
            if Int.random(in: 0..<6, using: &rng) == 0, let yarn = Tile.yarnIDs.first(where: free.contains) {
                set[Int.random(in: 0..<set.count, using: &rng)] = yarn
            }
            guard set.allSatisfy(free.contains), Set(set).count == set.count, TilesRules.readSet(set) != nil else { continue }
            table.append(set)
            free.subtract(set)
        }
        let rack = Array(free.shuffled(using: &rng).prefix(Int.random(in: 1...18, using: &rng)))
        return (table, rack)
    }

    /// One random operation; refusals are fine.
    static func step(_ draft: inout TilesDraft, _ rng: inout Rng) {
        let everything = draft.rack + draft.sets.flatMap(\.tiles)
        let ids = draft.sets.map(\.id)
        func pieces(_ rng: inout Rng) -> [TileID] {
            // Mostly rack pieces, and mostly ones that could belong together.
            let from = Int.random(in: 0..<4, using: &rng) == 0 ? everything : (draft.rack.isEmpty ? everything : draft.rack)
            guard let first = from.randomElement(using: &rng) else { return [] }
            var picked = [first]
            if Bool.random(using: &rng) {
                let friends = from.filter { other in
                    other != first && (Tile.value(other) == Tile.value(first) || Tile.suit(other) == Tile.suit(first) || Tile.isYarn(other))
                }
                picked += friends.shuffled(using: &rng).prefix(Int.random(in: 1...3, using: &rng))
            }
            return picked
        }
        // Walks that only ever break things never reach a play: when the draft is blocked, half the
        // time the next step is one of the two a player would take to fix it.
        var roll = Int.random(in: 0..<15, using: &rng)
        if case .blocked = draft.turnButton, Bool.random(using: &rng) { roll = Int.random(in: 12...14, using: &rng) }
        switch roll {
        case 0...3:
            draft.move(pieces(&rng), to: .newSet(at: Bool.random(using: &rng) ? nil : Int.random(in: 0...max(ids.count, 1), using: &rng)))
        case 4...7:
            if let id = ids.randomElement(using: &rng) {
                let side: TilesDraft.Side? = [nil, .start, .end].randomElement(using: &rng)!
                draft.move(pieces(&rng), to: .set(id, toward: side))
            }
        case 8:
            draft.move(pieces(&rng), to: .rack)
        case 9:
            if let set = draft.sets.randomElement(using: &rng), set.tiles.count > 1 {
                draft.split(set.id, before: Int.random(in: 1..<set.tiles.count, using: &rng))
            }
        case 10:
            if ids.count > 1 { draft.join(ids.randomElement(using: &rng)!, onto: ids.randomElement(using: &rng)!) }
        case 11:
            if Int.random(in: 0..<3, using: &rng) == 0 { draft.tidy.toggle() } else { draft.undo() }
        case 12, 13:
            // What a player aiming at a play does: a set from the rack, or a piece where it fits.
            switch TilesHints.next(draft) {
            case .newSet(let tiles): draft.move(tiles, to: .newSet())
            case .fits(let tile, let set): draft.move([tile], to: .set(set))
            case nil: break
            }
        default:
            // Tidying up: pieces placed in sets that aren't sets go back.
            let stray = draft.sets.filter { TilesRules.readSet($0.tiles) == nil }.flatMap(\.tiles).filter(draft.isPlaced)
            if case .failure = draft.takeBack(stray) { draft.undo() }
        }
    }

    /// What must hold for any draft, whatever was done to it.
    static func checkInvariants(_ draft: TilesDraft, _ label: String) {
        let onRug = draft.sets.flatMap(\.tiles)
        let was = Set(draft.base.joined())
        // Nothing invented, nothing lost, nothing twice.
        #expect(Set(onRug).count == onRug.count, "\(label): a piece twice")
        #expect(Set(onRug + draft.rack) == was.union(draft.baseRack), "\(label): pieces changed")
        #expect(onRug.count + draft.rack.count == was.count + draft.baseRack.count, "\(label): count changed")
        // Every piece that was on the rug is still on it; only rack pieces are placed.
        #expect(was.isSubset(of: Set(onRug)), "\(label): a rug piece left the rug")
        #expect(Set(draft.placed).isSubset(of: Set(draft.baseRack)), "\(label): placed a piece from nowhere")
        #expect(Set(draft.placed).isDisjoint(with: Set(draft.rack)), "\(label): a piece in two places")
        // No empty sets, and ids are unique.
        #expect(draft.sets.allSatisfy { !$0.tiles.isEmpty }, "\(label): an empty set")
        #expect(Set(draft.sets.map(\.id)).count == draft.sets.count, "\(label): an id twice")
        // Before opening, every set that was on the rug is still there piece for piece.
        if !draft.opened {
            let now = Set(draft.sets.map(\.tiles))
            #expect(draft.base.allSatisfy(now.contains), "\(label): the rug was touched before opening")
        }
        // The shown order is the same sets.
        #expect(draft.shownSets.map(\.id).sorted() == draft.sets.map(\.id).sorted(), "\(label): tidy lost a set")
        // The button says Play exactly when the rules take the submission.
        let verdict = TilesRules.checkPlay(before: draft.base, rack: draft.baseRack, opened: draft.opened, submitted: draft.submission)
        switch draft.turnButton {
        case .play:
            guard case .success(let play) = verdict else {
                Issue.record("\(label): the draft says Play and the rules say \(verdict)")
                return
            }
            #expect(Set(play.placed) == Set(draft.placed), "\(label)")
            #expect(draft.action == .play(table: draft.submission), "\(label)")
            if !draft.opened { #expect(draft.newPoints >= 30 && play.points == draft.newPoints, "\(label)") }
            #expect(draft.sets.allSatisfy { draft.state(of: $0.id) != .broken(.tooShort) }, "\(label)")
        case .draw, .pass:
            #expect(draft.isUntouched, "\(label)")
            #expect(draft.placed.isEmpty, "\(label)")
        case .blocked(let block):
            #expect(draft.action == nil, "\(label)")
            if case .success = verdict { Issue.record("\(label): the rules take a draft the button blocks") }
            switch block {
            case .brokenSet(let id): #expect(TilesRules.readSet(draft.set(id)?.tiles ?? []) == nil, "\(label)")
            case .nothingPlaced: #expect(draft.placed.isEmpty, "\(label)")
            case .openingTooLow(let points): #expect(points < 30 && !draft.opened, "\(label)")
            case .refused(let error): Issue.record("\(label): the draft reached \(error), which its own rules should prevent")
            }
        }
        // Set states agree with the rules.
        for set in draft.sets {
            switch draft.state(of: set.id) {
            case .unchanged: #expect(draft.base.contains(set.tiles), "\(label)")
            case .changed: #expect(TilesRules.readSet(set.tiles) != nil && !draft.base.contains(set.tiles), "\(label)")
            case .broken: #expect(TilesRules.readSet(set.tiles) == nil, "\(label)")
            }
        }
    }

    @Test(arguments: [true, false])
    func anyDraftTheModelCallsPlayableIsAcceptedByTheRules(opened: Bool) {
        var rng = Rng(state: opened ? 0xC0FFEE : 0xBEEF)
        var plays = 0
        for game in 0..<300 {
            let (table, rack) = Self.position(&rng)
            var draft = TilesDraft(table: table, rack: rack, opened: opened, poolHasPieces: game % 5 != 0)
            Self.checkInvariants(draft, "game \(game) start")
            for move in 0..<40 {
                Self.step(&draft, &rng)
                Self.checkInvariants(draft, "game \(game) move \(move) opened \(opened)")
                if draft.turnButton == .play { plays += 1 }
            }
            // Undo all the way is the snapshot again.
            while draft.undo() {}
            #expect(draft.isUntouched, "game \(game): undo did not reach the start")
            #expect(draft.rack == rack, "game \(game)")
        }
        // The walk has to reach playable drafts for the property to mean anything.
        print("[tiles property] opened \(opened): \(plays) playable drafts")
        #expect(plays > 100, "only \(plays) playable drafts were reached")
    }

    @Test func aPlayableDraftIsTakenByTheLocalEngineToo() throws {
        var rng = Rng(state: 42)
        var taken = 0
        for seed in 0..<40 {
            var game = TilesLocalGame(seats: 2 + seed % 3, seed: UInt64(seed))
            for _ in 0..<120 where game.status == .playing {
                let seat = game.turn
                var draft = TilesDraft(table: game.table, rack: game.racks[seat], opened: game.opened[seat], poolHasPieces: !game.pool.isEmpty)
                for _ in 0..<12 { Self.step(&draft, &rng) }
                // The House Cat's sets on top of whatever the walk left, so plays do happen.
                for set in TilesHints.bestSets(draft.rack) { draft.move(set, to: .newSet()) }
                let action = draft.action ?? (game.pool.isEmpty ? .pass : .draw)
                if case .play = action { taken += 1 }
                let result = game.apply(seat: seat, action)
                if case .failure(let refused) = result {
                    Issue.record("seed \(seed): the engine refused \(action) with \(refused.code.rawValue)")
                    break
                }
            }
        }
        print("[tiles property] engine took \(taken) plays")
        #expect(taken > 50)
    }

    @Test func arrangeNeverLosesOrInventsAPiece() {
        var rng = Rng(state: 7)
        for _ in 0..<2000 {
            let pool = Array(0..<Tile.count).shuffled(using: &rng)
            let existing = Array(pool.prefix(Int.random(in: 0...6, using: &rng)))
            let adding = Array(pool.dropFirst(6).prefix(Int.random(in: 1...4, using: &rng)))
            let side: TilesDraft.Side? = [nil, .start, .end].randomElement(using: &rng)!
            let out = TilesDraft.arrange(existing, adding: adding, toward: side)
            #expect(out.sorted() == (existing + adding).sorted())
        }
    }

    @Test func arrangeFindsTheSetWheneverThePiecesAreARowOrAMatch() {
        var rng = Rng(state: 11)
        for _ in 0..<400 {
            let (table, _) = Self.position(&rng)
            for set in table {
                // Dropped in any order, onto nothing or onto a part of itself, it comes out a set.
                let mixed = set.shuffled(using: &rng)
                #expect(TilesRules.readSet(TilesDraft.arrange([], adding: mixed, toward: nil)) != nil, "\(set) as \(mixed)")
                let cut = Int.random(in: 1..<set.count, using: &rng)
                let grown = TilesDraft.arrange(Array(set[..<cut]), adding: Array(set[cut...]).shuffled(using: &rng), toward: nil)
                #expect(TilesRules.readSet(grown) != nil, "\(set) grown from \(cut)")
            }
        }
    }
}
