import Foundation

/// The screens that carry tips about the app itself (not the game's rules, which `CoachTip`
/// teaches on the Cat Tower table). One screen hosts tips at a time: the one on top.
public enum TipScreen: String, CaseIterable, Codable, Sendable {
    case home, lobby, tableMenu, pounce, us, gear, tiles
}

/// What makes a tip worth showing, beyond its control being on screen.
public indirect enum TipTrigger: Hashable, Sendable {
    /// The control it points at is on screen (every tip needs that anyway).
    case visible
    /// The app has been opened at least this many times on this phone.
    case opens(Int)
    /// This person has seen or learned that tip already.
    case after(UITip)
    /// Something happened this session (`TipEvent`).
    case event(TipEvent)
    case all([TipTrigger])

    func holds(_ facts: TipFacts, seen: Set<UITip>) -> Bool {
        switch self {
        case .visible: true
        case .opens(let n): facts.opens >= n
        case .after(let tip): seen.contains(tip)
        case .event(let event): facts.events.contains(event)
        case .all(let triggers): triggers.allSatisfy { $0.holds(facts, seen: seen) }
        }
    }
}

/// Things the app tells the tips about as they happen.
public enum TipEvent: String, Hashable, Codable, Sendable {
    /// A game ended at a table on this phone.
    case gameOver
}

/// Who a tip is for. Nil means anyone.
public struct TipAudience: Hashable, Sendable {
    public var bands: Set<AgeBand>?
    /// True: only on a phone several people share. False: only on a phone with one person.
    public var passAndPlay: Bool?

    public init(bands: Set<AgeBand>? = nil, passAndPlay: Bool? = nil) {
        self.bands = bands
        self.passAndPlay = passAndPlay
    }

    public static let anyone = TipAudience()

    func includes(_ facts: TipFacts) -> Bool {
        if let bands, !bands.contains(facts.band ?? .adult) { return false }
        if let passAndPlay, passAndPlay != facts.passAndPlay { return false }
        return true
    }
}

/// One rule for one UI tip: where it shows, what it points at, when, for whom, and what use of
/// the app shows it is already learned.
public struct UITipRule: Sendable {
    public let screen: TipScreen
    /// The tip anchor (the same string as the control's accessibility identifier).
    public let anchor: String
    /// Higher shows first when several tips fit.
    public let priority: Int
    public let trigger: TipTrigger
    public let audience: TipAudience
    /// Controls whose use teaches this tip (`TipCenter.used`), shown or not. The anchor always counts.
    public let learnedBy: Set<String>
}

/// The tips that teach the app's own controls. The raw value is what `tutorial.json` keeps; the
/// "ui." prefix keeps them apart from the game's tips.
public enum UITip: String, CaseIterable, Codable, Sendable {
    // Home
    case homeShelf = "ui.home.shelf"
    case homePractice = "ui.home.practice"
    case homeJoin = "ui.home.join"
    case homeTables = "ui.home.tables"
    case homeArchive = "ui.home.archive"
    case homeRules = "ui.home.rules"
    case homeStreak = "ui.home.streak"
    case homeInvite = "ui.home.invite"
    case homeGift = "ui.home.gift"
    case homePeople = "ui.home.people"
    case homeUpdate = "ui.home.update"
    // The lobby
    case lobbySeat = "ui.lobby.seat"
    case lobbyAdd = "ui.lobby.add"
    case lobbyShare = "ui.lobby.share"
    case lobbyStart = "ui.lobby.start"
    // The table's paw menu
    case menuLook = "ui.menu.look"
    case menuMove = "ui.menu.move"
    // Pounce, Us, settings
    case pouncePick = "ui.pounce.pick"
    case usBell = "ui.us.bell"
    case usTrophies = "ui.us.trophies"
    case gearAlerts = "ui.gear.alerts"
    // The tile game's table
    case tilesMeter = "ui.tiles.meter"
    case tilesPlay = "ui.tiles.play"
    case tilesDraw = "ui.tiles.draw"
    case tilesSort = "ui.tiles.sort"
    case tilesLoupe = "ui.tiles.loupe"

