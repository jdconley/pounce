import PounceKit
import SwiftUI

/// How to play's words for one game, in the order its video shows them (`HowTo/beats.json`).
/// The video itself comes from the catalog entry (`GameCatalog.Entry.howTo`); a game with no
/// guide here shows its video alone.
struct HowToGuide {
    struct Section {
        let title: String
        let color: Color
        let lines: [String]
    }

    let sections: [Section]
    /// Cat Tower: the card listing the ten levels, after the sections.
    var showsLevels = false
    /// Cat Tower's first-game tips can be brought back from here.
    var replaysTips = false
    /// Where the wide (iPad) layout starts its second column.
    var split: Int

    static func of(_ game: GameCatalog.Entry) -> HowToGuide {
        switch game.id {
        case GameCatalog.catTower.id: catTower
        case GameCatalog.tiles.id: tiles
        default: HowToGuide(sections: [], split: 0)
        }
    }

    static let catTower = HowToGuide(
        sections: [
            Section(
                title: String(localized: "The goal", comment: "Rules sheet section"), color: Palette.violet,
                lines: [
                    String(localized: "Climb the cat tower. It has ten shelves, one for each level.", comment: "Rules: goal"),
                    String(localized: "Lay down your level in a round to climb a shelf. If you don't, you try it again next round.", comment: "Rules: goal"),
                ]),
            Section(
                title: String(localized: "Your turn", comment: "Rules sheet section"), color: Palette.teal,
                lines: [
                    String(localized: "1. Take a card from the deck or the top of the discard pile.", comment: "Rules: turn step"),
                    String(localized: "2. Build your level in the trays: tap a card, then a tray, or drag the card there.", comment: "Rules: turn step"),
                    String(localized: "3. When your trays hold your whole level, lay it down.", comment: "Rules: turn step"),
                    String(localized: "4. Once your level is down, add cards to any laid group, yours or anyone's.", comment: "Rules: turn step"),
                    String(localized: "5. Put one card on the discard pile to end your turn.", comment: "Rules: turn step"),
                ]),
            Section(
                title: String(localized: "Groups", comment: "Rules sheet section"), color: Palette.orange,
                lines: [
                    String(localized: "Set: all the same number, like three 7s.", comment: "Rules: what a set is"),
                    String(localized: "Run: numbers in a row, like 4 5 6 7.", comment: "Rules: what a run is"),
                    String(localized: "One coat: the same cat on every card, any numbers.", comment: "Rules: what a coat group is"),
                ]),
            Section(
                title: String(localized: "Special cards", comment: "Rules sheet section"), color: Palette.magenta,
                lines: [
                    String(localized: "Yarn is wild: it stands in for any number in a set or a run.", comment: "Rules: Yarn"),
                    String(localized: "Cucumber: drop it on another cat to make them skip their next turn. You can't take one from the discard pile.", comment: "Rules: Cucumber"),
                ]),
            Section(
                title: String(localized: "End of a round", comment: "Rules sheet section"), color: Palette.lime,
                lines: [
                    String(localized: "The round ends when someone plays or discards their last card.", comment: "Rules: round end"),
                    String(localized: "Cards left in your hand score points: 5 for 1 to 9, 10 for 10 to 12, 15 for a Cucumber, 25 for Yarn. Low is good.", comment: "Rules: scoring"),
                    String(localized: "Everyone who laid down their level climbs a shelf.", comment: "Rules: climbing after a round"),
                ]),
            Section(
                title: String(localized: "Winning", comment: "Rules sheet section"), color: Palette.sky,
                lines: [
                    String(localized: "The first cat to finish all ten levels wins. If two finish together, the lower score wins.", comment: "Rules: winning"),
                ]),
            Section(
                title: String(localized: "Ending early", comment: "Rules sheet section"), color: Palette.teal,
                lines: [
                    String(localized: "Forfeit from the paw menu to leave a game. You finish last and everyone else plays on.", comment: "Rules: forfeit"),
                    String(localized: "If someone hasn't moved for 3 days, anyone else can retire their seat from their player card. It counts as a forfeit.", comment: "Rules: retiring an absent player"),
                    String(localized: "The game ends early once the rest of the hand can't change who wins.", comment: "Rules: the early end"),
                ]),
        ],
        showsLevels: true, replaysTips: true, split: 3)

    /// The tile game, in our own words (tile game spec §4).
    static let tiles = HowToGuide(
        sections: [
            Section(
                title: String(localized: "Tidy up", comment: "Tile game rules: the goal"), color: Palette.orange,
                lines: [
                    String(localized: "The cats tipped the toy box onto the rug. Be the first to put every toy from your stash onto the rug.", comment: "Tile game rules"),
                    String(localized: "There are 106 toys: 1 to 13 in four kinds (fish, mouse, feather, bell), two of each, and 2 Yarn. Everyone starts with 14.", comment: "Tile game rules"),
                ]),
            Section(
                title: String(localized: "Sets", comment: "Tile game rules: sets"), color: Palette.teal,
                lines: [
                    String(localized: "Everything on the rug sits in a set of three or more.", comment: "Tile game rules"),
                    String(localized: "A match is three or four toys with the same number, each a different kind.", comment: "Tile game rules"),
                    String(localized: "A row is one kind of toy with numbers that climb by one: 4, 5, 6. A 1 is only ever low, and nothing comes after 13.", comment: "Tile game rules"),
                ]),
            Section(
                title: String(localized: "Your first play", comment: "Tile game rules: the opening"), color: Palette.violet,
                lines: [
                    String(localized: "Your first play has to stand on its own: new sets from your stash only, worth 30 or more when you add up their numbers.", comment: "Tile game rules"),
                    String(localized: "The meter over your stash adds them up as you go.", comment: "Tile game rules: the opening meter"),
                ]),
            Section(
                title: String(localized: "Your turn", comment: "Tile game rules: a turn"), color: Palette.magenta,
                lines: [
                    String(localized: "Play: tap a toy, then a set (or drag it there). Tap the empty slot to start a new set. Press Play when every set is good.", comment: "Tile game rules"),
                    String(localized: "Or hold Draw to take one toy from the toy box. That is your whole turn.", comment: "Tile game rules"),
                    String(localized: "When the toy box is empty you may pass.", comment: "Tile game rules"),
                ]),
            Section(
                title: String(localized: "Yarn", comment: "Tile game rules: the wild piece"), color: Palette.sky,
                lines: [
                    String(localized: "Yarn stands for any one toy. In a row it is the number its place gives it. In a match it is that number in a kind that isn't there yet.", comment: "Tile game rules"),
                    String(localized: "Put the real toy where a Yarn stands and the Yarn moves along. Once it is on the rug it stays on the rug.", comment: "Tile game rules"),
                ]),
            Section(
                title: String(localized: "Rearranging", comment: "Tile game rules: moving sets around"), color: Palette.lime,
                lines: [
                    String(localized: "After your first play you can take the whole rug apart and rebuild it, as long as every toy is back in a set when you press Play.", comment: "Tile game rules"),
                    String(localized: "Tap a set to open it. Drag its toys to other sets, or tap between two toys to split it.", comment: "Tile game rules: the loupe"),
                ]),
            Section(
                title: String(localized: "The end", comment: "Tile game rules: scoring"), color: Palette.orange,
                lines: [
                    String(localized: "Empty your stash and you win. Everyone else is charged the numbers left in theirs, 30 for a Yarn, and you collect it all.", comment: "Tile game rules"),
                    String(localized: "If the toy box is empty and everyone passes, the smallest stash total wins.", comment: "Tile game rules"),
                ]),
        ],
        split: 4)
}
