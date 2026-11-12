import PounceKit
import SwiftUI

/// The pass-and-play curtain (spec §5.9, mock `m4-pass`): a dark violet stage with the
/// spotlight on one person's cat, their name once, and a glowing paw button. Pressing and
/// holding the paw for `holdDuration` fills its ring and calls `onRevealed`; letting go early
/// drains the ring and nothing happens, so the last player can't tap through by accident.
/// The hold is a long-press gesture: sliding the finger off the paw, a cancelled touch (a
/// system edge gesture, an interruption) or the app leaving the foreground ends it unrevealed.
/// VoiceOver activates the button at once (its default action).
///
/// The curtain draws nothing private: the face-down cards along the bottom are decoration.
/// Once revealed it stays as it is (ring full, paw inert) until the shell takes it away.
struct PassCurtainView: View {
    let person: Person
    let onRevealed: () -> Void

    /// How long the paw must be held (at the app's pace).
    static let holdDuration: Double = Pace.seconds(0.6)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var done = false
    @State private var appeared = false
    @State private var breathe = false
    @State private var glow = false
    @State private var pressedAt: ContinuousClock.Instant?
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The cat, name and paw are bigger on a roomy (iPad) screen that is tall enough for them.
    private func scale(height: CGFloat) -> CGFloat { sizeClass == .regular && height >= 900 ? 1.3 : 1 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let scale = scale(height: h)
            let catSide = min(w * 0.86, h * 0.4, 360 * scale)
            ZStack {
                // The spotlight pool the cat sits in.
                Ellipse()
                    .fill(RadialGradient(
                        colors: [Palette.magenta.opacity(0.55), Palette.violet.opacity(0.25), .clear],
                        center: .center, startRadius: 0, endRadius: catSide * 0.62))
                    .frame(width: catSide * 1.35, height: catSide * 0.42)
                    .position(x: w / 2, y: h * 0.47 + catSide * 0.44)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)

                Image(ArtName.cat(person.cat, .idle))
                    .resizable()
                    .scaledToFit()
                    .frame(width: catSide, height: catSide)
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
                    .scaleEffect(breathe ? 1.03 : 1, anchor: .bottom)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.5, anchor: .bottom)
                    .groupOpacity(appeared ? 1 : 0)
                    .position(x: w / 2, y: h * 0.47)
                    .accessibilityHidden(true)

                OutlinedText(person.name, size: 54 * scale, fill: Palette.orange, width: 5)
                    .frame(maxWidth: w - 48)
                    .position(x: w / 2, y: h * 0.47 - catSide * 0.5 - 44 * scale)
                    .offset(y: appeared || reduceMotion ? 0 : -60)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityIdentifier("curtain.name")

                holdButton
                    .scaleEffect(scale)
                    .position(x: w / 2, y: h * 0.47 + catSide * 0.5 + 92 * scale)
                    .offset(y: appeared || reduceMotion ? 0 : 120)
                    .groupOpacity(appeared ? 1 : 0)

