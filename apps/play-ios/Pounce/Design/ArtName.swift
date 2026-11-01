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
