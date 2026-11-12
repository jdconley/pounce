import PounceKit
import SwiftUI

/// Push priming (spec §10): the calico ringing its bell under a mock "your turn" banner drawn
/// from this player's cat and name. The paw opens the system prompt; the corner button is
/// "not now". Short words say why.
struct PushPrimingView: View {
    let person: Person
    let onAllow: () -> Void
    let onNotNow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var ring = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.72)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 22) {
                MockTurnBanner(person: person)
                    .offset(y: appeared || reduceMotion ? 0 : -260)
                    .padding(.horizontal, 20)
                Image(ArtName.pushPriming)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 290)
                    .background(
                        Circle()
                            .fill(RadialGradient(
                                colors: [Palette.magenta.opacity(0.85), Palette.violet.opacity(0)],
                                center: .center, startRadius: 10, endRadius: 180))
                            .frame(width: 360, height: 360)
                    )
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 8)
                    .wiggle(trigger: ring)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .accessibilityLabel(Text(
                        "Get a notification when it's your turn",
                        comment: "VoiceOver: push priming art, a cat ringing a bell"))
                    .accessibilityAddTraits(.isImage)
                WordLabel(title: "Know when it's your turn", alignment: .center)
                    .padding(.horizontal, 28)
                PillButton(
                    icon: ArtName.iconPawMenu, color: Palette.orange, size: .large, width: 260,
                    title: String(localized: "Turn on", comment: "Push priming: the pill that asks iOS for notifications"), accessibilityLabel: "Turn on notifications"
                ) {
                    onAllow()
                }
                .bounceLoop(active: appeared && !reduceMotion)
                .accessibilityIdentifier("priming.allow")
            }
            // Bigger on a roomy (iPad) screen; the phone keeps its size.
            .scaleEffect(sizeClass == .regular ? 1.25 : 1)
            .opacity(appeared ? 1 : 0)
        }
        .overlay(alignment: .topLeading) {
            CornerHomeButton(icon: ArtName.iconBack, label: "Not now") { onNotNow() }
                .padding(.leading, 16)
                .padding(.top, 4)
                .accessibilityIdentifier("priming.notNow")
                .captioned("Not now")
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.45).paced) { appeared = true }
            Sound.shared.play(ArtName.Sound.sfxSparkle)
        }
        .task {
            // The bell rings now and then while the screen waits.
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.8))
                ring += 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-push-priming")
    }
}

/// A notification-shaped card: the game tile as the app icon, the player's cat and name, and
/// a ringing bell where the words would be.
private struct MockTurnBanner: View {
    let person: Person

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        HStack(spacing: 12) {
            Image(ArtName.gameTile)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.violet))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2.5))
            Image(ArtName.cat(person.cat, .awake))
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
            OutlinedText(person.name, size: 26, fill: .white, width: 3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            Image(ArtName.iconBell)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 380)
        .background(
            shape.fill(LinearGradient(
                colors: [Palette.sky.mix(with: .white, by: 0.2), Palette.sky, Palette.violet],
                startPoint: .top, endPoint: .bottom))
        )
        .overlay(shape.strokeBorder(Palette.ink, lineWidth: 5))
        .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 6)
        .accessibilityElement()
        .accessibilityLabel(Text(
            "Example notification: \(person.name), your turn",
            comment: "VoiceOver: the mock notification on the push priming screen"))
    }
}