    public var rule: UITipRule {
        switch self {
        case .homeShelf: r(.home, "home.play", 100, learnedBy: ["home.newGame"])
        case .homePractice: r(.home, "home.practice", 90, .after(.homeShelf))
        case .homeJoin: r(.home, "home.join", 80, .after(.homeShelf))
        case .homeUpdate: r(.home, "home.update", 98)
        case .homeGift: r(.home, "home.gift", 96)
        case .homeTables: r(.home, "home.tables", 85, learnedBy: ["home.table"])
        // A table that has waited a day: the anchor is on the first idle card.
        case .homeArchive: r(.home, "home.idleTable", 75, .after(.homeTables), learnedBy: ["home.table.archive"])
        case .homeStreak: r(.home, "home.own", 70)
        case .homeInvite: r(.home, "home.add", 65, .all([.after(.homeStreak), .event(.gameOver)]))
        case .homeRules: r(.home, "home.hero", 60, .opens(2), learnedBy: ["settings.rules", "menu.rules"])
        case .homePeople:
            r(.home, "home.people", 50, .opens(3), audience: TipAudience(passAndPlay: false))
        case .lobbyStart: r(.lobby, "lobby.startReady", 100, learnedBy: ["lobby.start"])
        case .lobbyShare: r(.lobby, "lobby.share", 90)
        case .lobbyAdd: r(.lobby, "lobby.add", 80, learnedBy: ["lobby.seat"])
        case .lobbySeat: r(.lobby, "lobby.openSeat", 70, .after(.lobbyAdd), learnedBy: ["lobby.seat", "lobby.add"])
        case .menuLook: r(.tableMenu, "menu.look", 80)
        case .menuMove: r(.tableMenu, "menu.move", 70)
        case .pouncePick: r(.pounce, "pounce.tile.0", 100, learnedBy: ["pounce.tile", "pounce.send"])
        case .usBell: r(.us, "us.bell", 100)
        case .usTrophies: r(.us, "us.trophies", 80, .after(.usBell))
        case .gearAlerts:
            r(.gear, "settings.reminder", 100, audience: TipAudience(bands: [.teen, .adult]))
        case .tilesMeter: r(.tiles, "tiles.meter", 100)
        case .tilesPlay: r(.tiles, "tiles.play", 95, learnedBy: ["tiles.turn"])
        case .tilesDraw: r(.tiles, "tiles.draw", 90, learnedBy: ["tiles.turn"])
        case .tilesSort: r(.tiles, "tiles.sort", 70, .after(.tilesDraw))
        case .tilesLoupe: r(.tiles, "tiles.set", 60, learnedBy: ["tiles.loupe"])
        }
    }

    private func r(
        _ screen: TipScreen, _ anchor: String, _ priority: Int, _ trigger: TipTrigger = .visible,
        audience: TipAudience = .anyone, learnedBy: Set<String> = []
    ) -> UITipRule {
        UITipRule(
            screen: screen, anchor: anchor, priority: priority, trigger: trigger, audience: audience,
            learnedBy: learnedBy.union([anchor]))
    }

    /// The tips a use of `control` teaches: every tip that names it, shown or not.
    public static func learned(by control: String) -> Set<UITip> {
        Set(allCases.filter { $0.rule.learnedBy.contains(control) })
    }
}

/// What the tips know about the moment: who is looking, at which screen, and what is on it.
public struct TipFacts: Equatable, Sendable {
    public var screen: TipScreen
    /// `Person.id` of whoever the screen is for (the owner, or the face-up seat on a table).
    public var person: String
    public var band: AgeBand?
    /// More than one person plays on this phone.
    public var passAndPlay: Bool
    /// App opens on this phone, this one included.
    public var opens: Int
    /// Tip anchors on screen right now.
    public var visible: Set<String>
    public var events: Set<TipEvent>

