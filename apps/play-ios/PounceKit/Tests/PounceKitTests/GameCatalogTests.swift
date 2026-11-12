import Foundation
import Testing
@testable import PounceKit

@Suite struct GameCatalogTests {
    @Test func theCatalogHoldsCatTowerThenTiles() {
        #expect(GameCatalog.all.map(\.id) == ["cat-tower", "tiles"])
    }

    @Test func catTowerIsTheGameTheServerDealsAndCanBeStarted() {
        #expect(GameCatalog.dealt.id == "cat-tower")
        #expect(GameCatalog.catTower.isAvailable)
        #expect(GameCatalog.catTower.minPlayers == 2)
        #expect(GameCatalog.catTower.maxPlayers == 6)
    }

    @Test func tilesIsOnTheShelfButNotStartableYet() {
        #expect(GameCatalog.tiles.availability == .comingSoon)
        #expect(!GameCatalog.tiles.isAvailable)
        #expect(GameCatalog.tiles.minPlayers == 2)
        #expect(GameCatalog.tiles.maxPlayers == 4)
    }

    @Test func idsAreUniqueLowerCaseAndHyphenated() {
        let ids = GameCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(id.wholeMatch(of: /[a-z]+(-[a-z]+)*/) != nil, "\(id)")
        }
    }

    @Test func everyEntryHasANameAShortPlainPitchAndItsOwnArt() {
        for entry in GameCatalog.all {
            #expect(!entry.title.isEmpty)
            #expect(!entry.pitch.isEmpty)
            #expect(entry.pitch.count <= 40, "\(entry.id): the pitch is one short line")
            // Plain words: no emoji, no symbols beyond sentence punctuation.
            #expect((entry.title + entry.pitch).unicodeScalars.allSatisfy { $0.isASCII }, "\(entry.id)")
            #expect(entry.art.hasPrefix("game-"))
            #expect(entry.minPlayers >= 2)
            #expect(entry.maxPlayers >= entry.minPlayers)
        }
        #expect(Set(GameCatalog.all.map(\.art)).count == GameCatalog.all.count)
        #expect(Set(GameCatalog.all.map(\.title)).count == GameCatalog.all.count)
    }

    /// Each game names its own How to play video, and a made-up entry has none.
    @Test func everyGameHasItsOwnHowToVideo() {
        let videos = GameCatalog.all.compactMap(\.howTo)
        #expect(videos.count == GameCatalog.all.count)
        #expect(Set(videos).count == videos.count)
        #expect(GameCatalog.catTower.howTo == "howto-cat-tower")
        #expect(GameCatalog.Entry(id: "x", title: "X", pitch: "p", minPlayers: 2, maxPlayers: 4, art: "a", tint: .sky,
                                  availability: .comingSoon).howTo == nil)
    }

    @Test func entriesAreFoundById() {
        #expect(GameCatalog.entry(id: "cat-tower") == GameCatalog.catTower)
        #expect(GameCatalog.entry(id: "tiles") == GameCatalog.tiles)
        #expect(GameCatalog.entry(id: "chess") == nil)
    }

    @Test func theShelfPutsStartableGamesFirstAndKeepsCatalogOrder() {
        func game(_ id: String, _ availability: GameCatalog.Entry.Availability) -> GameCatalog.Entry {
            GameCatalog.Entry(
                id: id, title: id, pitch: "p", minPlayers: 2, maxPlayers: 4, art: "game-\(id)", tint: .sky,
                availability: availability)
        }
        let shelf = GameCatalog.shelf([
            game("a", .available), game("b", .comingSoon), game("c", .available), game("d", .comingSoon),
            game("e", .available),
        ])
        #expect(shelf.map(\.id) == ["a", "c", "e", "b", "d"])
        #expect(GameCatalog.shelf().map(\.id) == ["cat-tower", "tiles"])
    }

    @Test func unlockingAGameOnlyChangesItsAvailability() {
        let open = GameCatalog.tiles.unlocked()
        #expect(open.isAvailable)
        #expect(open.id == GameCatalog.tiles.id)
        #expect(open.title == GameCatalog.tiles.title)
        #expect(open.art == GameCatalog.tiles.art)
        #expect(open.howTo == GameCatalog.tiles.howTo)
        #expect(GameCatalog.shelf([GameCatalog.tiles.unlocked(), GameCatalog.catTower]).map(\.id) == ["tiles", "cat-tower"])
    }

    // MARK: what Home leads with

    private func table(_ code: String, _ status: String, turn: Bool = false) -> HomeTableItem {
        HomeTableItem(id: code, name: nil, yourTurn: turn, status: status, seats: [], turnCat: nil, updatedAt: 0)
    }

    @Test func homeLeadsWithTheShelfUntilAGameIsGoing() {
        #expect(HomeLead.pick([]) == .shelf)
        #expect(HomeLead.pick([table("OVER1", "over")]) == .shelf)
        #expect(HomeLead.pick([table("LOBB1", "lobby")]) == .tables)
        #expect(HomeLead.pick([table("OVER1", "over"), table("PLAY1", "playing")]) == .tables)
        #expect(HomeLead.pick([table("MINE1", "playing", turn: true)]) == .tables)
    }

    @Test func homeCountsTheTablesWaitingOnYou() {
        #expect(HomeLead.waiting([]) == 0)
        #expect(HomeLead.waiting([table("A", "playing", turn: true), table("B", "playing"), table("C", "playing", turn: true)]) == 2)
    }
}
