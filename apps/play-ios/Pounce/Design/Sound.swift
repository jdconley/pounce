import AVFoundation
import PounceKit
import Foundation

/// What a sound is for. A phone showing just its cards while a TV shows the table (spec §3,
/// "one table, one sound") keeps its own `ui` sounds and leaves `game` ones to the TV.
enum SoundKind {
    /// This phone's own controls and feedback: a button, a tip, a move this phone was refused.
    case ui
    /// Something that happened in the game (a draw, a hit, a celebration): the table's sound.
    case game
}

/// Plays the app's sound effects. `Sound.shared` is the real one, or under a UI test
/// (`Pace.underTest`) a silent stand-in that never touches the audio session.
@MainActor
protocol SoundPlaying: AnyObject {
    /// Loads every effect up front so the first play has no hitch.
    func preload()
    /// Plays `name` at `volume` (0–1; a quiet variant of an effect, say), unless it is a `game`
    /// sound while `gameMuted`.
    func play(_ name: String, volume: Float, kind: SoundKind)
    /// Game sounds are the TV's (this phone shows just its cards). Set by the table screen.
    var gameMuted: Bool { get set }
}

extension SoundPlaying {
    func play(_ name: String) { play(name, volume: 1, kind: .ui) }
    func play(_ name: String, volume: Float) { play(name, volume: volume, kind: .ui) }
    func play(_ name: String, kind: SoundKind) { play(name, volume: 1, kind: kind) }
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
    private var loading: Set<String> = []
    private var cursor: [String: Int] = [:]
    private var session: Task<Void, Never>?
    var gameMuted = false

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Starts loading every effect, off the main thread (docs/main-thread.md); each is ready a
    /// moment after launch.
    func preload() {
        let a = ArtName.Sound.self
        for name in [
            a.sfxPop, a.sfxFlip, a.sfxBat, a.sfxThud, a.sfxNope, a.sfxSparkle, a.sfxWhoosh, a.sfxScream,
            a.sfxLeap, a.sfxFanfare, a.sfxTick,
        ] {
            load(name)
        }
    }

    /// Plays `name`. One still loading (a moment after launch, or an effect `preload` doesn't
    /// list) is skipped this once and loads for next time.
    func play(_ name: String, volume: Float, kind: SoundKind) {
        guard settings.soundOn, kind == .ui || !gameMuted else { return }
        guard let players = pools[name], !players.isEmpty else {
            load(name)
            return
        }
        let i = cursor[name, default: 0] % players.count
        cursor[name] = i + 1
        let player = players[i]
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private func load(_ name: String) {
        guard pools[name] == nil, !loading.contains(name) else { return }
        loading.insert(name)
        if session == nil { session = Task { await SoundFiles.activateAmbientSession() } }
        let session = session
        Task {
            await session?.value
            let players = await SoundFiles.players(named: name, voices: Self.voicesPerEffect)
            pools[name] = players
            loading.remove(name)
        }
    }
}

/// Under a UI test: counts what would have played and plays nothing.
@MainActor
final class SilentSound: SoundPlaying {
    private(set) var played = 0
    var gameMuted = false

    func preload() {}

    func play(_ name: String, volume: Float, kind: SoundKind) {
        if kind == .ui || !gameMuted { played += 1 }
    }
}
