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
            /// Played, but only a TV starts a table (Purrtrait: the TV is the easel). The phone's
            /// card says "Starts on the TV" and a tip says to pick it there.
            case onTV
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

        /// Played on this app, though a phone can't start it (`onTV`), or startable here.
        public var isPlayable: Bool { availability != .comingSoon }

        /// Only a TV makes this game's table.
        public var startsOnTV: Bool { availability == .onTV }

        /// The same game, startable (a debug preview of a game before it ships).
        public func unlocked() -> Entry {
            Entry(
                id: id, title: title, pitch: pitch, minPlayers: minPlayers, maxPlayers: maxPlayers, art: art, tint: tint,
                availability: availability == .onTV ? .onTV : .available, howTo: howTo)
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

    /// The trick-taking game with bidding, the feeder and the Bird (design 2026-11-25).
    public static let birdwatch = Entry(
        id: "birdwatch", title: "Birdwatch", pitch: "Bid, call trump, take tricks.",
        minPlayers: 4, maxPlayers: 6, art: "game-birdwatch", tint: .lime, availability: .available)

    /// The real-time falling-toys battle (design 2026-11-26). Gated: see `ships14`.
    public static let tumble = Entry(
        id: "tumble", title: "Toy Tumble", pitch: "Drop toys, clear rows, toss tricks.",
        minPlayers: 2, maxPlayers: 6, art: "game-tumble", tint: .lime, availability: .available)

    /// The draw-and-guess party game (design 2026-11-26): the TV is the easel, the drawer draws
    /// on a phone, everyone else shouts. A TV starts the table. Gated: see `ships14`.
    public static let purrtrait = Entry(
        id: "purrtrait", title: "Purrtrait", pitch: "Draw it. They shout it.",
        minPlayers: 2, maxPlayers: 10, art: "game-purrtrait", tint: .magenta, availability: .onTV)

    /// Toy Tumble and Purrtrait come with the app's 1.4 (Toy Tumble design §10.4): a Release
    /// build below 1.4 never shows them or asks the server for them, so `main` can build 1.3 with
    /// them merged. Debug builds always have them, to play them on a dev server.
    public static func ships14(debug: Bool, version: String?) -> Bool {
        if debug { return true }
        guard let version = AppVersion(version), let first = AppVersion("1.4") else { return false }
        return version >= first
    }

    /// The games this build has, in catalog order (the order games were added, oldest first).
    public static func games(debug: Bool, version: String?) -> [Entry] {
        [catTower, tiles, birdwatch] + (ships14(debug: debug, version: version) ? [tumble, purrtrait] : [])
    }

    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Catalog order: the order games were added, oldest first. Toy Tumble and Purrtrait only
    /// from 1.4.
    public static let all: [Entry] = games(debug: isDebug, version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)

    /// The game the server deals when a table is created.
    public static let dealt = catTower

    public static func entry(id: String) -> Entry? {
        all.first { $0.id == id }
    }

    /// A table's game by name, for share text and titles: a game this app doesn't know, or a
    /// table from before tables had a game (nil), is the one the server dealt then.
    public static func title(of id: String?) -> String {
        id.flatMap { entry(id: $0) }?.title ?? dealt.title
    }

    /// The shelf, top to bottom: the games you can start, then the ones on the way, each group in
    /// catalog order.
    public static func shelf(_ entries: [Entry] = all) -> [Entry] {
        entries.filter(\.isAvailable) + entries.filter(\.startsOnTV) + entries.filter { !$0.isPlayable }
    }
}

/// What Home leads with (game picker design). Someone with a game going came back for their
/// tables, so those sit above the shelf; with no table, or only finished ones, the shelf leads.
public enum HomeLead: Equatable, Sendable {
    case tables, shelf

    public static func pick(_ items: [HomeTableItem]) -> HomeLead {
        items.contains { $0.status != RoomStatus.over.rawValue } ? .tables : .shelf
    }

    /// The lead at launch. `known`: the phone has a saved table list or the server answered.
    /// Until then a phone that has played (`hadTables`, from its room cache) leads with nothing,
    /// so a returning player never sees the first-visit posters flash before their tables.
    public static func pick(_ items: [HomeTableItem], known: Bool, hadTables: Bool) -> HomeLead? {
        if items.isEmpty, !known, hadTables { return nil }
        return pick(items)
    }

    /// How many tables wait on this phone's move.
    public static func waiting(_ items: [HomeTableItem]) -> Int {
        items.count { $0.yourTurn }
    }
}