    public init(
        screen: TipScreen, person: String, band: AgeBand? = nil, passAndPlay: Bool = false, opens: Int = 1,
        visible: Set<String>, events: Set<TipEvent> = []
    ) {
        self.screen = screen
        self.person = person
        self.band = band
        self.passAndPlay = passAndPlay
        self.opens = opens
        self.visible = visible
        self.events = events
    }
}

/// How many UI tips may show: one at a time, a few per screen visit, per session and per day.
public struct TipPacing: Equatable, Sendable {
    public var perVisit: Int
    public var perSession: Int
    public var perDay: Int

    public init(perVisit: Int = 3, perSession: Int = 4, perDay: Int = 6) {
        self.perVisit = perVisit
        self.perSession = perSession
        self.perDay = perDay
    }

    public static let standard = TipPacing()
}

/// The pure part of UI tips: picks the next one and keeps the counts that pace them. The app
/// supplies the facts, what each person has seen, and today's count from `TipPacingStore`.
public struct TipDirector: Equatable, Sendable {
    public var pacing: TipPacing
    /// The tip up now, and whose it is.
    public private(set) var tip: UITip?
    public private(set) var person: String?
    private var visit: TipScreen?
    private var shownThisVisit = 0
    private var shownThisSession: [String: Int] = [:]

    public init(pacing: TipPacing = .standard) {
        self.pacing = pacing
    }

    /// The best tip for `facts`, ignoring pacing: on this screen, its anchor visible, triggered,
    /// for this person, not seen yet; the highest priority wins, then declaration order.
    public static func candidate(_ facts: TipFacts, seen: Set<UITip>) -> UITip? {
        let fits = UITip.allCases.filter { tip in
            let rule = tip.rule
            return rule.screen == facts.screen && !seen.contains(tip) && facts.visible.contains(rule.anchor)
                && rule.audience.includes(facts) && rule.trigger.holds(facts, seen: seen)
        }
        return fits.max { a, b in
            a.rule.priority != b.rule.priority
                ? a.rule.priority < b.rule.priority
                : UITip.allCases.firstIndex(of: a)! > UITip.allCases.firstIndex(of: b)!
        }
    }

    /// A screen came up: a new visit with its own count.
    public mutating func visit(_ screen: TipScreen) {
        visit = screen
        shownThisVisit = 0
        if let tip, tip.rule.screen != screen { dismiss() }
    }

    /// Feeds the moment. A tip whose anchor left the screen comes down; otherwise, with none up
    /// and room under every limit, the next tip goes up and is returned, to be marked seen.
    /// `today`: tips this person has had today.
    public mutating func update(_ facts: TipFacts, seen: Set<UITip>, today: Int) -> UITip? {
        if visit != facts.screen {
            visit = facts.screen
            shownThisVisit = 0
        }
        if let tip, tip.rule.screen != facts.screen || person != facts.person || !facts.visible.contains(tip.rule.anchor) {
            dismiss()
        }
        guard tip == nil, shownThisVisit < pacing.perVisit,
              shownThisSession[facts.person, default: 0] < pacing.perSession, today < pacing.perDay,
              let next = Self.candidate(facts, seen: seen) else { return nil }
        tip = next
        person = facts.person
        shownThisVisit += 1
        shownThisSession[facts.person, default: 0] += 1
        return next
    }

    /// "Got it", a tap on the bubble, or VoiceOver's escape.
    public mutating func dismiss() {
        tip = nil
        person = nil
    }

    /// A control was used: the tips it teaches, to mark learned; the one up comes down if it's one.
    public mutating func used(_ control: String) -> Set<UITip> {
        let learned = UITip.learned(by: control)
        if let tip, learned.contains(tip) { dismiss() }
        return learned
    }

    /// Tips back on, counts back to zero (settings' Reset tips).
    public mutating func reset() {
        dismiss()
        shownThisVisit = 0
        shownThisSession = [:]
    }
}
