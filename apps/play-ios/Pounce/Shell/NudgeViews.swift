import PounceKit
import SwiftUI

/// The player card's Nudge button (a person on another phone holds the move): a big orange paw
/// to tap, greyed with when it can go while the turn is too new (or this phone nudged here
/// lately), and lime "Nudge sent" once this turn's went. `state` is read live from the store, so
/// the card changes as the server answers; the wait is shown in whole minutes, never ticking.
struct NudgeButton: View {
    let name: String
    let state: () -> RoomStore.NudgeButton?
    let onNudge: () -> Void
    var scale: CGFloat = 1

    @State private var landed = false

    var body: some View {
        // Wakes every few seconds to move "In 2 min" along and light up when the wait is over.
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if let state = state() {
                button(state, now: context.date)
                    .onChange(of: state == .sent) { _, sent in
                        guard sent else { return }
                        Haptics.shared.success()
                        Sound.shared.play(ArtName.Sound.sfxSparkle)
                        UIAccessibility.post(
                            notification: .announcement,
                            argument: String(localized: "Nudge sent", comment: "VoiceOver: your nudge went"))
                        withAnimation(.spring(duration: 0.4, bounce: 0.6).paced) { landed = true }
                    }
            }
        }
    }

    private func waitEnd(_ state: RoomStore.NudgeButton) -> Date? {
        if case .wait(let until) = state { return until }
        return nil
    }

    private func button(_ state: RoomStore.NudgeButton, now: Date) -> some View {
        let waiting = waitEnd(state).map { $0 > now } ?? false
        let ready = state == .ready || (waitEnd(state) != nil && !waiting)
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.7)
            onNudge()
        } label: {
            HStack(spacing: 10 * scale) {
                Image(state == .sent ? ArtName.Habit.pawBoth : ArtName.Habit.pawOne)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34 * scale, height: 34 * scale)
                    .rotationEffect(.degrees(state == .sent && landed ? -12 : 0))
                    .scaleEffect(state == .sent && landed ? 1.15 : 1)
                    .saturation(ready || state == .sent ? 1 : 0.2)
                VStack(alignment: .leading, spacing: 0) {
                    OutlinedText(title(state), size: 22 * scale, fill: .white, width: 3)
                    if let note = note(state, now: now) {
                        Text(note)
                            .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 22 * scale)
            .padding(.vertical, 10 * scale)
            .frame(minWidth: 200 * scale, minHeight: 56 * scale)
            .background(Capsule().fill(fill(state, ready: ready)).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4)))
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: ready ? 5 : 2)
        }
        // Its own style: `.plain` would dim the lime "Nudge sent"; the wait has its own colors.
        .buttonStyle(Squish())
        .disabled(!ready)
        .accessibilityLabel(label(state, now: now))
        .accessibilityValue(value(state, ready: ready))
        .accessibilityIdentifier("player.nudge")
    }

    private func title(_ state: RoomStore.NudgeButton) -> String {
        state == .sent
            ? String(localized: "Nudge sent", comment: "Player card: your nudge went")
            : String(localized: "Nudge", comment: "Player card: the button that nudges the person whose move it is")
    }

    /// "In 2 min" while waiting (whole minutes, rounded up), nothing otherwise.
    private func note(_ state: RoomStore.NudgeButton, now: Date) -> String? {
        guard case .wait(let until) = state, until > now else { return nil }
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        return String(localized: "In \(minutes) min", comment: "Player card: how soon you can nudge, in whole minutes")
    }

    private func fill(_ state: RoomStore.NudgeButton, ready: Bool) -> Color {
        if state == .sent { return Palette.lime }
        return ready ? Palette.orange : Palette.night.mix(with: .white, by: 0.25)
    }

    private func label(_ state: RoomStore.NudgeButton, now: Date) -> Text {
        if state == .sent { return Text("Nudge sent to \(name)", comment: "VoiceOver: the player card after your nudge went") }
        if let note = note(state, now: now) {
            return Text("Nudge \(name), \(note)", comment: "VoiceOver: the nudge button while you have to wait")
        }
        return Text("Nudge \(name)", comment: "VoiceOver: the button that nudges the person whose move it is")
    }

    private func value(_ state: RoomStore.NudgeButton, ready: Bool) -> String {
        switch state {
        case .sent: "sent"
        case .sending: "sending"
        case .wait where !ready: "wait"
        case .ready, .wait: "ready"
        }
    }
}

/// Squashes a little while pressed; never dims when disabled.
private struct Squish: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12).paced, value: configuration.isPressed)
    }
}

/// On the nudged phone: the nudger's cat leaps in at the top, paw out, with "Mo nudged you", and
/// taps twice. The "Your turn" cue plays again under it.
struct NudgePill: View {
    let name: String
    let cat: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tap = false

    var body: some View {
        HStack(spacing: 8) {
            Image(ArtName.cat(cat, .leap))
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .rotationEffect(.degrees(tap ? -10 : 6), anchor: .bottom)
            Image(ArtName.Habit.pawOne)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .offset(x: tap ? -6 : 2, y: tap ? 2 : -3)
                .rotationEffect(.degrees(tap ? -18 : 0))
            OutlinedText(String(localized: "\(name) nudged you", comment: "Table notice: someone nudged you to take your move"), size: 20)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.orange).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4)))
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name) nudged you. Your move.", comment: "VoiceOver: someone nudged you to take your move"))
        .accessibilityIdentifier("nudge.pill")
        .onAppear {
            guard !reduceMotion else { return }
            // Two gentle paw taps.
            withAnimation(.easeInOut(duration: 0.18).repeatCount(4, autoreverses: true).paced) { tap = true }
        }
    }
}
