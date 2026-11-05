import PounceKit
import SwiftUI

/// The streak badge in the table's top bar (§10.3), for the top pair whose people both sit here.
/// A streak view from this table's socket stamps it (§9.5): a kept day is a double paw stamp,
/// the numeral rolls up, sparkles and the day's toy arcs from the middle of the table into the
/// badge; your half done is one paw and a small stamp. Under a second, and it never takes a touch.
struct TableStreakBadge: View {
    let badge: StreakBadge
    let stamp: (kind: StreakStamp, serial: Int)?
    /// Where the badge's center is, in this view's space.
    let at: CGPoint
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flyingToy: String?
    @State private var landed = false
    @State private var sparkle = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PawBadge(badge: badge, scale: scale, stamps: stamp?.serial ?? 0)
                    .overlay {
                        if case .dayKept = stamp?.kind {
                            Image(ArtName.Habit.pawBoth)
                                .resizable().scaledToFit()
                                .frame(width: 44 * scale)
                                .keyframeAnimator(initialValue: 0.0, trigger: stamp?.serial ?? 0) { content, t in
                                    content.scaleEffect(0.6 + t * 0.9).opacity(t > 0 ? 1.2 - t : 0)
                                } keyframes: { _ in
                                    LinearKeyframe(1.0, duration: Pace.seconds(0.6))
                                    LinearKeyframe(0.0, duration: 0.01)
                                }
                        }
                    }
                    .position(at)
                if let toy = flyingToy {
                    Image(ArtName.Habit.toy(toy))
                        .resizable().scaledToFit()
                        .frame(width: (landed ? 22 : 64) * scale)
                        .position(landed ? at : CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.45))
                        .opacity(landed && reduceMotion ? 0 : 1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .onChange(of: stamp?.serial) { play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your streak, \(badge.count)", comment: "VoiceOver: the table's streak badge"))
        .accessibilityIdentifier("table.streak")
        .accessibilityValue("\(badge.count)|\(badge.me ? 1 : 0)|\(badge.them ? 1 : 0)|\(badge.kept ? 1 : 0)|\(stamp?.serial ?? 0)")
    }

    private func play() {
        guard let stamp else { return }
        switch stamp.kind {
        case .halfDone:
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
        case .dayKept(let toy):
            Haptics.shared.success()
            Sound.shared.play(ArtName.Sound.sfxSparkle)
            guard let toy else { return }
            landed = false
            flyingToy = toy
            Task {
                try? await Task.sleep(for: Pace.duration(.milliseconds(120)))
                withAnimation(reduceMotion ? .easeOut(duration: 0.3).paced : .timingCurve(0.3, -0.4, 0.6, 1, duration: 0.7).paced) {
                    landed = true
                }
                try? await Task.sleep(for: Pace.duration(.milliseconds(750)))
                flyingToy = nil
            }
        }
    }
}

/// The pill that floats down when someone changes the table's look (§9.4): their cat and the new
/// rug or back. No words.
struct LookPill: View {
    let cat: Int
    let art: String
    let isBack: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(ArtName.cat(cat, .awake)).resizable().scaledToFit().frame(width: 40, height: 40)
            Image(systemName: "arrow.right").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
            Group {
                if isBack {
                    Image(uiImage: CardFaceFactory.backImage(art)).resizable().scaledToFit().frame(width: 30, height: 42)
                } else {
                    Image(art).resizable().scaledToFit().frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.magenta).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4)))
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("The table changed", comment: "VoiceOver: someone changed the table's rug or card back"))
        .accessibilityIdentifier("look.pill")
    }
}
