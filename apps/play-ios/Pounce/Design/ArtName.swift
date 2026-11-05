// Asset names used by the UI. Art/manifest.json is the source of truth; this file mirrors it,
// and scripts/check-assets.sh fails if a manifest name is missing here or in the catalog.
import PounceKit

/// Poses drawn for every cat in the roster (`cat{0...7}-{pose}` in the `Cats` atlas).
enum CatPose: String, CaseIterable {
    case idle, awake, away, asleep, leap, terrified, celebrate
}

enum ArtName {
    /// Sprite atlas names (`SKTextureAtlas(named:)`). Sprites inside are addressed by the names below.
    enum Atlas {
        static let cats = "Cats"
        static let cards = "Cards"
        static let table = "Table"
        static let fx = "FX"
    }

    /// Cat roster by index: 0 orange tabby, 1 tuxedo, 2 calico, 3 gray, 4 black, 5 white fluffy,
    /// 6 siamese, 7 tortie. The House Cat bot uses index 3 plus `badge-bot`.
    static let catCount = 8

    /// `cat{index}-{pose}` (160x160 pt, Cats atlas).
    static func cat(_ index: Int, _ pose: CatPose) -> String {
        "cat\(index)-\(pose.rawValue)"
    }

    /// Center cat-face art on a number card (48x48 pt, Cards atlas).
    static func coat(_ c: Coat) -> String {
        switch c {
        case .tabby: "coat-tabby"
        case .tuxedo: "coat-tuxedo"
        case .calico: "coat-calico"
        case .gray: "coat-gray"
        }
    }

    /// Coat glyph under the numeral: stripe / bow tie / three patches / paw (16x16 pt, Cards atlas).
    static func glyph(_ c: Coat) -> String {
        switch c {
        case .tabby: "glyph-tabby"
        case .tuxedo: "glyph-tuxedo"
        case .calico: "glyph-calico"
        case .gray: "glyph-gray"
        }
    }

    // MARK: Cards atlas
    static let cardFace = "card-face"
    static let cardBack = "card-back"
    static let cardYarn = "card-yarn"
    static let cardCucumber = "card-cucumber"
    static let cardGlow = "card-glow"
    static let cardShadow = "card-shadow"

    // MARK: Table atlas
    static let rug = "rug"
    static let towerBase = "tower-base"
    static let towerShelf = "tower-shelf"
    static let towerTop = "tower-top"
    static let shelfBadge = "shelf-badge"
    static let ring = "ring"
    static let ringGlow = "ring-glow"
    static let tray = "tray"
    static let trayGold = "tray-gold"
    static let pawSwipe = "paw-swipe"
    static let crown = "crown"
    static let sunburst = "sunburst"

    // MARK: FX atlas
    static let fxStar = "fx-star"
    static let fxFur = "fx-fur"
    static let fxYarn = "fx-yarn"
    static let fxConfetti = "fx-confetti"
    static let fxSparkle = "fx-sparkle"

    // MARK: Image sets (asset catalog roots)
    static let roomBg = "room-bg"
    static let homeBg = "home-bg"
    static let curtainStage = "curtain-stage"
    static let gameTile = "game-tile"
    static let stateClosed = "state-closed"
    static let stateStalled = "state-stalled"
    static let stateOffline = "state-offline"
    static let stateFull = "state-full"
    static let stateUpdate = "state-update"
    static let pushPriming = "push-priming"
    static let iconPlus = "icon-plus"
    static let iconKeypad = "icon-keypad"
    static let iconShare = "icon-share"
    static let iconQr = "icon-qr"
    static let iconPlay = "icon-play"
    static let iconBack = "icon-back"
    static let iconGear = "icon-gear"
    static let iconPawMenu = "icon-paw-menu"
    static let iconSort = "icon-sort"
    static let iconBell = "icon-bell"
    static let iconCheck = "icon-check"
    static let iconDice = "icon-dice"
    static let iconHome = "icon-home"
    static let iconMove = "icon-move"
    static let iconSoundOn = "icon-sound-on"
    static let iconSoundOff = "icon-sound-off"
    static let iconHapticsOn = "icon-haptics-on"
    static let iconHapticsOff = "icon-haptics-off"
    static let badgePhone = "badge-phone"
    static let badgeRemote = "badge-remote"
    static let badgeBot = "badge-bot"
    static let badgeSkip = "badge-skip"
    static let badgeLaid = "badge-laid"
    static let iconTrophy = "icon-trophy"
    static let iconZzz = "icon-zzz"
    static let iconHold = "icon-hold"
    /// Join keypad backspace.
    static let iconDelete = "icon-delete"
    /// Lobby seat bubble: close the seat.
    static let iconRemove = "icon-remove"
    /// Lobby seat bubble on your own cat: stand up.
    static let iconLeave = "icon-leave"
    /// Lobby seat bubble on your own cat: someone else on this phone sits here.
    static let iconSwap = "icon-swap"

