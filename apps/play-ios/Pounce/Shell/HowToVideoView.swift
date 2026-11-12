import AVKit
import PounceKit
import SwiftUI

/// The top of How to play: the game's video (`GameCatalog.Entry.howTo`, bundled from
/// `Pounce/Resources/HowTo/`). Its poster with a big play button until tapped, then the video
/// inline with the standard controls (full screen is one of them). It never starts by itself.
/// The video has no sound: every step is a caption on screen, and the same steps are written
/// under it.
struct HowToVideoView: View {
    let game: GameCatalog.Entry
    /// The room it has: it is as big as fits in it.
    let bounds: CGSize

    @State private var player: AVPlayer?
    @State private var seconds: Int?

    /// The videos are cut at 496x1080 (`HowTo/beats.json`).
    static let aspect: CGFloat = 496.0 / 1080.0

    private var video: URL? { game.howTo.flatMap { Bundle.main.url(forResource: $0, withExtension: "mp4") } }
    private var poster: UIImage? {
        game.howTo.flatMap { Bundle.main.path(forResource: $0, ofType: "jpg") }.flatMap(UIImage.init(contentsOfFile:))
    }

    var body: some View {
        if let video {
            let height = max(min(bounds.height, bounds.width / Self.aspect), 120)
            content(video)
                .frame(width: (height * Self.aspect).rounded(), height: height.rounded())
                .frame(maxWidth: .infinity)
                .task(id: game.id) {
                    let duration = try? await AVURLAsset(url: video).load(.duration)
                    seconds = duration.map { Int($0.seconds.rounded()) }
                }
                .onDisappear { player?.pause() }
        }
    }

    private func content(_ video: URL) -> some View {
        ZStack {
            if let player {
                InlinePlayer(player: player)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier("rules.video.player")
            } else {
                Button {
                    Haptics.shared.tick()
                    let player = AVPlayer(url: video)
                    player.isMuted = true
                    player.preventsDisplaySleepDuringVideoPlayback = true
                    self.player = player
                    player.play()
                } label: {
                    posterFace
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityHint(Text("Plays the video. The same steps are written below.", comment: "VoiceOver hint on How to play's video"))
                .accessibilityAddTraits(.startsMediaSession)
                .accessibilityIdentifier("rules.video")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.ink, lineWidth: 4))
        .background(RoundedRectangle(cornerRadius: 22).fill(Palette.ink.opacity(0.55)).offset(y: 6))
    }

    /// The poster (the video's title card) with the play button in its clear bottom third.
    private var posterFace: some View {
        GeometryReader { geo in
            let side = min(92, geo.size.width * 0.42)
            ZStack {
                if let poster {
                    Image(uiImage: poster).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Palette.ink
                }
                ZStack {
                    Circle().fill(Palette.ink.opacity(0.5)).offset(y: 5)
                    Circle().fill(Palette.magenta)
                    Circle().strokeBorder(Palette.ink, lineWidth: 5)
                    Image(systemName: "play.fill")
                        .font(.system(size: side * 0.41, weight: .black))
                        .foregroundStyle(.white)
                        .offset(x: side * 0.04)
                }
                .frame(width: side, height: side)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.81)
            }
        }
        .contentShape(Rectangle())
    }

    private var label: Text {
        if let seconds, seconds > 0 {
            let time = Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
            return Text("How to play \(game.title), a video with captions, \(time)", comment: "VoiceOver: How to play's video, e.g. 'How to play Cat Tower, a video with captions, 1 minute, 10 seconds'")
        }
        return Text("How to play \(game.title), a video with captions", comment: "VoiceOver: How to play's video before its length is known")
    }
}

/// AVKit's player view controller inline: its standard controls, full screen from there.
private struct InlinePlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        controller.view.backgroundColor = UIColor(Palette.ink)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
    }
}
