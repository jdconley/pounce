import PounceKit
import SwiftUI

/// The Daily Dish (daily games design §7): today's puzzles as big cards (the number, your result,
/// the best on your board), the board (the Dish overall, then a tab per game), stats for the tab's
/// game, and the board on the TV (Show, and Unlink beside it). A phone stacks it in one column;
/// an iPad on its side puts the cards and stats beside the board.
///
/// Its first visit carries one tip (`ui.dish.first`, on the cards).
struct DishScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var tab: DailyBoardTab = .dish
    @State private var showTV = false
    @State private var unlinking = false

    private var roomy: Bool { sizeClass == .regular }
    private var board: DailyBoard? { model.daily.board }
    private var games: [DailyGameInfo] { DailyHost.shown(board) }

    var body: some View {
        GeometryReader { geo in
            if roomy && Roomy.sideBySide(geo.size) {
                HStack(alignment: .top, spacing: 32) {
                    column { cards; statsSection }
                    column { boardSection; tvRow }
                }
                .padding(.horizontal, 32)
            } else {
                column { cards; boardSection; statsSection; tvRow }
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .background { background }
        .tipHost(.dish, paused: showTV)
        .task { await model.refreshDaily() }
        .task { await model.daily.refreshStats() }
        .onAppear {
            if let focus = model.dishFocus {
                tab = .game(focus)
                model.dishFocus = nil
            }
        }
        .task(id: model.daily.enabled == true) {
            if model.daily.enabled == true { await model.daily.listen() }
        }
        // The server turned the Dish off: back to Home, where it's gone too.
        .onChange(of: model.daily.enabled) { _, on in
            if on == false { model.goHome() }
        }
        .sheet(isPresented: $showTV) {
            ShowOnTVSheet(code: "", board: true, onClose: { showTV = false })
                .environment(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.night)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-dish")
    }

    private func column(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: roomy ? 26 : 20) { content() }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var background: some View {
        ZStack {
            Palette.night
            Image(ArtName.homeBg).resizable().scaledToFill().opacity(0.45).accessibilityHidden(true)
            LinearGradient(colors: [Palette.magenta.opacity(0.3), Palette.night.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    // MARK: the bar

    private var topBar: some View {
        HStack(spacing: 10) {
            CornerHomeButton { model.goHome() }
                .accessibilityIdentifier("dish.back")
            Spacer()
            VStack(spacing: 0) {
                OutlinedText(String(localized: "Daily Dish", comment: "The Daily Dish screen's title"), size: roomy ? 34 : 26, width: 3)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                if let number = board?.games.first?.number, number > 0 {
                    Text(verbatim: "No. \(number)")
                        .font(.system(size: roomy ? 16 : 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Spacer()
            // Balances the back button, so the title sits in the middle.
            Color.clear.frame(width: 52, height: 52)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Palette.night, Palette.night.opacity(0.85), Palette.night.opacity(0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: the cards

    private var cards: some View {
        let columns = roomy && !typeSize.isAccessibilitySize ? 2 : typeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            ForEach(games) { card($0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dish.cards")
        .tipTarget("dish.cards")
    }

    private func card(_ game: DailyGameInfo) -> some View {
        let mine = board?.mine(game.id)
        let result = mine?.result
        let best = board?.best(game.id)
        let tint = DailyArt.tint(game)
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            model.tips.used("dish.play")
            model.playDaily(game.id)
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    DailyTreat(game: game, side: roomy ? 58 : 46, done: result != nil)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: game.title)
                            .font(.system(size: roomy ? 22 : 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let number = board?.game(game.id)?.number, number > 0 {
                            Text(verbatim: "No. \(number)")
                                .font(.system(size: roomy ? 15 : 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    Spacer(minLength: 0)
                }
                Group {
                    if let result {
                        Text(verbatim: game.summary(result))
                            .font(.system(size: roomy ? 26 : 21, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(mine?.playing != nil
                             ? String(localized: "Keep going", comment: "Daily Dish: a puzzle started and not finished")
                             : String(localized: "Play", comment: "Daily Dish: a puzzle not played yet"))
                            .font(.system(size: roomy ? 22 : 18, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Palette.orange).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // The best on your board, when it isn't you.
                HStack(spacing: 6) {
                    if let best, !best.isMe, let r = best.result {
                        Image(systemName: "crown.fill").foregroundStyle(Palette.yellow)
                        Text(verbatim: "\(best.name) \(game.short(r))")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if best?.isMe == true {
                        Image(systemName: "crown.fill").foregroundStyle(Palette.yellow)
                        Text("Best today", comment: "Daily Dish: your result is the best on your board")
                    } else {
                        Text(verbatim: " ")
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: roomy ? 15 : 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(12)
            .background(
                shape.fill(LinearGradient(colors: [tint.mix(with: Palette.ink, by: 0.15), tint.mix(with: Palette.ink, by: 0.45)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Palette.ink, lineWidth: 4))
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5))
            .compositingGroup()
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: game.title))
        .accessibilityValue(result.map(game.summary) ?? String(localized: "Not played", comment: "VoiceOver: a daily puzzle not played yet"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("dish.card.\(game.id)")
    }

    // MARK: the board

    @ViewBuilder private var boardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DailyBoardTabs(games: games, tab: $tab, roomy: roomy)
            if let board {
                DailyBoardRows(board: board, tab: tab, roomy: roomy)
            } else {
                YarnIndicator().frame(maxWidth: .infinity).padding(.vertical, 20)
            }
        }
        .padding(14)
        .background { RoomyPanel(color: Palette.violet) { Color.clear } }
    }

    // MARK: stats

    @ViewBuilder private var statsSection: some View {
        if case .game(let id) = tab, let game = DailyCatalog.info(id) {
            VStack(alignment: .leading, spacing: 10) {
                heading(String(localized: "Your \(game.title)", comment: "Daily Dish: the heading over one game's stats"))
                DailyStatsView(game: game, stats: model.daily.stats[id] ?? .empty, today: board?.date ?? "", roomy: roomy)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                heading(String(localized: "Your streaks", comment: "Daily Dish: the heading over each game's streak"))
                HStack(spacing: 8) {
                    ForEach(games) { game in
                        let stats = model.daily.stats[game.id] ?? .empty
                        Button {
                            withAnimation(.spring(duration: 0.3, bounce: 0.3).paced) { tab = .game(game.id) }
                        } label: {
                            VStack(spacing: 4) {
                                DailyTreat(game: game, side: roomy ? 44 : 34)
                                Text(verbatim: "\(stats.streak)")
                                    .font(.system(size: roomy ? 24 : 20, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.ink.opacity(0.4)))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(game.title) streak \(stats.streak)", comment: "VoiceOver: one daily game's streak"))
                        .accessibilityIdentifier("dish.streak.\(game.id)")
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: roomy ? 22 : 18, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: the TV

    /// Show board on TV, and Unlink beside it once a TV shows it.
    private var tvRow: some View {
        let linked = model.daily.linkedHere || model.daily.tvs > 0
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { showPill; if linked { unlinkPill } }
            VStack(spacing: 10) { showPill; if linked { unlinkPill } }
        }
        .frame(maxWidth: .infinity)
    }

    private var showPill: some View {
        PillButton(
            icon: ArtName.iconTV, color: Palette.sky, size: .medium, width: roomy ? 300 : 230,
            title: String(localized: "Board on TV", comment: "Daily Dish: puts the board on a TV"),
            accessibilityLabel: "Show board on TV"
        ) {
            showTV = true
        }
        .accessibilityIdentifier("dish.tv")
    }

    private var unlinkPill: some View {
        PillButton(
            icon: nil, color: Palette.violet, size: .medium, width: 130,
            title: String(localized: "Unlink", comment: "Daily Dish: takes the board off every TV"),
            accessibilityLabel: "Unlink the TV"
        ) {
            guard !unlinking else { return }
            unlinking = true
            let service = model.daily.service
            let person = model.people.owner?.id
            Task {
                try? await service.unlinkBoard(person: person)
                model.daily.linkedHere = false
                unlinking = false
                await model.refreshDaily()
            }
        }
        .groupOpacity(unlinking ? 0.6 : 1)
        .accessibilityIdentifier("dish.unlink")
    }
}
