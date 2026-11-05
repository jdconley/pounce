import PounceKit
import SwiftUI

/// Opening a milestone gift (§9.5), full screen: the box wiggles, then bursts; the reward spins
/// in on a sunburst; both cats strike their celebrate pose; a check puts it away. With Reduce
/// Motion everything fades instead. `open` tells the server while the box wiggles.
struct GiftReveal: View {
    let gift: StreakView.Gift
    let mine: Int
    let theirs: Int
    let open: @MainActor () async -> Bool
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var stage = 0  // 0 wiggle, 1 burst, 2 reward, 3 done
    @State private var wiggles = 0
    @State private var turned = false

    private var scale: CGFloat { sizeClass == .regular ? 1.4 : 1 }

    var body: some View {
        ZStack {
            Palette.night.opacity(0.92).ignoresSafeArea()
            Image(ArtName.sunburst)
                .resizable().scaledToFit()
                .frame(width: 440 * scale)
                .rotationEffect(.degrees(turned ? 120 : 0))
                .scaleEffect(stage >= 1 ? 1 : 0.2)
                .opacity(stage >= 1 ? 1 : 0)
                .accessibilityHidden(true)
            HStack(spacing: 150 * scale) {
                Image(ArtName.cat(mine, stage >= 2 ? .celebrate : .awake)).resizable().scaledToFit().frame(width: 120 * scale)
                Image(ArtName.cat(theirs, stage >= 2 ? .celebrate : .awake)).resizable().scaledToFit().frame(width: 120 * scale)
            }
            .offset(y: 170 * scale)
            if stage < 1 {
                Image(ArtName.Habit.giftBox)
                    .resizable().scaledToFit()
                    .frame(width: 200 * scale)
                    .wiggle(trigger: wiggles)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
            } else if stage == 1 {
                Image(ArtName.Habit.giftBoxOpen)
                    .resizable().scaledToFit()
                    .frame(width: 220 * scale)
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
            }
            if stage >= 2 {
                Image(ArtName.Habit.item(gift.item))
                    .resizable().scaledToFit()
                    .frame(width: (gift.item.hasPrefix("back-") ? 130 : 200) * scale)
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
                    .transition(reduceMotion ? .opacity : .modifier(active: Spin(angle: -540, scale: 0.1), identity: Spin(angle: 0, scale: 1)))
                    .offset(y: -20 * scale)
            }
            if stage >= 3 {
                VStack {
                    Spacer()
                    PillButton(icon: ArtName.iconCheck, color: Palette.teal, size: .large, width: 140,
                               accessibilityLabel: "Done", action: onDone)
                        .accessibilityIdentifier("gift.done")
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gift.reveal")
        .accessibilityValue(stage >= 2 ? gift.item : "")
        .task { await play() }
    }

    private func play() async {
        let open = open
        let opened = Task { @MainActor in await open() }
        for _ in 0..<3 where !reduceMotion {
            wiggles += 1
            Haptics.shared.tick()
            try? await Task.sleep(for: Pace.duration(.milliseconds(320)))
        }
        _ = await opened.value
        Sound.shared.play(ArtName.Sound.sfxPop)
        Haptics.shared.thump()
        withAnimation(.spring(duration: 0.4, bounce: 0.5).paced) { stage = 1 }
        if !reduceMotion { withAnimation(.easeOut(duration: 6).paced) { turned = true } }
        try? await Task.sleep(for: Pace.duration(.milliseconds(380)))
        Sound.shared.play(ArtName.Sound.sfxFanfare)
        Haptics.shared.success()
        withAnimation(reduceMotion ? .easeIn(duration: 0.3).paced : .spring(duration: 0.8, bounce: 0.45).paced) { stage = 2 }
        try? await Task.sleep(for: Pace.duration(.milliseconds(700)))
        withAnimation(.spring(duration: 0.4).paced) { stage = 3 }
    }
}

/// The reward's way in: turning and growing.
private struct Spin: ViewModifier {
    let angle: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(angle)).scaleEffect(scale).opacity(scale < 0.5 ? 0 : 1)
    }
}
