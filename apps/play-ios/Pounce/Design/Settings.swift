import Foundation
import Observation

/// User toggles and push-priming flags, persisted in UserDefaults.
@MainActor @Observable
final class Settings {
    /// The app-wide instance. Under `-uitest-reset` it uses a scratch suite wiped at launch.
    static let shared = Settings(
        defaults: CommandLine.arguments.contains("-uitest-reset") ? Settings.freshSuite() : .standard)

    private enum Key {
        static let soundOn = "settings.soundOn"
        static let hapticsOn = "settings.hapticsOn"
        static let pushPrimed = "settings.pushPrimed"
        static let pushDeclinedOnce = "settings.pushDeclinedOnce"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var soundOn: Bool { didSet { defaults.set(soundOn, forKey: Key.soundOn) } }
    var hapticsOn: Bool { didSet { defaults.set(hapticsOn, forKey: Key.hapticsOn) } }
    /// The push priming screen has been shown.
    var pushPrimed: Bool { didSet { defaults.set(pushPrimed, forKey: Key.pushPrimed) } }
    /// The user said "not now" to push once (do not nag again right away).
    var pushDeclinedOnce: Bool { didSet { defaults.set(pushDeclinedOnce, forKey: Key.pushDeclinedOnce) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundOn = defaults.object(forKey: Key.soundOn) as? Bool ?? true
        hapticsOn = defaults.object(forKey: Key.hapticsOn) as? Bool ?? true
        pushPrimed = defaults.bool(forKey: Key.pushPrimed)
        pushDeclinedOnce = defaults.bool(forKey: Key.pushDeclinedOnce)
    }

    private static func freshSuite() -> UserDefaults {
        let name = "com.conleychaos.play.uitest"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }
}
