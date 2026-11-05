import PounceKit
import SwiftUI
import WidgetKit

/// The Us widget (spec §11.1): small, medium, and the small one in StandBy.
struct UsWidgetView: View {
    let entry: UsEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var hasBackground

    var body: some View {
        content
            .widgetURL(entry.state.url)
            .containerBackground(for: .widget) { WidgetBackdrop() }
    }

    @ViewBuilder private var content: some View {
        if family == .systemMedium {
            MediumUsView(state: entry.state)
        } else if !hasBackground {
            // StandBy (and anywhere else the system strips the background): the night art.
            StandByUsView(state: entry.state)
        } else {
            SmallUsView(state: entry.state)
        }
    }
}

/// The loud backdrop: violet into magenta under the living-room sky.
struct WidgetBackdrop: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.violet, Palette.magenta], startPoint: .top, endPoint: .bottom)
            ArtImage(ArtName.Habit.widgetBackground, points: family == .systemMedium ? 380 : 180)
                .scaledToFill()
                .opacity(0.55)
            LinearGradient(colors: [.clear, Palette.night.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        }
    }
}

/// The condo with both cats (pose by state), the numeral and today's two paws.
struct SmallUsView: View {
    let state: UsWidgetState

    var body: some View {
        VStack(spacing: 0) {
            if state.kind == .pair {
                PawRow(state: state, numeral: 34, paw: 24)
            }
            CondoScene(state: state)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.label(state)))
    }

    static func label(_ s: UsWidgetState) -> String {
        guard let partner = s.partner else { return s.me?.name ?? "" }
        return "\(s.count) · \(partner.name)"
    }
}

/// Today's two paws around the numeral, with the mode's picture on it (bandage, suitcase, nap).
struct PawRow: View {
    let state: UsWidgetState
    let numeral: CGFloat
    let paw: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            pawImage(lit: state.meIn || state.kept)
            Numeral(value: state.count, size: numeral)
                .overlay(alignment: .topTrailing) { modeMark.offset(x: paw * 0.55, y: -paw * 0.3) }
            pawImage(lit: state.themIn || state.kept)
        }
    }

    private func pawImage(lit: Bool) -> some View {
        ArtImage(lit ? ArtName.Habit.pawOne : ArtName.Habit.pawGrey, points: paw)
            .frame(width: paw, height: paw)
            .widgetAccentable(lit)
            .opacity(lit ? 1 : 0.6)
    }

    @ViewBuilder private var modeMark: some View {
        switch state.mode {
        case .winback: ArtImage(ArtName.Habit.pawBandage, points: paw * 0.8).frame(width: paw * 0.8)
        case .paused: ArtImage(ArtName.Habit.pawSuitcase, points: paw * 0.8).frame(width: paw * 0.8)
        case .napped: ArtImage(ArtName.Habit.pawNap, points: paw * 0.8).frame(width: paw * 0.8)
        case .fresh: ArtImage(ArtName.fxSparkle, points: paw * 0.7).frame(width: paw * 0.7)
        case .normal: EmptyView()
        }
    }
}

/// Both cats on the condo; on an empty widget, your own cat (or the house cat) on the first stage.
struct CondoScene: View {
    let state: UsWidgetState

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cat = side * 0.5
            ZStack(alignment: .bottom) {
                ArtImage(ArtName.Habit.condo(state.condoStage) ?? ArtName.Habit.condos[0], points: side)
                    .frame(width: side, height: side)
                HStack(alignment: .bottom, spacing: -cat * 0.18) {
                    ArtImage(WidgetArt.cat(state.me?.cat ?? 3, state.myPose), points: cat)
                        .frame(width: cat, height: cat)
                    if let partner = state.partner {
                        ArtImage(WidgetArt.cat(partner.cat, state.theirPose), points: cat)
                            .frame(width: cat, height: cat)
                            .scaleEffect(x: -1, y: 1)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }
}

/// StandBy (spec §11.1): both cats asleep on the condo with the numeral; the system tints it red
/// in night mode.
struct StandByUsView: View {
    let state: UsWidgetState

    var body: some View {
        ZStack(alignment: .top) {
            ArtImage(ArtName.Habit.catsAsleepCondo, points: 200)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            if state.kind == .pair {
                Numeral(value: state.count, size: 44)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: SmallUsView.label(state)))
    }
}

/// Medium (spec §11.1): the small widget on the left; up to two shared tables on the right (your
/// bell for your move, their cat for theirs), and the round Pounce button below them.
struct MediumUsView: View {
    let state: UsWidgetState

    var body: some View {
        HStack(spacing: 10) {
            SmallUsView(state: state)
                .frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(state.tables) { table in
                    Link(destination: WidgetLink.table(table.code).url) { TableRow(table: table, partner: state.partner) }
                }
                Spacer(minLength: 0)
                if state.kind == .pair, let pair = state.pair {
                    PounceButton(state: state, pair: pair)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}

struct TableRow: View {
    let table: UsWidgetState.Table
    let partner: StreakView.Partner?

    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: table.name)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if table.mine {
                    ArtImage(ArtName.iconBell, points: 26)
                } else if let partner {
                    ArtImage(WidgetArt.cat(partner.cat, .awake), points: 30)
                }
            }
            .frame(width: 28, height: 28)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background {
            if mode == .fullColor {
                Capsule().fill(table.mine ? Palette.orange : Palette.teal)
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 2.5))
            } else {
                Capsule().fill(.white.opacity(0.18))
            }
        }
    }
}

/// The round Pounce button: the bell sends; then the check (a moon when it landed in quiet
/// hours), the sleeping bell while it rests, or their answer, each for the hour.
struct PounceButton: View {
    let state: UsWidgetState
    let pair: String
    var size: CGFloat = 50

    var body: some View {
        switch state.pounce {
        case .ready:
            Button(intent: PounceIntent(pair: pair)) { face(ArtName.Habit.pounceBell) }
                .buttonStyle(.plain)
        case .sent(let quiet):
            face(ArtName.Habit.pounceBellSent)
                .overlay(alignment: .topLeading) {
                    if quiet { ArtImage(ArtName.Habit.iconMoon, points: size * 0.4).frame(width: size * 0.4) }
                }
        case .resting:
            face(ArtName.Habit.pounceBellAsleep)
        case .answered(.play):
            face(WidgetArt.cat(state.partner?.cat ?? 3, .leap))
        case .answered(.later):
            face(ArtName.Habit.iconClock)
        case .answered(.no):
            face(WidgetArt.cat(state.partner?.cat ?? 3, .asleep))
        }
    }

    private func face(_ name: String) -> some View {
        ArtImage(name, points: size)
            .frame(width: size, height: size)
    }
}
