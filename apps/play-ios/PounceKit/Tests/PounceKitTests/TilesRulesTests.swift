import Foundation
import Testing
@testable import PounceKit

/// One entry of `apps/play-api/fixtures/tiles-sets.json`, the vectors the server's `readSet`
/// is tested against.
struct TileSetVector: Decodable, Sendable, CustomTestStringConvertible {
    let name: String
    let tiles: [TileID]
    /// "run", "group", or nil when the pieces are not a set.
    let kind: String?
    let points: Int?
    /// A run's first number, where the vector pins it.
    let start: Int?

    var testDescription: String { name }

    static func load() throws -> [TileSetVector] {
        try JSONDecoder().decode([TileSetVector].self, from: Data(contentsOf: Fixtures.url("tiles-sets.json")))
    }
}

/// One entry of `Fixtures/tiles/plays.json`: a submitted table and what the server's `checkPlay`
/// said about it. Made from the House Cat's own plays in seeded games, each with a handful of
/// ways to break it, plus hand-made cases for the opening rule and the order of the checks.
struct TilePlayVector: Decodable, Sendable, CustomTestStringConvertible {
    let name: String
    let before: [[TileID]]
    let rack: [TileID]
    let opened: Bool
    let submitted: [[TileID]]
    let ok: Bool
    let error: String?
    let placed: [TileID]?
    let points: Int?

    var testDescription: String { name }

    static func load() throws -> [TilePlayVector] {
        try JSONDecoder().decode([TilePlayVector].self, from: Data(contentsOf: Fixtures.localURL("tiles/plays.json")))
    }
}

@Suite struct TilesRulesTests {
    @Test func pieceDecoding() {
        #expect(Tile(id: 0) == .number(value: 1, suit: .fish))
        #expect(Tile(id: 12) == .number(value: 13, suit: .fish))
        #expect(Tile(id: 13) == .number(value: 1, suit: .fish))
        #expect(Tile(id: 26) == .number(value: 1, suit: .mouse))
        #expect(Tile(id: 70) == .number(value: 6, suit: .feather))
        #expect(Tile(id: 103) == .number(value: 13, suit: .bell))
        #expect(Tile(id: 104) == .yarn)
        #expect(Tile(id: 105) == .yarn)
        #expect(Tile.decode(106) == nil)
        #expect(Tile.decode(-1) == nil)
        #expect(Tile.count == 106)
    }

    @Test func everyNumberAppearsTwicePerSuitAndIdsRoundTrip() {
        var seen: [Tile: Int] = [:]
        for id in 0..<Tile.count { seen[Tile(id: id), default: 0] += 1 }
        #expect(seen[.yarn] == 2)
        #expect(seen.count == 53)
        #expect(seen.filter { $0.key != .yarn }.values.allSatisfy { $0 == 2 })
        for suit in TileSuit.allCases {
            for value in 1...13 {
                for copy in 0...1 {
                    let id = Tile.id(value, suit, copy: copy)
                    #expect(Tile(id: id) == .number(value: value, suit: suit))
                    #expect(Tile.value(id) == value)
                    #expect(Tile.suit(id) == suit)
                    #expect(!Tile.isYarn(id))
                }
            }
        }
        #expect(Tile.yarnIDs == [104, 105])
        #expect(Tile.yarnIDs.allSatisfy(Tile.isYarn))
        #expect(Tile.value(104) == nil)
        #expect(Tile.suit(105) == nil)
    }

    @Test func rackPoints() {
        #expect(Tile.rackPoints(0) == 1)
        #expect(Tile.rackPoints(103) == 13)
        #expect(Tile.rackPoints(104) == 30)
        #expect(Tile.rackTotal([0, 12, 104]) == 44)
        #expect(Tile.rackTotal([]) == 0)
    }

    @Test func theSharedVectorsAreAllHere() throws {
        // A count that moves means the server's file changed: look at what was added.
        #expect(try TileSetVector.load().count == 43)
    }

    @Test(arguments: try! TileSetVector.load())
    func setVectors(_ v: TileSetVector) {
        let reading = TilesRules.readSet(v.tiles)
        switch (v.kind, reading) {
        case (nil, nil):
            break
        case ("run", .run(_, let start, let end, let points)):
            #expect(points == v.points, "\(v.name)")
            #expect(end - start + 1 == v.tiles.count, "\(v.name)")
            // The vectors' `start` is the number the lowest Yarn-free reading pins, where given;
            // every run's start is also checked against its first number piece.
            if let at = v.tiles.firstIndex(where: { !Tile.isYarn($0) }), let value = Tile.value(v.tiles[at]) {
                #expect(start == value - at, "\(v.name)")
            }
        case ("group", .group(let value, let points)):
            #expect(points == v.points, "\(v.name)")
            #expect(v.tiles.compactMap(Tile.value).allSatisfy { $0 == value }, "\(v.name)")
        default:
            Issue.record("\(v.name): read as \(String(describing: reading)), the server says \(v.kind ?? "not a set")")
        }
    }

