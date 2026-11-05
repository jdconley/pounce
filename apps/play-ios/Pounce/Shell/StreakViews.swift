import PounceKit
import SwiftUI

/// The streak badge (Home §10.1, the table's top bar §10.3): today's two paws around the numeral,
/// with the mode's picture on the numeral (bandage, suitcase, nap blanket, a fresh-start sparkle).
/// `stamps` bumps play the paw stamp (§9.5). No words.
struct PawBadge: View {
    let badge: StreakBadge
    var scale: CGFloat = 1
    var stamps = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6 * scale) {
            paw(lit: badge.me || badge.kept)
            numeral
            paw(lit: badge.them || badge.kept)
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 6 * scale)
        .background {
            Capsule()
                .fill(LinearGradient(
                    colors: [Palette.violet.mix(with: .white, by: 0.2), Palette.violet],
                    startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4 * scale))
                .shadow(color: badge.kept ? Palette.orange.opacity(0.8) : .clear, radius: 10 * scale)
        }
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4 * scale)
        .keyframeAnimator(initialValue: 1.0, trigger: stamps) { content, value in
            content.scaleEffect(value)
        } keyframes: { _ in
            if reduceMotion {
                CubicKeyframe(1.0, duration: 0.01)
            } else {
                SpringKeyframe(1.28, duration: Pace.seconds(0.14))
                SpringKeyframe(0.94, duration: Pace.seconds(0.12))
                SpringKeyframe(1.18, duration: Pace.seconds(0.12))
                SpringKeyframe(1.0, duration: Pace.seconds(0.25))
            }
        }
    }

    private func paw(lit: Bool) -> some View {
        Image(lit ? ArtName.Habit.pawOne : ArtName.Habit.pawGrey)
            .resizable().scaledToFit()
            .frame(width: 30 * scale, height: 30 * scale)
            .scaleEffect(lit ? 1.08 : 0.92)
            .animation(.spring(duration: 0.35, bounce: 0.6).paced, value: lit)
    }

    private var numeral: some View {
        OutlinedText(String(badge.count), size: 28 * scale, fill: badge.mode == .fresh ? Palette.sky.mix(with: .white, by: 0.5) : .white,
                     width: 3 * scale)
            .contentTransition(.numericText(value: Double(badge.count)))
            .animation(.spring(duration: 0.4).paced, value: badge.count)
            .fixedSize()
            .overlay(alignment: .topTrailing) { modeMark.offset(x: 14 * scale, y: -10 * scale) }
    }

    @ViewBuilder private var modeMark: some View {
        switch badge.mode {
        case .normal:
            EmptyView()
        case .winback(let kept):
            VStack(spacing: 2 * scale) {
                Image(ArtName.Habit.pawBandage).resizable().scaledToFit().frame(width: 22 * scale)
                HStack(spacing: 3 * scale) {
                    ForEach(0..<2, id: \.self) { i in
                        Circle().fill(i < kept ? Palette.lime : Palette.night)
                            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5 * scale))
                            .frame(width: 7 * scale, height: 7 * scale)
                    }
                }
            }
        case .paused:
            Image(ArtName.Habit.pawSuitcase).resizable().scaledToFit().frame(width: 22 * scale)
        case .napped:
            Image(ArtName.Habit.pawNap).resizable().scaledToFit().frame(width: 22 * scale)
        case .fresh:
            Image(ArtName.fxSparkle).resizable().scaledToFit().frame(width: 20 * scale)
        }
    }

    static func modeName(_ mode: StreakBadge.Mode) -> String {
        switch mode {
        case .normal: "normal"
        case .winback: "winback"
        case .paused: "paused"
        case .napped: "napped"
        case .fresh: "fresh"
        }
    }

    /// The test-facing value: `count|me|them|mode`.
    static func value(_ badge: StreakBadge) -> String {
        "\(badge.count)|\(badge.me ? 1 : 0)|\(badge.them ? 1 : 0)|\(modeName(badge.mode))"
    }
}