    // MARK: Daily habit (spec §9.6; placeholders until PR 8's art replaces them by name)
    enum Habit {
        /// The Cat Condo by stage 1...10 (300x300 pt). Stage 0 draws no condo.
        static let condos = [
            "condo-1", "condo-2", "condo-3", "condo-4", "condo-5", "condo-6", "condo-7", "condo-8", "condo-9", "condo-10",
        ]
        static func condo(_ stage: Int) -> String? {
            stage >= 1 ? condos[min(stage, condos.count) - 1] : nil
        }

        /// Toys by catalog id (48x48 pt); the ids are the art names.
        static let toys = [
            "toy-yarn-ball", "toy-feather-wand", "toy-cardboard-box", "toy-mouse", "toy-fish", "toy-bell", "toy-laser-dot",
            "toy-catnip-sack", "toy-sock", "toy-bottle-cap", "toy-crinkle-ball", "toy-spring", "toy-ribbon", "toy-paper-bag",
            "toy-pom-pom", "toy-cork", "toy-rainbow-yarn", "toy-glitter-mouse", "toy-silver-bell", "toy-moon-fish",
            "toy-star-wand", "toy-disco-ball", "toy-golden-fish", "toy-golden-mouse",
        ]
        static func toy(_ id: String) -> String { toys.contains(id) ? id : "toy-yarn-ball" }

        /// Card backs (Cards atlas, 64x90 pt). The default violet paw is the classic `card-back`.
        static let backs = [
            "back-yarn-swirl", "back-moonlit-fish", "back-cucumber-chaos", "back-crown", "back-heart-paws", "back-golden-yarn",
        ]
        static func back(_ id: String) -> String { backs.contains(id) ? id : ArtName.cardBack }

        /// Rugs (Table atlas, 360x360 pt). The default is the classic `rug`.
        static let rugs = ["rug-night-sky", "rug-candy-stripe", "rug-fish-pond", "rug-royal-violet"]
        static func rug(_ id: String) -> String { rugs.contains(id) ? id : ArtName.rug }

        /// Any reward id's picture: a toy, back or rug, or the gift box for confetti.
        static func item(_ id: String) -> String {
            if id.hasPrefix("toy-") { return toy(id) }
            if id.hasPrefix("back-") { return back(id) }
            if id.hasPrefix("rug-") { return rug(id) }
            return giftBoxOpen
        }

        static let giftBox = "gift-box"
        static let giftBoxOpen = "gift-box-open"
        /// Today's paw, unlit and lit; both paws (the kept stamp); the mode pictures.
        static let pawGrey = "paw-badge-grey"
        static let pawOne = "paw-badge-one"
        static let pawBoth = "paw-badge-both"
        static let pawNap = "paw-badge-nap"
        static let pawBandage = "paw-badge-bandage"
        static let pawSuitcase = "paw-badge-suitcase"
        /// The Pounce push and Messages card (PR 5).
        static let pounceBell = "pounce-bell"
        /// StandBy and night (PR 6).
        static let catsAsleepCondo = "cats-asleep-condo"
        static let iconPause = "icon-pause"
        static let iconPin = "icon-pin"
        static let iconTrash = "icon-trash"
        static let iconRug = "icon-rug"
        static let iconCloudPlus = "icon-cloud-plus"
        static let iconDays = "icon-days"
        static let iconWeeks = "icon-weeks"
        static let iconReplay = "icon-replay"
        /// Pounce (PR 5): the resting bell, the New game and You pick tiles.
        static let pounceBellAsleep = "pounce-bell-asleep"
        static let pounceNewGame = "pounce-new-game"
        static let pouncePick = "pounce-pick"
        /// "In a bit"; the reminder dials.
        static let iconClock = "icon-clock"
        /// Quiet hours start and end.
        static let iconMoon = "icon-moon"
        static let iconSun = "icon-sun"
        /// Learned reminder time, the weekday and weekend dials, last chance.
        static let iconAuto = "icon-auto"
        static let iconWeekday = "icon-weekday"
        static let iconWeekend = "icon-weekend"
        static let iconLastChance = "icon-last-chance"
    }

    // MARK: Sounds (Resources/Sounds/<name>.caf, 44.1 kHz mono)
    enum Sound {
        static let sfxPop = "sfx-pop"
        static let sfxFlip = "sfx-flip"
        static let sfxBat = "sfx-bat"
        static let sfxThud = "sfx-thud"
        static let sfxNope = "sfx-nope"
        static let sfxSparkle = "sfx-sparkle"
        static let sfxWhoosh = "sfx-whoosh"
        static let sfxScream = "sfx-scream"
        static let sfxLeap = "sfx-leap"
        static let sfxFanfare = "sfx-fanfare"
        static let sfxTick = "sfx-tick"
    }
}
