import AVFoundation
import Foundation

/// The sound effects' files and the audio session, off the caller's actor: making an
/// `AVAudioPlayer` reads and decodes its file, and activating the session waits on the audio
/// server.
public enum SoundFiles {
    /// `voices` players for the bundled `<name>.caf`, each prepared to play; empty when missing.
    @concurrent
    public static func players(named name: String, voices: Int, in bundle: Bundle = .main) async -> sending [AVAudioPlayer] {
        // Xcode copies Resources/Sounds/*.caf flat into the bundle root.
        guard let url = bundle.url(forResource: name, withExtension: "caf") else { return [] }
        var players: [AVAudioPlayer] = []
        for _ in 0..<voices {
            guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players.append(player)
        }
        return players
    }

    #if os(iOS)
    /// The ambient session: mixes with the user's music and follows the silent switch.
    @concurrent
    public static func activateAmbientSession() async {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
    #endif
}
