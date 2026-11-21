import PounceKit
import SwiftUI

/// Home's Daily Dish (daily games design §7): today's treats in one candy panel, each showing
/// done or not and your result once done. The header opens the Dish; a treat opens its puzzle
/// (or its end screen once played). At the largest text sizes the treats go two by two.
struct DishBand: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var roomy = false

    private var board: DailyBoard? { model.daily.board }
    private var games: [DailyGameInfo] { DailyHost.shown(board) }

    var body: some View {
        let big = typeSize.isAccessibilitySize
        VStack(spacing: roomy ? 14 : 10) {
            header
            if big {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(Array(stride(from: 0, to: games.count, by: 2)), id: \.self) { i in
                        GridRow {
                            ForEach(games[i..<min(i + 2, games.count)]) { treat($0) }
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: roomy ? 18 : 6) {
                    ForEach(games) { treat($0) }
                }
            }
        }
        .padding(.horizontal, roomy ? 22 : 12)
        .padding(.top, roomy ? 14 : 10)
        .padding(.bottom, roomy ? 18 : 14)
        .frame(maxWidth: .infinity)
        .background { panel }
        .compositingGroup()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Daily Dish", comment: "VoiceOver: Home's daily puzzles"))
        .accessibilityIdentifier("home.dish")
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: roomy ? 32 : 26, style: .continuous)
        return shape
            .fill(LinearGradient(
                colors: [Palette.magenta.mix(with: Palette.violet, by: 0.55), Palette.violet.mix(with: Palette.ink, by: 0.35)],
                startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 5))
            .overlay(shape.strokeBorder(Palette.magenta.mix(with: .white, by: 0.3).opacity(0.6), lineWidth: 2).padding(5))
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
    }

    /// "Daily Dish", the day's number, and how many you've played: a button to the Dish.
    private var header: some View {
        let done = games.filter { board?.mine($0.id)?.result != nil }.count
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            model.tips.used("home.dish")
            model.showDish()
        } label: {
            HStack(spacing: 8) {
                OutlinedText(String(localized: "Daily Dish", comment: "Home: the daily puzzles' title"), size: roomy ? 30 : 22, width: 3)
                    .fixedSize()
                if let number = board?.games.first?.number, number > 0 {
                    Text(verbatim: "No. \(number)")
                        .font(.system(size: roomy ? 17 : 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize()
                }
                Spacer(minLength: 4)
                Text(verbatim: "\(done)/\(games.count)")
                    .font(.system(size: roomy ? 18 : 15, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(done == games.count && done > 0 ? Palette.lime : Palette.yellow))
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 2.5))
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: roomy ? 18 : 15, weight: .black))
                    .foregroundStyle(.white)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Daily Dish, \(done) of \(games.count) played", comment: "VoiceOver: Home's Dish header"))
        .accessibilityHint(Text("Opens the board", comment: "VoiceOver: what Home's Dish header does"))
        .accessibilityIdentifier("home.dish.open")
        .tipTarget("home.dish")
    }

    /// One game: its treat, then your result, "Playing" or "Play".
    private func treat(_ game: DailyGameInfo) -> some View {
        let row = board?.mine(game.id)
        let result = row?.result
        let side: CGFloat = roomy ? 84 : 56
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            model.tips.used("home.dish")
            model.playDaily(game.id)
        } label: {
            VStack(spacing: 6) {
                DailyTreat(game: game, side: side, done: result != nil)
                    .overlay(alignment: .topTrailing) {
                        if row?.playing != nil, result == nil {
                            Circle().fill(Palette.yellow).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
                                .frame(width: side * 0.26, height: side * 0.26)
                        }
                    }
                Text(verbatim: game.title)
                    .font(.system(size: roomy ? 16 : 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                label(result.map(game.short) ?? String(localized: "Play", comment: "Home: a daily puzzle not played yet"), done: result != nil)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: game.title))
        .accessibilityValue(result.map(game.summary) ?? String(localized: "Not played", comment: "VoiceOver: a daily puzzle not played yet"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.dish.\(game.id)")
    }

    private func label(_ text: String, done: Bool) -> some View {
        Text(verbatim: text)
            .font(.system(size: roomy ? 17 : 13, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(done ? .white : Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(minWidth: roomy ? 70 : 50)
            .background(Capsule().fill(done ? Palette.ink.opacity(0.55) : Palette.orange))
            .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 2))
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