    @Test func twoYarnReadings() {
        // 5, Yarn, Yarn: a run 5-6-7 (18) beats a group of 5s (15).
        #expect(TilesRules.readSet([4, 104, 105]) == .run(suit: .fish, start: 5, end: 7, points: 18))
        // Yarn, Yarn, 10: only 8-9-10 as a run (27); the group of 10s is worth 30 and wins.
        #expect(TilesRules.readSet([104, 105, 9]) == .group(value: 10, points: 30))
        // Yarn, 6, Yarn: 5-6-7 and three 6s are both 18; a tie reads as the run.
        #expect(TilesRules.readSet([104, 5, 105]) == .run(suit: .fish, start: 5, end: 7, points: 18))
    }

    @Test func standingsSayWhatAYarnIs() {
        // In a run the place gives the number.
        #expect(TilesRules.standings([3, 104, 5]) == [
            TileStanding(value: 4, suit: .fish), TileStanding(value: 5, suit: .fish), TileStanding(value: 6, suit: .fish),
        ])
        // In a group of three plus one Yarn the Yarn is the one suit not there.
        let sevens = [Tile.id(7, .fish), Tile.id(7, .mouse), Tile.id(7, .bell), 104]
        #expect(TilesRules.standings(sevens)?.last == TileStanding(value: 7, suit: .feather))
        // With two suits open it is the number in a suit not yet there, whichever.
        #expect(TilesRules.standings([Tile.id(7, .fish), Tile.id(7, .mouse), 104])?.last == TileStanding(value: 7, suit: nil))
        #expect(TilesRules.standings([3, 4]) == nil)
    }

    @Test func thePlayVectorsCoverEveryRefusal() throws {
        let vectors = try TilePlayVector.load()
        #expect(vectors.count == 240)
        let errors = Set(vectors.compactMap(\.error))
        #expect(errors == Set(TilesPlayError.allCases.map(\.rawValue)))
        #expect(vectors.contains { $0.ok && !$0.opened })
        #expect(vectors.contains { $0.ok && $0.opened })
    }

    @Test(arguments: try! TilePlayVector.load())
    func playVectors(_ v: TilePlayVector) {
        switch TilesRules.checkPlay(before: v.before, rack: v.rack, opened: v.opened, submitted: v.submitted) {
        case .success(let play):
            #expect(v.ok, "\(v.name): the server refuses this with \(v.error ?? "?")")
            #expect(play.placed == v.placed, "\(v.name)")
            #expect(play.points == v.points, "\(v.name)")
        case .failure(let error):
            #expect(!v.ok, "\(v.name): the server takes this")
            #expect(error.rawValue == v.error, "\(v.name)")
        }
    }

    @Test func theOpeningThirty() {
        let nines = [Tile.id(9, .fish), Tile.id(9, .mouse), Tile.id(9, .bell)]
        let rack = [Tile.id(10, .mouse), 104, 105, Tile.id(9, .feather), Tile.id(1, .fish), Tile.id(2, .fish), Tile.id(3, .fish)]
        func check(_ opened: Bool, _ table: [[TileID]]) -> Result<TilesPlay, TilesPlayError> {
            TilesRules.checkPlay(before: [nines], rack: rack, opened: opened, submitted: table)
        }
        // Yarn, Yarn, 10 is a group worth exactly 30, and it opens.
        #expect(check(false, [nines, [104, 105, Tile.id(10, .mouse)]]) == .success(TilesPlay(placed: [104, 105, Tile.id(10, .mouse)], points: 30)))
        // 1-2-3 is 6: not enough.
        #expect(check(false, [nines, [Tile.id(1, .fish), Tile.id(2, .fish), Tile.id(3, .fish)]]) == .failure(.openingTooLow))
        // Adding to a set on the rug is not an opening.
        #expect(check(false, [nines + [Tile.id(9, .feather)]]) == .failure(.tableTouched))
        // Once opened both are fine.
        #expect(check(true, [nines, [Tile.id(1, .fish), Tile.id(2, .fish), Tile.id(3, .fish)]]).map(\.points) == .success(6))
        #expect(check(true, [nines + [Tile.id(9, .feather)]]).map(\.points) == .success(36))
    }
}