/// The little cloud with a plus on the badge (§10.5): keep this streak on all your devices.
struct CloudPlusBubble: View {
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            action()
        } label: {
            Image(ArtName.Habit.iconCloudPlus)
                .resizable().scaledToFit()
                .padding(size * 0.14)
                .frame(width: size, height: size)
                .background(Circle().fill(Palette.sky).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3)))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .bounceLoop(active: true)
        .accessibilityLabel(Text("Keep your streaks on all your devices", comment: "VoiceOver: the sign-in cloud on the streak badge"))
    }
}

/// A round icon button in the Us screen's style.
struct ArtIconButton: View {
    let icon: String
    let color: Color
    var size: CGFloat = 56
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            action()
        } label: {
            Circle()
                .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.3), color], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                .overlay { Image(icon).resizable().scaledToFit().padding(size * 0.2) }
                .frame(width: size, height: size)
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The Cat Condo (§9.1): the stage's art, both cats on it, the toys scattered along its base.
/// A stage that grew since this phone last looked drops in with squash and stretch, and the cats
/// leap onto it. A fresh start (count 0 after a break) shows them curled up asleep.
struct CondoView: View {
    let view: StreakView
    let mine: Int
    var side: CGFloat = 300
    /// The stage this phone last showed for the pair; a bigger one plays the drop.
    var seenStage: Int?
    var onSeen: (Int) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropped = true
    @State private var leap = false

    private var asleep: Bool { view.count == 0 && view.best > 0 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Palette.magenta.opacity(0.35))
                .frame(width: side * 0.95, height: side * 0.18)
                .offset(y: side * 0.02)
            if let condo = ArtName.Habit.condo(view.condoStage) {
                Image(condo)
                    .resizable().scaledToFit()
                    .frame(width: side, height: side)
                    .scaleEffect(x: dropped ? 1 : 0.9, y: dropped ? 1 : 1.15, anchor: .bottom)
                    .offset(y: dropped ? 0 : -side * 0.8)
                    .opacity(dropped ? 1 : 0)
            }
            toys
            HStack(spacing: side * 0.22) {
                cat(mine, pose: asleep ? .asleep : (leap ? .leap : .idle))
                cat(view.partner.cat, pose: asleep ? .asleep : (leap ? .leap : .idle))
            }
            .offset(y: leap ? -side * 0.25 : -side * 0.02)
            if asleep {
                Image(ArtName.fxSparkle)
                    .resizable().scaledToFit()
                    .frame(width: side * 0.16)
                    .offset(x: side * 0.32, y: -side * 0.6)
                    .bounceLoop(active: !reduceMotion)
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("us.condo")
        .accessibilityValue(String(view.condoStage))
        .task(id: view.pair) { await playDrop() }
    }

    private func cat(_ index: Int, pose: CatPose) -> some View {
        Image(ArtName.cat(index, pose))
            .resizable().scaledToFit()
            .frame(width: side * 0.36, height: side * 0.36)
            .shadow(color: Palette.ink.opacity(0.4), radius: 0, x: 0, y: 4)
    }

    /// Up to 12 toys, the newest (today's) first, along the base.
    private var toys: some View {
        let shown = Array(([view.todayToy].compactMap { $0 } + view.toys.reversed().filter { $0 != view.todayToy }).prefix(12))
        return ZStack(alignment: .bottom) {
            ForEach(Array(shown.enumerated()), id: \.element) { i, toy in
                let x = CGFloat(i % 2 == 0 ? 1 : -1) * CGFloat(i / 2 + 1) * side * 0.075
                Image(ArtName.Habit.toy(toy))
                    .resizable().scaledToFit()
                    .frame(width: side * (toy == view.todayToy ? 0.13 : 0.1))
                    .rotationEffect(.degrees(Double((i * 37) % 40) - 20))
                    .offset(x: x, y: -CGFloat((i * 13) % 3) * side * 0.01)
                    .accessibilityElement()
                    .accessibilityIdentifier("us.toy.\(toy)")
            }
        }
    }

