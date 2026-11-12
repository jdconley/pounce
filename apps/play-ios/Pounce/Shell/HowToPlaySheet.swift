import PounceKit
import SwiftUI

/// How to play, per game (`GameCatalog`): a game picker, the game's video on top
/// (`HowToVideoView`), then its rules in loud cards that follow the video's steps
/// (`HowToGuide`). Cat Tower also lists its ten levels and can bring the first-game tips back.
/// Opens on `game`: Home's chip and gear open Cat Tower, a table's menu opens its own game.
struct HowToPlaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let onClose: () -> Void

    @State private var game: GameCatalog.Entry
    @State private var replayed = false

    init(game: GameCatalog.Entry = GameCatalog.dealt, onClose: @escaping () -> Void) {
        var game = game
        #if DEBUG
        // `-show-rules -rules-game tiles`: open on that game (screenshots).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-rules-game"), args.indices.contains(i + 1), let pick = GameCatalog.entry(id: args[i + 1]) {
            game = pick
        }
        #endif
        _game = State(initialValue: game)
        self.onClose = onClose
    }

    private var guide: HowToGuide { HowToGuide.of(game) }

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
                let roomy = sizeClass == .regular && geo.size.width >= 760
                let width = min(geo.size.width - (roomy ? 64 : 40), roomy ? 1080 : sizeClass == .regular ? 640 : .infinity)
                ScrollView {
                    VStack(spacing: roomy ? 22 : 18) {
                        title
                        if GameCatalog.all.count > 1 { picker }
                        HowToVideoView(game: game, bounds: CGSize(width: width, height: geo.size.height * (roomy ? 0.66 : 0.72)))
                            .id(game.id)
                            .padding(.bottom, 4)
                        if roomy { columns } else { column }
                        if guide.replaysTips { replay }
                    }
                    .padding(.horizontal, roomy ? 32 : 20)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                    .frame(maxWidth: roomy ? 1080 : sizeClass == .regular ? 640 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Palette.night.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-rules")
    }

    private var title: some View {
        OutlinedText(String(localized: "How to play", comment: "Rules sheet title"), size: 34, fill: Palette.orange)
            .accessibilityAddTraits(.isHeader)
    }

    /// One chip per game in the catalog; the chosen one is lit in its own tint.
    private var picker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { chips }
            VStack(spacing: 10) { chips }
        }
    }

    private var chips: some View {
        ForEach(GameCatalog.all) { entry in
            let on = entry.id == game.id
            Button {
                guard !on else { return }
                Haptics.shared.tick()
                withAnimation(.spring(duration: 0.3).paced) { game = entry }
            } label: {
                HStack(spacing: 8) {
                    Text(entry.title)
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                    if !entry.isAvailable {
                        Text("Soon", comment: "How to play: tag on a game that can't be started yet")
                            .font(.system(.caption, design: .rounded, weight: .black))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.lime))
                    }
                }
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(on ? Palette.tint(entry.tint) : Palette.ink.opacity(0.55))
                        .overlay(Capsule().strokeBorder(on ? Palette.ink : Palette.tint(entry.tint), lineWidth: 3))
                        .shadow(color: Palette.ink.opacity(on ? 0.6 : 0), radius: 0, x: 0, y: 3))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityHint(entry.isAvailable ? Text(verbatim: "") : Text("Coming soon", comment: "VoiceOver: a game that can't be started yet"))
            .accessibilityIdentifier("rules.game.\(entry.id)")
        }
    }

    /// A phone: the cards in one column.
    private var column: some View {
        VStack(spacing: 18) {
            ForEach(guide.sections, id: \.title, content: card)
            if guide.showsLevels { levelsCard }
        }
    }

    /// A wide sheet: the cards in two columns, the levels at the bottom of the second.
    private var columns: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(spacing: 18) {
                ForEach(guide.sections.prefix(guide.split), id: \.title, content: card)
            }
            VStack(spacing: 18) {
                ForEach(guide.sections.dropFirst(guide.split), id: \.title, content: card)
                if guide.showsLevels { levelsCard }
            }
        }
    }

    private func card(_ section: HowToGuide.Section) -> some View {
        RulesCard(title: section.title, color: section.color, lines: section.lines)
    }

    private var levelsCard: some View {
        RulesCard(
            title: String(localized: "The ten levels", comment: "Rules sheet: the list of levels"),
            color: Palette.sky,
            lines: Rules.phases.enumerated().map { i, reqs in
                String(localized: "\(i + 1). \(CoachCopy.phase(reqs).capitalizedFirst)", comment: "Rules sheet: one level, e.g. '1. Two sets of 3'")
            })
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
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, 6)
    }
}

/// One loud rules card: a colored header in toy lettering over plain lines.
private struct RulesCard: View {
    let title: String
    let color: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OutlinedText(title, size: 22, lines: 2, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(.body, design: .rounded, weight: .bold))
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
