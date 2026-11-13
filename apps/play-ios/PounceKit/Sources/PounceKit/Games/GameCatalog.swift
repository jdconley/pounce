import Foundation

/// Every game Pounce knows about, in shelf order. Home's game shelf draws from this and nothing
/// else: a new game is one entry here plus its cover art (`Art/manifest.json`, `ArtName.swift`).
///
/// The server deals one game today (`dealt`, Cat Tower). A table started from a card asks the
/// create route for that card's `id`, so a second game goes live in one place: flip its
/// `availability` below once the server deals it.
public enum GameCatalog {
    public struct Entry: Identifiable, Equatable, Sendable {
        public enum Availability: String, Equatable, Sendable {
            /// On the shelf and startable.
            case available
            /// On the shelf, named and pictured, but no table can be started yet.
            case comingSoon
        }

        /// The card's colour, from the app's palette (`Palette` maps it): the band under the art.
        public enum Tint: String, CaseIterable, Sendable {
            case violet, magenta, teal, orange, sky, lime
        }

        /// Stable, lower-case, hyphenated: the server's game id once it takes one. Never reused.
        public let id: String
        /// The game's name. A name, so it is not translated.
        public let title: String
        /// One short, plain line under the name.
        public let pitch: String
        public let minPlayers: Int
        public let maxPlayers: Int
        /// The cover's image set in the asset catalog (3:2, the subject in the middle, so a
        /// centred square or a wide banner can be cut from it).
        public let art: String
        public let tint: Tint
        public let availability: Availability
        /// How to play's video: the base name of `<howTo>.mp4` and its poster `<howTo>.jpg` in the
        /// app bundle (`Pounce/Resources/HowTo/`, made by `HowTo/make.sh`). Nil: text only. The
        /// text is the app's `HowToGuide` for this entry's `id`.
        public let howTo: String?

        public init(
            id: String, title: String, pitch: String, minPlayers: Int, maxPlayers: Int, art: String, tint: Tint,
            availability: Availability, howTo: String? = nil
        ) {
            self.id = id
            self.title = title
            self.pitch = pitch
            self.minPlayers = minPlayers
            self.maxPlayers = maxPlayers
            self.art = art
            self.tint = tint
            self.availability = availability
            self.howTo = howTo
        }

        public var isAvailable: Bool { availability == .available }

        /// The same game, startable (a debug preview of a game before it ships).
        public func unlocked() -> Entry {
            Entry(
                id: id, title: title, pitch: pitch, minPlayers: minPlayers, maxPlayers: maxPlayers, art: art, tint: tint,
                availability: .available, howTo: howTo)
        }
    }

    public static let catTower = Entry(
        id: "cat-tower", title: "Cat Tower", pitch: "Rummy up a ten-shelf tower.",
        minPlayers: 2, maxPlayers: 6, art: "game-cat-tower", tint: .violet, availability: .available,
        howTo: "howto-cat-tower")

    /// Working title.
    public static let tiles = Entry(
        id: "tiles", title: "Tuna Tiles", pitch: "Tile rummy. Yarn is wild.",
        minPlayers: 2, maxPlayers: 4, art: "game-tiles", tint: .sky, availability: .available,
        howTo: "howto-tiles")

    /// Catalog order: the order games were added, oldest first.
    public static let all: [Entry] = [catTower, tiles]

    /// The game the server deals when a table is created.
    public static let dealt = catTower

    public static func entry(id: String) -> Entry? {
        all.first { $0.id == id }
    }

    /// The shelf, top to bottom: the games you can start, then the ones on the way, each group in
    /// catalog order.
    public static func shelf(_ entries: [Entry] = all) -> [Entry] {
        entries.filter(\.isAvailable) + entries.filter { !$0.isAvailable }
    }
}

/// What Home leads with (game picker design). Someone with a game going came back for their
/// tables, so those sit above the shelf; with no table, or only finished ones, the shelf leads.
public enum HomeLead: Equatable, Sendable {
    case tables, shelf

    public static func pick(_ items: [HomeTableItem]) -> HomeLead {
        items.contains { $0.status != RoomStatus.over.rawValue } ? .tables : .shelf
    }

    /// How many tables wait on this phone's move.
    public static func waiting(_ items: [HomeTableItem]) -> Int {
        items.count { $0.yourTurn }
    }
}