    private func playDrop() async {
        let stage = view.condoStage
        defer { onSeen(stage) }
        guard let seenStage, stage > seenStage, !reduceMotion else { return }
        dropped = false
        try? await Task.sleep(for: Pace.duration(.milliseconds(250)))
        Sound.shared.play(ArtName.Sound.sfxThud)
        withAnimation(.spring(duration: 0.55, bounce: 0.5).paced) { dropped = true }
        try? await Task.sleep(for: Pace.duration(.milliseconds(450)))
        Sound.shared.play(ArtName.Sound.sfxLeap)
        Haptics.shared.success()
        withAnimation(.spring(duration: 0.35, bounce: 0.5).paced) { leap = true }
        try? await Task.sleep(for: Pace.duration(.milliseconds(380)))
        withAnimation(.spring(duration: 0.45, bounce: 0.4).paced) { leap = false }
    }
}

/// This week's seven paw dots (§10.2): kept, nap, held, paused, or plain. Never who played.
struct WeekStrip: View {
    let week: [WeekDot]
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, dot in
                Self.dot(dot.state, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("us.week")
        .accessibilityValue(week.map(\.state.rawValue).joined(separator: ","))
        .accessibilityLabel(Text("This week", comment: "VoiceOver: the Us screen's week strip"))
    }

    @ViewBuilder static func dot(_ state: WeekState, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(fill(state))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
            switch state {
            case .kept: Image(ArtName.Habit.pawOne).resizable().scaledToFit().padding(size * 0.14)
            case .nap: Image(ArtName.Habit.pawNap).resizable().scaledToFit().padding(size * 0.14)
            case .paused: Image(ArtName.Habit.pawSuitcase).resizable().scaledToFit().padding(size * 0.16)
            case .held: Circle().fill(.white).frame(width: size * 0.3)
            case .live: Image(ArtName.Habit.pawGrey).resizable().scaledToFit().padding(size * 0.18)
            case .missed, .none: EmptyView()
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if state == .live { Circle().strokeBorder(Palette.orange, lineWidth: 3).padding(-4) }
        }
    }

    private static func fill(_ state: WeekState) -> Color {
        switch state {
        case .kept: Palette.magenta
        case .nap: Palette.sky
        case .held: Palette.teal
        case .paused: Palette.orange.mix(with: Palette.violet, by: 0.3)
        case .live: Palette.violet
        case .missed, .none: Palette.night.mix(with: .white, by: 0.15)
        }
    }
}

/// One of the three stat tiles: an icon and a numeral.
struct StatTile: View {
    let icon: String
    let number: Int
    let color: Color
    let id: String
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 4 * scale) {
            Image(icon).resizable().scaledToFit().frame(width: 30 * scale, height: 30 * scale)
            OutlinedText(String(number), size: 24 * scale, fill: .white, width: 3).fixedSize()
        }
        .frame(width: 92 * scale, height: 84 * scale)
        .background(
            RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: 22 * scale, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4)))
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(id)
        .accessibilityValue(String(number))
    }
}

/// The distance to the next milestone (§9.2): a ring that starts part-filled, with the gift box and
/// the milestone's numeral inside.
struct MilestoneArc: View {
    let count: Int
    let next: Int
    var side: CGFloat = 92

    private var progress: Double {
        let from = StreakCatalog.previousMilestone(before: next)
        let span = max(next - from, 1)
        // Endowed progress: never an empty ring.
        return max(0.12, min(1, Double(count - from) / Double(span)))
    }

    var body: some View {
        ZStack {
            Circle().stroke(Palette.night.mix(with: .white, by: 0.15), lineWidth: side * 0.13)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(LinearGradient(colors: [Palette.lime, Palette.teal], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: side * 0.13, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().strokeBorder(Palette.ink, lineWidth: 3).padding(side * 0.12)
            VStack(spacing: 0) {
                Image(ArtName.Habit.giftBox).resizable().scaledToFit().frame(width: side * 0.36)
                OutlinedText(String(next), size: side * 0.22, fill: .white, width: 2.5).fixedSize()
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("us.arc")
        .accessibilityValue("\(count)/\(next)")
    }
}
