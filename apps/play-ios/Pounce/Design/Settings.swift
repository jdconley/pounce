import Foundation
import Observation

/// User toggles and push-priming flags, persisted in UserDefaults.
@MainActor @Observable
final class Settings {
    /// The app-wide instance. Under `-uitest-reset` (DEBUG only) it uses a scratch suite wiped
    /// at launch.
    static let shared: Settings = {
        #if DEBUG
        if CommandLine.arguments.contains("-uitest-reset") { return Settings(defaults: freshSuite()) }
        #endif
        return Settings(defaults: .standard)
    }()

    private enum Key {
        static let soundOn = "settings.soundOn"
        static let hapticsOn = "settings.hapticsOn"
        static let pushPrimed = "settings.pushPrimed"
        static let pushDeclinedOnce = "settings.pushDeclinedOnce"
        static let pushReoffered = "settings.pushReoffered"
        static let turnReminder = "settings.turnReminder"
        static let kittenDaily = "settings.kittenDaily"
        static let signInPromptSeen = "settings.signInPromptSeen"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var soundOn: Bool { didSet { defaults.set(soundOn, forKey: Key.soundOn) } }
    var hapticsOn: Bool { didSet { defaults.set(hapticsOn, forKey: Key.hapticsOn) } }
    /// The push priming screen has been shown.
    var pushPrimed: Bool { didSet { defaults.set(pushPrimed, forKey: Key.pushPrimed) } }
    /// The user said "not now" to push once (do not nag again right away).
    var pushDeclinedOnce: Bool { didSet { defaults.set(pushDeclinedOnce, forKey: Key.pushDeclinedOnce) } }
    /// Home's bell offered push again after a "not now" (it only does that once).
    var pushReoffered: Bool { didSet { defaults.set(pushReoffered, forKey: Key.pushReoffered) } }

    /// The local "your turn" reminder, as the person set it; nil until they touch it, when the age
    /// band's default applies (off for a kitten, spec §14.1).
    var turnReminderChoice: Bool? {
        didSet {
            if let turnReminderChoice { defaults.set(turnReminderChoice, forKey: Key.turnReminder) }
            else { defaults.removeObject(forKey: Key.turnReminder) }
        }
    }

    /// A kitten's local daily reminder at 17:00 (spec §14.1): off until they turn it on.
    var kittenDaily: Bool { didSet { defaults.set(kittenDaily, forKey: Key.kittenDaily) } }

    /// Home's "Keep your streak if you change phones" card was answered (signed in or not now).
    var signInPromptSeen: Bool { didSet { defaults.set(signInPromptSeen, forKey: Key.signInPromptSeen) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundOn = defaults.object(forKey: Key.soundOn) as? Bool ?? true
        hapticsOn = defaults.object(forKey: Key.hapticsOn) as? Bool ?? true
        pushPrimed = defaults.bool(forKey: Key.pushPrimed)
        pushDeclinedOnce = defaults.bool(forKey: Key.pushDeclinedOnce)
        pushReoffered = defaults.bool(forKey: Key.pushReoffered)
        turnReminderChoice = defaults.object(forKey: Key.turnReminder) as? Bool
        kittenDaily = defaults.bool(forKey: Key.kittenDaily)
        signInPromptSeen = defaults.bool(forKey: Key.signInPromptSeen)
    }

    #if DEBUG
    private static func freshSuite() -> UserDefaults {
        let name = "com.conleychaos.play.uitest"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }
    #endif
}
