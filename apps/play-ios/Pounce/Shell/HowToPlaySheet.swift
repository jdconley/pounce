import PounceKit
import SwiftUI

/// How to play Cat Tower: the rules on a few loud cards, the ten phases, and a pill that brings
/// the first-game tips back for everyone on this phone. From Home's gear and the table menu.
struct HowToPlaySheet: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void

    @State private var replayed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CornerHomeButton(label: "Back") { onClose() }
                    .accessibilityIdentifier("rules.close")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            GeometryReader { geo in
                ScrollView {
                    if sizeClass == .regular && geo.size.width >= 760 {
                        roomy
                    } else {
                        VStack(spacing: 18) {
                            title
                            ForEach(sections, id: \.title) { section in
                                RulesCard(title: section.title, color: section.color, lines: section.lines)
                            }
                            phasesCard
                            replay
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 32)
                        .frame(maxWidth: sizeClass == .regular ? 640 : .infinity)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .background(Palette.night.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-rules")
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var title: some View {
        OutlinedText(String(localized: "How to play", comment: "Rules sheet title"), size: 34, fill: Palette.orange)
            .accessibilityAddTraits(.isHeader)
    }

    private var phasesCard: some View {
        RulesCard(
            title: String(localized: "The ten levels", comment: "Rules sheet: the list of levels"),
            color: Palette.sky,
            lines: Rules.phases.enumerated().map { i, reqs in
                String(localized: "\(i + 1). \(CoachCopy.phase(reqs).capitalizedFirst)", comment: "Rules sheet: one level, e.g. '1. Two sets of 3'")
            })
    }

    /// A wide sheet: the rules in two columns (the goal, a turn and groups on the left; special
    /// cards, the end of a round and the phases on the right), the replay pill under both.
    private var roomy: some View {
        let split = 3
        return VStack(spacing: 22) {
            title
            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 18) {
                    ForEach(sections.prefix(split), id: \.title) { section in
                        RulesCard(title: section.title, color: section.color, lines: section.lines)
                    }
                }
                VStack(spacing: 18) {
                    ForEach(sections.dropFirst(split), id: \.title) { section in
                        RulesCard(title: section.title, color: section.color, lines: section.lines)
                    }
                    phasesCard
                }
            }
            replay
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
        .padding(.bottom, 36)
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity)
    }

    private var replay: some View {
        VStack(spacing: 10) {
            PillButton(
                icon: ArtName.iconPlay, color: Palette.magenta, size: .medium, width: 300,
                title: String(localized: "Show the tips again", comment: "Rules sheet: bring the first-game tips back"),
                accessibilityLabel: "Show the tips again"
            ) {
                model.replayTips()
                withAnimation(.spring(duration: 0.3).paced) { replayed = true }
            }
            .accessibilityIdentifier("rules.replay")
            if replayed {
                Text("Tips are back on for everyone on this phone.", comment: "Rules sheet: after the tips were turned back on")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, 6)
    }

    private struct Section {
        let title: String
        let color: Color
        let lines: [String]
    }

    private var sections: [Section] {
        [
            Section(
                title: String(localized: "The goal", comment: "Rules sheet section"), color: Palette.violet,
                lines: [
                    String(localized: "Climb the cat tower. It has ten shelves, one for each level.", comment: "Rules: goal"),
                    String(localized: "Lay down your level in a round to climb a shelf. If you don't, you try it again next round.", comment: "Rules: goal"),
                    String(localized: "The first cat to finish all ten levels wins. If two finish together, the lower score wins.", comment: "Rules: winning"),
                ]),
            Section(
                title: String(localized: "Your turn", comment: "Rules sheet section"), color: Palette.teal,
                lines: [
                    String(localized: "1. Take a card from the deck or the top of the discard pile.", comment: "Rules: turn step"),
                    String(localized: "2. If your trays hold your whole level, lay it down.", comment: "Rules: turn step"),
                    String(localized: "3. Once your level is down, add cards to any laid group, yours or anyone's.", comment: "Rules: turn step"),
                    String(localized: "4. Put one card on the discard pile to end your turn.", comment: "Rules: turn step"),
                ]),
            Section(
                title: String(localized: "Groups", comment: "Rules sheet section"), color: Palette.orange,
                lines: [
                    String(localized: "Set: all the same number, like three 7s.", comment: "Rules: what a set is"),
                    String(localized: "Run: numbers in a row, like 4 5 6 7.", comment: "Rules: what a run is"),
                    String(localized: "One coat: the same cat on every card, any numbers.", comment: "Rules: what a coat group is"),
                ]),
            Section(
                title: String(localized: "Special cards", comment: "Rules sheet section"), color: Palette.magenta,
                lines: [
                    String(localized: "Yarn is wild: it stands in for any number in a set or a run.", comment: "Rules: Yarn"),
                    String(localized: "Cucumber: drop it on another cat to make them skip their next turn. You can't take one from the discard pile.", comment: "Rules: Cucumber"),
                ]),
            Section(
                title: String(localized: "End of a round", comment: "Rules sheet section"), color: Palette.lime,
                lines: [
                    String(localized: "The round ends when someone plays or discards their last card.", comment: "Rules: round end"),
                    String(localized: "Cards left in your hand score points: 5 for 1 to 9, 10 for 10 to 12, 15 for a Cucumber, 25 for Yarn. Low is good.", comment: "Rules: scoring"),
                ]),
            Section(
                title: String(localized: "Ending early", comment: "Rules sheet section"), color: Palette.teal,
                lines: [
                    String(localized: "Forfeit from the paw menu to leave a game. You finish last and everyone else plays on.", comment: "Rules: forfeit"),
                    String(localized: "If someone hasn't moved for 3 days, anyone else can retire their seat from their player card. It counts as a forfeit.", comment: "Rules: retiring an absent player"),
                    String(localized: "The game ends early once the rest of the hand can't change who wins.", comment: "Rules: the early end"),
                ]),
        ]
    }
}

/// One loud rules card: a colored header in toy lettering over plain lines.
private struct RulesCard: View {
    let title: String
    let color: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OutlinedText(title, size: 22)
                .accessibilityAddTraits(.isHeader)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(color.mix(with: Palette.ink, by: 0.35))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(color, lineWidth: 4))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.ink, lineWidth: 2).padding(-1))
        }
        .accessibilityElement(children: .combine)
    }
}

private extension String {
    /// "two sets of 3" -> "Two sets of 3".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
