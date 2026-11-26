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
        case GameCatalog.purrtrait.id: purrtrait
        default: HowToGuide(sections: [], split: 0)
        }
    }

    /// Purrtrait (spec §4, in our words): the TV is the easel, guesses are said out loud.
    static let purrtrait = HowToGuide(
        sections: [
            Section(
                title: String(localized: "Get ready", comment: "Purrtrait rules section"), color: Palette.violet,
                lines: [
                    String(localized: "Pick Purrtrait on the TV. Everyone scans its code to join. 2 to 10 players.", comment: "Purrtrait rules: setup"),
                    String(localized: "The host picks the timer: 45, 60 or 90 seconds a turn.", comment: "Purrtrait rules: the timer"),
                ]),
            Section(
                title: String(localized: "Draw", comment: "Purrtrait rules section"), color: Palette.magenta,
                lines: [
                    String(localized: "On your turn, pick one of two words: Easy for 1 point, Tricky for 2.", comment: "Purrtrait rules: the pick"),
                    String(localized: "Draw it on your phone. The TV shows your lines as you draw.", comment: "Purrtrait rules: drawing"),
                    String(localized: "No letters, numbers or talking about the word.", comment: "Purrtrait rules: what the drawer can't do"),
                ]),
            Section(
                title: String(localized: "Guess", comment: "Purrtrait rules section"), color: Palette.teal,
                lines: [
                    String(localized: "Everyone else shouts out guesses. The TV shows the word's group as a hint.", comment: "Purrtrait rules: guessing"),
                    String(localized: "Heard it? Tap Got it, then who said it first. You both score.", comment: "Purrtrait rules: Got it"),
                    String(localized: "Time up, or Give up: nobody scores, and the TV shows the word.", comment: "Purrtrait rules: a missed turn"),
                ]),
            Section(
                title: String(localized: "Win", comment: "Purrtrait rules section"), color: Palette.orange,
                lines: [
                    String(localized: "Everyone draws twice. The most points wins. A tie shares the win.", comment: "Purrtrait rules: the end"),
                    String(localized: "Drawings show only on the TV and are gone when the turn ends.", comment: "Purrtrait rules: drawings aren't kept"),
                ]),
        ],
        split: 2)

    /// Birdwatch, for one rule set (design §4, in our words).
    static func birdwatch(_ rules: BirdRules) -> HowToGuide {
        let target = rules == .official ? 300 : 500
        let top = rules == .official ? 120 : 180
        var deck = [
            String(localized: "Four toys: fish, mouse, feather and bell, plus the Bird.", comment: "Birdwatch rules: the deck"),
        ]
        switch rules {
        case .official:
            deck.append(String(localized: "Cards run 5 to 14. With 5 or 6 players, 2 to 4 join in.", comment: "Birdwatch rules: Official's deck"))
        case .tucker, .friesen:
            deck.append(String(localized: "Cards run 5 to 14, and the 1 beats the 14. With 5 or 6 players, 2 to 4 join in.", comment: "Birdwatch rules: Tucker and Friesen's deck"))
        }
        var points = [
            String(localized: "Seed badges show points: 5s are 5, 10s and 14s are 10, the Bird is 20.", comment: "Birdwatch rules: counters"),
        ]
        if rules != .official {
            points.append(String(localized: "Each 1 is 15.", comment: "Birdwatch rules: the 1 counts 15 in Tucker and Friesen"))
        }
        points.append(String(localized: "Every hand holds \(top) points.", comment: "Birdwatch rules: the points in a hand"))
        let bird = rules == .friesen
            ? String(localized: "The Bird is the top trump. Play it like any trump: when trump is led, or when you can't follow suit.", comment: "Birdwatch rules: Friesen's Bird")
            : String(localized: "The Bird is the top trump, and you can play it any time.", comment: "Birdwatch rules: the wild Bird")
        return HowToGuide(
            sections: [
                Section(
                    title: String(localized: "Teams", comment: "Birdwatch rules section"), color: Palette.violet,
                    lines: [
                        String(localized: "4 players: two teams of two. 6 players: three teams of two. Teammates sit across.", comment: "Birdwatch rules: teams"),
                        String(localized: "5 players: the bid winner calls a card. Whoever holds it is their partner, in secret.", comment: "Birdwatch rules: five players"),
                    ] + deck),
                Section(
                    title: String(localized: "Bidding", comment: "Birdwatch rules section"), color: Palette.orange,
                    lines: [
                        String(localized: "Bid how many points your side will take: 70 up to \(top), by 5s. Or pass, and you're out of the bidding.", comment: "Birdwatch rules: bidding"),
                        String(localized: "The high bid takes the feeder's cards, puts the same number back and names trump.", comment: "Birdwatch rules: the nest"),
                    ]),
                Section(
                    title: String(localized: "Tricks", comment: "Birdwatch rules section"), color: Palette.teal,
                    lines: [
                        String(localized: "Follow the suit that was led if you can. Cards you can't play are dimmed.", comment: "Birdwatch rules: follow suit"),
                        String(localized: "The highest trump takes the trick, or the highest card of the suit led.", comment: "Birdwatch rules: who takes a trick"),
                        bird,
                        String(localized: "The last trick also takes the cards put back.", comment: "Birdwatch rules: the nest goes to the last trick"),
                    ]),
                Section(
                    title: String(localized: "Scoring", comment: "Birdwatch rules section"), color: Palette.magenta,
                    lines: points + [
                        String(localized: "Made your bid: score what you took. Missed: lose your bid.", comment: "Birdwatch rules: made and missed"),
                        String(localized: "First side to \(target) wins. A side that missed its bid can't win on that hand.", comment: "Birdwatch rules: winning"),
                    ]),
                Section(
                    title: String(localized: "Leaving", comment: "Birdwatch rules section"), color: Palette.sky,
                    lines: [
                        String(localized: "Leave from the paw menu. A House Cat plays on for your team.", comment: "Birdwatch rules: leaving"),
                    ]),
            ],
            split: 2)
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

/// Birdwatch's three rule sets as big pills, the chosen one lit with its line under it (the
/// lobby's and How to play's).
struct BirdRulesPills: View {
    @Binding var rules: BirdRules
    var enabled = true
    var onPick: (BirdRules) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ForEach(BirdRules.allCases, id: \.self) { option in
                    let on = option == rules
                    Button {
                        guard enabled, !on else { return }
                        Haptics.shared.tick()
                        withAnimation(.spring(duration: 0.3).paced) { rules = option }
                        onPick(option)
                    } label: {
                        Text(BirdWords.rules(option))
                            .font(.system(.headline, design: .rounded, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule().fill(on ? Palette.lime.mix(with: Palette.ink, by: 0.15) : Palette.ink.opacity(0.55))
                                    .overlay(Capsule().strokeBorder(on ? Palette.ink : Palette.lime, lineWidth: 3))
                                    .shadow(color: Palette.ink.opacity(on ? 0.6 : 0), radius: 0, x: 0, y: 3))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(enabled)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityHint(Text(verbatim: BirdWords.rulesLine(option)))
                    .accessibilityIdentifier("bird.rules.\(option.rawValue)")
                }
            }
            Text(BirdWords.rulesLine(rules))
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        // The three names always fit on one row, so the pills stop growing at the largest
        // standard size (VoiceOver and the line under them still read in full).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bird.rules")
    }
}
