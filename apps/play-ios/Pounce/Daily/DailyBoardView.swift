import PounceKit
import SwiftUI

/// Which board the Dish shows: the Dish overall, or one game's.
enum DailyBoardTab: Hashable {
    case dish
    case game(String)
}

/// The tabs over the board: "Dish", then one per game. Scrolls sideways when they don't fit.
struct DailyBoardTabs: View {
    let games: [DailyGameInfo]
    @Binding var tab: DailyBoardTab
    var roomy = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(String(localized: "Dish", comment: "Daily Dish board: the overall tab"), color: Palette.yellow, tab: .dish, id: "dish.tab.dish")
                ForEach(games) { game in
                    chip(game.title, color: DailyArt.tint(game), tab: .game(game.id), id: "dish.tab.\(game.id)")
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dish.tabs")
    }

    private func chip(_ title: String, color: Color, tab: DailyBoardTab, id: String) -> some View {
        let on = self.tab == tab
        return Button {
            Haptics.shared.tick()
            withAnimation(.spring(duration: 0.3, bounce: 0.3).paced) { self.tab = tab }
        } label: {
            Text(verbatim: title)
                .font(.system(size: roomy ? 19 : 15, weight: .black, design: .rounded))
                .foregroundStyle(on ? Palette.ink : .white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(on ? color : Palette.ink.opacity(0.45)))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3))
                .compositingGroup()
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// One board: ranked rows of people and their results, best first. Playing rows follow with
/// their progress. Nobody who hasn't played appears, and there is no "last".
struct DailyBoardRows: View {
    let board: DailyBoard
    let tab: DailyBoardTab
    var roomy = false

    var body: some View {
        VStack(spacing: 8) {
            switch tab {
            case .dish:
                if board.dish.shown.isEmpty {
                    empty
                } else {
                    ForEach(board.dish.shown) { dishRow($0) }
                }
            case .game(let id):
                let rows = board.game(id)?.rows ?? []
                if rows.isEmpty {
                    empty
                } else {
                    ForEach(rows) { gameRow($0, game: DailyCatalog.info(id)) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dish.board")
    }

    private var empty: some View {
        Text("Nobody yet. Be the first.", comment: "Daily Dish board: no results yet")
            .font(.system(size: roomy ? 20 : 16, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .accessibilityIdentifier("dish.board.empty")
    }

    private func dishRow(_ row: DailyDishRow) -> some View {
        line(rank: row.rank, cat: row.cat, name: row.name, me: row.isMe, id: "dish.row.\(row.player)") {
            // One crown, and how many games were won when more than one: the name keeps its room.
            if !row.crowns.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: roomy ? 16 : 13, weight: .black))
                        .foregroundStyle(Palette.yellow)
                        .shadow(color: Palette.ink, radius: 0, x: 1, y: 1)
                    if row.crowns.count > 1 {
                        Text(verbatim: "\(row.crowns.count)")
                            .font(.system(size: roomy ? 15 : 12, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.yellow)
                    }
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Won \(row.crowns.count)", comment: "VoiceOver: how many daily games someone won today"))
            }
            score(String(row.points), unit: String(localized: "pts", comment: "Daily Dish board: points, short"))
        }
    }

    private func gameRow(_ row: DailyBoardRow, game: DailyGameInfo?) -> some View {
        line(rank: row.rank, cat: row.cat, name: row.name, me: row.isMe, id: "dish.row.\(row.player)") {
            if let result = row.result, let game {
                mark(result)
                score(game.short(result), unit: nil)
            } else if let playing = row.playing {
                ProgressRing(progress: playing.progress, side: roomy ? 30 : 24)
                Text("Playing", comment: "Daily Dish board: someone is playing this puzzle now")
                    .font(.system(size: roomy ? 17 : 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.yellow)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// Solved, missed or hinted: a shape, not a color alone.
    @ViewBuilder private func mark(_ result: DailyResult) -> some View {
        if result.hints > 0 {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: roomy ? 15 : 12, weight: .black))
                .foregroundStyle(Palette.yellow)
                .accessibilityLabel(Text("Hinted", comment: "VoiceOver: a daily result that used a hint"))
        }
        if !result.outcome.finished {
            Image(systemName: "moon.fill")
                .font(.system(size: roomy ? 15 : 12, weight: .black))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityLabel(Text("Not solved", comment: "VoiceOver: a daily result that wasn't solved"))
        }
    }

    private func score(_ text: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: text)
                .font(.system(size: roomy ? 22 : 18, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            if let unit {
                Text(verbatim: unit)
                    .font(.system(size: roomy ? 14 : 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// A row: the rank, the cat, the name (it gives way, never the result), then `trailing`.
    private func line(rank: Int?, cat: Int, name: String, me: Bool, id: String, @ViewBuilder trailing: () -> some View) -> some View {
        let side: CGFloat = roomy ? 46 : 38
        return HStack(spacing: 10) {
            RankBadge(rank: rank, side: side * 0.8)
            Image(ArtName.cat(cat, .idle))
                .resizable().scaledToFit()
                .frame(width: side, height: side)
                .accessibilityHidden(true)
            Text(verbatim: name)
                .font(.system(size: roomy ? 20 : 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Spacer(minLength: 4)
            trailing()
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(me ? Palette.magenta.opacity(0.55) : Palette.ink.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(me ? Palette.magenta : Palette.ink, lineWidth: 2.5)))
        .compositingGroup()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// A place: gold, silver and bronze for the first three, plain after. Nil (playing): no number.
struct RankBadge: View {
    let rank: Int?
    let side: CGFloat

    var body: some View {
        let color: Color =
            switch rank {
            case 1: Palette.yellow
            case 2: Palette.sky
            case 3: Palette.orange
            default: Palette.ink.opacity(0.5)
            }
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2.5))
            .overlay {
                if let rank {
                    Text(verbatim: "\(rank)")
                        .font(.system(size: side * 0.5, weight: .black, design: .rounded))
                        .foregroundStyle(rank <= 3 ? Palette.ink : .white)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: side, height: side)
            .accessibilityLabel(rank.map { Text("Place \($0)", comment: "VoiceOver: a place on the daily board") } ?? Text(verbatim: ""))
    }
}

/// Spoiler-free progress, 0 to 1, as a ring.
struct ProgressRing: View {
    let progress: Double
    let side: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Palette.ink.opacity(0.5), lineWidth: side * 0.18)
            Circle()
                .trim(from: 0, to: max(0.04, min(1, progress)))
                .stroke(Palette.yellow, style: StrokeStyle(lineWidth: side * 0.18, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: side, height: side)
        .accessibilityLabel(Text("\(Int((progress * 100).rounded())) percent", comment: "VoiceOver: how far someone is in a daily puzzle"))
    }
}