                CardBacksPeek(width: w)
                    .position(x: w / 2, y: h - 22)
                    .accessibilityHidden(true)
            }
        }
        .background { stage }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("screen-curtain")
        .onAppear(perform: enter)
        .onDisappear(perform: release)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { release() }
        }
    }

    private var stage: some View {
        Palette.night
            .overlay {
                Image(ArtName.curtainStage)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            }
            .clipped()
    }

    // MARK: hold button

    private static let buttonSide: CGFloat = 116
    private static let ringWidth: CGFloat = 12

    private var holdButton: some View {
        let side = Self.buttonSide
        let ring = side + Self.ringWidth * 2 + 10
        return ZStack {
            // Ring track, then the fill that grows while the paw is held.
            Circle()
                .stroke(Palette.ink.opacity(0.6), lineWidth: Self.ringWidth + 6)
                .frame(width: ring, height: ring)
            Circle()
                .stroke(Palette.teal.opacity(0.45), lineWidth: Self.ringWidth)
                .frame(width: ring, height: ring)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(done ? Palette.lime : Palette.teal, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ring, height: ring)
                .shadow(color: Palette.teal.opacity(0.9), radius: 8)

            // The candy disc.
            Circle()
                .fill(Palette.magenta.mix(with: Palette.ink, by: 0.45))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 5))
                .frame(width: side, height: side)
                .offset(y: 7)
            Circle()
                .fill(LinearGradient(
                    colors: [Palette.magenta.mix(with: .white, by: 0.12), Palette.magenta, Palette.magenta.mix(with: Palette.violet, by: 0.35)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(0.5))
                        .frame(width: side * 0.56, height: side * 0.16)
                        .padding(.top, side * 0.09)
                }
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 5))
                .overlay {
                    Image(ArtName.iconHold)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side * 0.56, height: side * 0.56)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
                }
                .frame(width: side, height: side)
                .offset(y: pressing ? 5 : 0)
        }
        .frame(width: ring + 12, height: ring + 12)
        // One glow around the whole button (without the group, every layer casts its own).
        .compositingGroup()
        .shadow(color: Palette.teal.opacity(glow ? 0.95 : 0.5), radius: glow ? 26 : 12)
        .scaleEffect(pressing && !reduceMotion ? 0.95 : 1)
        .animation(.spring(duration: 0.15, bounce: 0.3).paced, value: pressing)
        .contentShape(Circle())
        // `onPressingChanged(false)` comes on lift, on a cancelled touch and when the finger
        // slides further than `maximumDistance`; `perform` only after a full, unbroken hold.
        .onLongPressGesture(
            minimumDuration: Self.holdDuration,
            maximumDistance: Self.buttonSide / 2,
            perform: holdCompleted,
            onPressingChanged: { down in down ? begin() : release() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "Hold to show \(person.name)'s cards",
            comment: "VoiceOver: the pass-the-phone curtain's paw button; activating it shows that person's hand"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
        .accessibilityIdentifier("curtain.hold")
    }

    // MARK: actions

    private func enter() {
        Sound.shared.play(ArtName.Sound.sfxWhoosh, volume: 0.7)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2).paced : .spring(duration: 0.5, bounce: 0.45).paced) {
            appeared = true
        }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).paced) { breathe = true }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).paced) { glow = true }
    }

    /// Finger down on the paw: the ring starts filling.
    private func begin() {
        guard !done, scenePhase == .active else { return }
        pressing = true
        pressedAt = .now
        Haptics.shared.tick()
        Sound.shared.play(ArtName.Sound.sfxTick)
        withAnimation(.linear(duration: Self.holdDuration).paced) { progress = 1 }
    }

    /// Finger up, slid off, touch cancelled or app inactive: too early drains the ring.
    private func release() {
        let wasPressing = pressing
        pressing = false
        let held = pressedAt.map { ContinuousClock.now - $0 >= .seconds(Self.holdDuration * 0.95) } ?? false
        pressedAt = nil
        guard !done, wasPressing else { return }
        if held, scenePhase == .active {
            // A full hold ends the press too, right around `perform`: leave the ring full for
            // it, and drain only if no reveal follows (the finger slid off at the last moment).
            Task { @MainActor in
                try? await Task.sleep(for: Pace.duration(.milliseconds(150)))
                if !done, !pressing { drain() }
            }
            return
        }
        drain()
    }

    private func drain() {
        withAnimation(.easeOut(duration: 0.2).paced) { progress = 0 }
    }

    /// The long press held for `holdDuration` without the finger lifting, sliding off or the
    /// touch being cancelled (the gesture fails for those). Never while the app isn't active.
    private func holdCompleted() {
        guard scenePhase == .active else { return release() }
        complete()
    }

    private func complete() {
        guard !done else { return }
        done = true
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { progress = 1 }
        Haptics.shared.success()
        Sound.shared.play(ArtName.Sound.sfxSparkle)
        onRevealed()
    }
}

/// A row of face-down cards peeking up from the bottom edge, like a hand held low.
private struct CardBacksPeek: View {
    let width: CGFloat

    var body: some View {
        let cardW = min(width / 4.4, 96)
        let cardH = cardW * 90 / 64
        HStack(spacing: -cardW * 0.18) {
            ForEach(0..<5, id: \.self) { i in
                Image(uiImage: CardFaceFactory.backImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cardW, height: cardH)
                    .rotationEffect(.degrees(Double(i - 2) * 7), anchor: .bottom)
                    .offset(y: abs(CGFloat(i - 2)) * 8)
            }
        }
        .frame(width: width, height: cardH)
        .offset(y: cardH * 0.25)
    }
}

#if DEBUG
#Preview("Pass curtain") {
    PassCurtainView(person: Person(id: "p", name: "Mia", cat: 2)) {}
}
#endif
