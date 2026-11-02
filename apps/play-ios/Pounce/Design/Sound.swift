import AVFoundation
import Foundation

/// Plays the app's sound effects. `Sound.shared` is the real one, or under a UI test
/// (`Pace.underTest`) a silent stand-in that never touches the audio session.
@MainActor
protocol SoundPlaying: AnyObject {
    /// Loads every effect up front so the first play has no hitch.
    func preload()
    /// Plays `name` at `volume` (0–1; a quiet variant of an effect, say).
    func play(_ name: String, volume: Float)
}

extension SoundPlaying {
    func play(_ name: String) { play(name, volume: 1) }
}

@MainActor
enum Sound {
    static let shared: any SoundPlaying = Pace.underTest ? SilentSound() : AudioSound()
}

/// Sound effects from a small pool of pre-loaded `AVAudioPlayer`s per effect, so rapid repeats
/// overlap instead of cutting off. The ambient session mixes with the user's music and follows
/// the silent switch.
@MainActor
final class AudioSound: SoundPlaying {
    private static let voicesPerEffect = 3
    private let settings: Settings
    private var pools: [String: [AVAudioPlayer]] = [:]
    private var cursor: [String: Int] = [:]
    private var sessionReady = false

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    func preload() {
        prepareSession()
        let a = ArtName.Sound.self
        for name in [
            a.sfxPop, a.sfxFlip, a.sfxBat, a.sfxThud, a.sfxNope, a.sfxSparkle, a.sfxWhoosh, a.sfxScream,
            a.sfxLeap, a.sfxFanfare, a.sfxTick,
        ] {
            _ = pool(for: name)
        }
    }

    func play(_ name: String, volume: Float) {
        guard settings.soundOn, let players = pool(for: name), !players.isEmpty else { return }
        let i = cursor[name, default: 0] % players.count
        cursor[name] = i + 1
        let player = players[i]
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private func prepareSession() {
        guard !sessionReady else { return }
        sessionReady = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func pool(for name: String) -> [AVAudioPlayer]? {
        if let existing = pools[name] { return existing }
        prepareSession()
        // Xcode copies Resources/Sounds/*.caf flat into the bundle root.
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else { return nil }
        var players: [AVAudioPlayer] = []
        for _ in 0..<Self.voicesPerEffect {
            guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players.append(player)
        }
        pools[name] = players
        return players
    }
}

/// Under a UI test: counts what would have played and plays nothing.
@MainActor
final class SilentSound: SoundPlaying {
    private(set) var played = 0

    func preload() {}

    func play(_ name: String, volume: Float) { played += 1 }
}
