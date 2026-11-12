#if DEBUG
import Foundation
import Testing
@testable import PounceKit

@Suite struct DemoTilesTests {
    static let rooms: [(name: String, room: RoomView)] = [
        ("early", DemoFixtures.tilesEarly()), ("early opened", DemoFixtures.tilesEarly(opened: true)),
        ("mid", DemoFixtures.tilesMid()), ("other", DemoFixtures.tilesOther()), ("late", DemoFixtures.tilesLate()),
        ("long", DemoFixtures.tilesLong()), ("pass", DemoFixtures.tilesPass()), ("curtain", DemoFixtures.tilesCurtain()),
        ("over", DemoFixtures.tilesOver()),
    ]

    @Test(arguments: rooms.indices)
    func everyFixtureIsATableTheServerCouldSend(_ i: Int) throws {
        let (name, room) = Self.rooms[i]
        let view = try #require(room.tiles, "\(name)")
        #expect(room.isTiles, "\(name)")
        #expect(room.game == nil, "\(name)")
        #expect(room.seats.count == view.seatCount, "\(name)")
        for count in [view.opened.count, view.passed.count, view.forfeited.count, view.scores.count] {
            #expect(count == view.seatCount, "\(name)")
        }
        // Every visible id is a real piece and appears once.
        let visible = Array(view.table.joined()) + view.racks.values.joined()
        #expect(visible.allSatisfy(Tile.isTileID), "\(name)")
        #expect(Set(visible).count == visible.count, "\(name)")
        // Every set on the rug is a row or a match.
        for set in view.table { #expect(TilesRules.readSet(set) != nil, "\(name): \(set)") }
        // Racks match their counts, and the 106 pieces are all somewhere.
        for (seat, rack) in view.racks {
            #expect(view.rackCounts[seat] == rack.count, "\(name)")
            #expect(room.seats[seat].yours, "\(name)")
        }
        #expect(view.poolCount >= 0, "\(name)")
        #expect(view.table.joined().count + view.rackCounts.reduce(0, +) + view.poolCount == Tile.count, "\(name)")
        // A seat with pieces on the rug to its name has opened; nobody opened onto an empty rug.
        if view.table.isEmpty { #expect(!view.opened.contains(true), "\(name)") }
    }

    @Test func earlyIsBeforeMyOpeningWithAnOpeningInHand() throws {
        let model = try #require(TilesTableModel(room: DemoFixtures.tilesEarly()))
        var draft = try #require(model.draft(for: 0))
        #expect(!draft.opened)
        #expect(model.rack(0)?.count == 14)
        #expect(draft.sets.allSatisfy { draft.isLocked($0.id) })
        draft.move([DemoFixtures.tile(10, .fish), DemoFixtures.tile(11, .fish), DemoFixtures.tile(12, .fish)], to: .newSet())
        #expect(draft.openingMeter?.points == 33)
        #expect(draft.turnButton == .play)
        // The same table after that opening.
        let after = try #require(TilesTableModel(room: DemoFixtures.tilesEarly(opened: true)))
        #expect(after.view.hasOpened(0))
        #expect(after.rack(0)?.count == 11)
        #expect(after.view.table.count == 3)
    }

    @Test func midHasPiecesThatFitAndAYarnToSwap() throws {
        let model = try #require(TilesTableModel(room: DemoFixtures.tilesMid()))
        var draft = try #require(model.draft(for: 0))
        #expect(model.seatCount == 4)
        #expect(draft.opened)
        draft.move([DemoFixtures.tile(7, .fish)], to: .set(0))
        draft.move([DemoFixtures.tile(13, .mouse)], to: .set(2))
        draft.move([DemoFixtures.tile(11, .feather)], to: .set(8))
        draft.move([DemoFixtures.tile(7, .bell)], to: .set(5))
        #expect(draft.turnButton == .play)
        #expect(draft.placed.count == 4)
    }

    @Test func lateIsTwentyFiveSetsAndABigRack() throws {
        let view = try #require(DemoFixtures.tilesLate().tiles)
        #expect(view.table.count == 25)
        #expect(view.table.joined().count == 80)
        #expect((view.racks[0]?.count ?? 0) >= 20)
        #expect(view.racks[0]?.contains(Tile.yarnIDs[1]) == true)
        #expect(view.table.contains { $0.contains(Tile.yarnIDs[0]) })
        // Rows and matches are mixed down the rug.
        #expect(TilesRules.readSet(view.table[0])?.isRun == true)
        #expect(TilesRules.readSet(view.table[1])?.isRun == false)
    }

    @Test func longHoldsARowOfAllThirteen() throws {
        let view = try #require(DemoFixtures.tilesLong().tiles)
        #expect(view.table.map(\.count).max() == 13)
    }

    @Test func passHasAnEmptyToyBox() throws {
        let model = try #require(TilesTableModel(room: DemoFixtures.tilesPass()))
        #expect(model.view.poolCount == 0)
        #expect(model.seatCount == 2)
        #expect(model.draft(for: 0)?.turnButton == .pass)
    }

    @Test func overIsScoredAsTheEngineScores() throws {
        let view = try #require(DemoFixtures.tilesOver().tiles)
        #expect(view.status == .gameOver)
        #expect(view.winners == [1])
        #expect(view.endReason == .out)
        #expect(view.scores.reduce(0, +) == 0)
        #expect(view.scores[1] > 0)
        #expect(view.scores[0] == -Tile.rackTotal(view.racks[0] ?? []))
        guard case .gameOver(let winners, let reason, let scores, let left)? = DemoFixtures.tilesOverEvents().first else {
            Issue.record("no game over event"); return
        }
        #expect(winners == view.winners)
        #expect(reason == .out)
        #expect(scores == view.scores)
        #expect(left[1] == 0)
    }
}

@Suite struct TilesLocalGameTests {
    /// Every piece is in exactly one place: a rack, the toy box or the rug (forfeited racks are
    /// set aside, so those games only keep the rest).
    private func conserved(_ game: TilesLocalGame) -> Bool {
        let all = game.racks.joined() + game.pool + game.table.joined()
        return Set(all).count == all.count && (game.forfeited.contains(true) ? all.count <= Tile.count : all.count == Tile.count)
    }

    @Test func aNewGameDealsFourteenEach() {
        for seats in 2...4 {
            let game = TilesLocalGame(seats: seats, seed: 9)
            #expect(game.racks.count == seats)
            #expect(game.racks.allSatisfy { $0.count == 14 })
            #expect(game.pool.count == 106 - 14 * seats)
            #expect(game.table.isEmpty)
            #expect((0..<seats).contains(game.turn))
            #expect(conserved(game))
        }
        #expect(TilesLocalGame(seats: 3, seed: 5) == TilesLocalGame(seats: 3, seed: 5))
        #expect(TilesLocalGame(seats: 3, seed: 5) != TilesLocalGame(seats: 3, seed: 6))
    }

    @Test func aGameFromAViewKeepsWhatTheViewShows() throws {
        let view = try #require(DemoFixtures.tilesMid().tiles)
        let game = TilesLocalGame(view: view, seed: 1)
        #expect(game.table == view.table)
        #expect(game.racks[0] == view.racks[0])
        #expect(game.racks.map(\.count) == view.rackCounts)
        #expect(game.pool.count == view.poolCount)
        #expect(conserved(game))
        #expect(game.view(for: [0]) == view)
        #expect(game.view(for: []).racks.isEmpty)
        #expect(game.view(for: [0, 2]).racks.keys.sorted() == [0, 2])
    }

    @Test func turnsFollowTheEngine() {
        var game = TilesLocalGame(seats: 2, seed: 3)
        let first = game.turn, second = 1 - first
        #expect(game.apply(seat: second, .draw) == .failure(.init(code: .notYourTurn)))
        #expect(game.apply(seat: first, .pass) == .failure(.init(code: .poolNotEmpty)))
        guard case .success(let events) = game.apply(seat: first, .draw) else { Issue.record("draw refused"); return }
        #expect(events.count == 2)
        guard case .drew(let seat, let tile, let poolCount) = events[0] else { Issue.record("no drew"); return }
        #expect(seat == first)
        #expect(tile == game.racks[first].last)
        #expect(poolCount == 77)
        #expect(events[1] == .turn(seat: second))
        #expect(game.turn == second)
        #expect(game.turns == 1)
        // The other phone doesn't see the piece.
        #expect(TilesLocalGame.event(events[0], for: [second]) == .drew(seat: first, tile: nil, poolCount: 77))
        #expect(TilesLocalGame.event(events[0], for: [first]) == events[0])
        // A bad play is refused with the rules' own code and changes nothing.
        let before = game
        #expect(game.apply(seat: second, .play(table: [[game.racks[second][0]]])) == .failure(.init(code: .badSet)))
        #expect(game == before)
    }

    @Test func aForfeitWithTwoSeatsEndsTheGame() {
        var game = TilesLocalGame(seats: 2, seed: 3)
        guard case .success(let events) = game.apply(seat: 1, .forfeit) else { Issue.record("refused"); return }
        #expect(events.first == .forfeited(seat: 1))
        #expect(game.status == .gameOver)
        #expect(game.winners == [0])
        #expect(game.endReason == .forfeit)
        #expect(game.scores == [0, 0])
        #expect(game.apply(seat: 0, .draw) == .failure(.init(code: .gameOver)))
    }

    @Test func aForfeitWithMoreSeatsPlaysOn() {
        var game = TilesLocalGame(seats: 3, seed: 3)
        let onTurn = game.turn
        let other = (onTurn + 1) % 3
        guard case .success(let events) = game.apply(seat: other, .forfeit) else { Issue.record("refused"); return }
        #expect(events == [.forfeited(seat: other)])
        #expect(game.turn == onTurn)
        #expect(game.racks[other].isEmpty)
        #expect(game.apply(seat: other, .forfeit) == .failure(.init(code: .forfeited)))
        #expect(game.apply(seat: 7, .forfeit) == .failure(.init(code: .badSeat)))
        // The move skips the seat that left.
        _ = game.apply(seat: onTurn, .draw)
        #expect(game.turn == (onTurn + 2) % 3)
        // A forfeit on its own turn passes the move on.
        let mover = game.turn
        guard case .success(let more) = game.apply(seat: mover, .forfeit) else { Issue.record("refused"); return }
        #expect(more.first == .forfeited(seat: mover))
        #expect(game.status == .gameOver)
        #expect(game.winners == [onTurn])
    }

    @Test func everyoneOutOfMovesEndsItBlocked() throws {
        // Seat 1 holds one piece that fits nowhere, seat 0 two; the toy box is empty.
        let view = TilesView(
            turn: 0, turns: 50, table: [[t(3, .fish), t(4, .fish), t(5, .fish)]], poolCount: 0,
            rackCounts: [2, 1], racks: [0: [t(9, .bell), t(1, .mouse)], 1: [t(13, .feather)]], opened: [true, true])
        var game = TilesLocalGame(view: view, seed: 1)
        // The view shows both racks, so the game holds exactly these pieces.
        #expect(game.racks == [[t(9, .bell), t(1, .mouse)], [t(13, .feather)]])
        #expect(game.botAction(0) == .pass)
        _ = game.apply(seat: 0, .pass)
        #expect(game.passed == [true, false])
        guard case .success(let events) = game.apply(seat: 1, .pass) else { Issue.record("refused"); return }
        #expect(events.last == .gameOver(winners: [0], reason: .blocked, scores: [3, -13], left: [10, 13]))
        #expect(game.status == .gameOver)
    }

    @Test(arguments: [2, 3, 4])
    func botOnlyGamesAlwaysEnd(seats: Int) {
        var finished = 0, turns = 0
        for seed in 0..<25 {
            var game = TilesLocalGame(seats: seats, seed: UInt64(seed * 31 + seats))
            var guardrail = 0
            while game.status == .playing, guardrail < 2000 {
                let seat = game.turn
                let action = game.botAction(seat)
                if case .failure(let refused) = game.apply(seat: seat, action) {
                    Issue.record("seed \(seed): the engine refused its own House Cat: \(refused.code.rawValue)")
                    break
                }
                #expect(conserved(game), "seed \(seed)")
                #expect(game.table.allSatisfy { TilesRules.readSet($0) != nil }, "seed \(seed)")
                guardrail += 1
            }
            if game.status == .gameOver {
                finished += 1
                turns += game.turns
                #expect(!game.winners.isEmpty)
                #expect(game.scores.reduce(0, +) <= 0 || game.winners.count > 1 || game.scores.reduce(0, +) == 0)
            }
        }
        #expect(finished == 25)
        print("[tiles local] \(seats) seats: \(turns / 25) turns a game")
    }
}
#endif
