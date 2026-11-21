import PounceKit
import SwiftUI

/// Tonight's board (daily games design §8): the Daily Dish board a phone linked, live, read from
/// across the room. The Dish on the left, a card per game on the right, a cheer when a result
/// lands, and the card that offers to watch a run. The web TV's `TvBoard`.
struct BoardView: View {
    let model: TVModel
    let board: TVBoard

    var body: some View {
        let state = board.state
        ZStack {
            if let watching = state.watching {
                WatchHost(watching: watching, frame: state.frames[watching.player], ended: state.ended) {
                    Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
                    board.stopWatching()
                }
                .transition(.opacity)
            } else {
                content(state)
                    .transition(.opacity)
            }
            if let offer = state.offer, state.watching == nil, model.menu == .closed {
                WatchCard(offer: offer, watch: { board.watch() }, notNow: { board.notNow() })
                    .id("\(offer.player)\(offer.until.timeIntervalSince1970)")
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: state.offer)
        .animation(.easeInOut(duration: 0.3), value: state.watching)
        .overlay(alignment: .topLeading) {
            if board.everConnected, !board.online { TVReconnecting() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tv.board")
        #if DEBUG
        // The board is gameplay for the frame gates, as a table is.
        .onAppear { MainThreadWatchdog.shared?.screen(true) }
        .onDisappear { MainThreadWatchdog.shared?.screen(false) }
        #endif
    }

    private func content(_ state: TVBoardState) -> some View {
        HStack(alignment: .top, spacing: 36) {
            DishColumn(board: state.board, cheer: state.cheer, connecting: !board.everConnected)
                .frame(width: 600)
            // Left of the menu's paw (top right), so nothing overlaps it: six rows need the card's
            // full height, so its room comes from the side.
            Games(games: state.board?.games ?? [], cheer: state.cheer)
                .padding(.trailing, 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "Monday, November 23": the board's own day.
func boardDay(_ date: String) -> String {
    let parse = DateFormatter()
    parse.locale = Locale(identifier: "en_US_POSIX")
    parse.timeZone = TimeZone(identifier: "UTC")
    parse.dateFormat = "yyyy-MM-dd"
    guard let day = parse.date(from: date) else { return date }
    let show = DateFormatter()
    show.timeZone = TimeZone(identifier: "UTC")
    show.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
    return show.string(from: day)
}

private struct DishColumn: View {
    let board: DailyBoard?
    let cheer: TVBoardState.Cheer?
    let connecting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OutlinedText(String(localized: "Tonight's board", comment: "TV: the Daily Dish board's title"), size: 76, width: 5, alignment: .leading)
                .fixedSize()
            Text(board.map { boardDay($0.date) } ?? " ")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.yellow)
                .padding(.top, 6)
                .padding(.bottom, 28)
            if let rows = board?.dish.rows, !rows.isEmpty {
                VStack(spacing: 14) {
                    ForEach(rows.prefix(7), id: \.player) { row in
                        let cheering = cheer?.player == row.player
                        // A new view when it starts cheering, so its entrance plays.
                        DishLine(row: row, first: row.rank == 1, cheering: cheering)
                            .id(cheering ? "\(row.player)-cheer" : row.player)
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(ArtName.cat(0, .asleep))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                    OutlinedText(
                        connecting
                            ? String(localized: "Finding your board", comment: "TV board: before the board arrives")
                            : String(localized: "Nobody has played yet", comment: "TV board: a board with no results today"),
                        size: 48, width: 4, lines: 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        }
    }
}

private struct DishLine: View {
    let row: DailyDishRow
    let first: Bool
    let cheering: Bool

    var body: some View {
        HStack(spacing: 16) {
            RankDisc(rank: row.rank)
            Image(ArtName.cat(row.cat % ArtName.catCount, .idle))
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text(row.name)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(first ? Palette.ink : .white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: -10) {
                ForEach(row.crowns.prefix(4), id: \.self) { _ in
                    Image(ArtName.crown).resizable().scaledToFit().frame(width: 48, height: 48)
                }
            }
            Text("\(row.points)")
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 84)
                .padding(.horizontal, 12)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4))
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.vertical, 8)
        .frame(minHeight: 96)
        .background(RowFace(colors: first ? [Color(hex: 0xFFE066), Color(hex: 0xFFB400)] : [Color(hex: 0x9D63FF), Color(hex: 0x6A22E0)]))
        .cheer(cheering, from: -700)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.rank). \(row.name), \(row.points) points")
        .accessibilityIdentifier("tv.board.dish.\(row.player)")
    }
}

private struct Games: View {
    let games: [DailyGameBoard]
    let cheer: TVBoardState.Cheer?

    /// One game fills the space, two sit side by side, three or four in a 2 x 2 grid, five or six (a
    /// test server's extra game) in 2 x 3. Each card shows up to six people, its rows as tall as its
    /// height allows.
    var body: some View {
        GeometryReader { g in
            let shown = Array(games.prefix(6))
            let columns = shown.count <= 1 ? 1 : 2
            let rows = max(1, (shown.count + columns - 1) / columns)
            let gap: CGFloat = 32
            let w = (g.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let h = (g.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            // One row height for every card, as if each held a whole family, so cards line up.
            let rowH = GameCard.rowHeight(cardHeight: h, more: games.contains { $0.rows.count > TVBoardState.rowsShown })
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { c in
                            let i = r * columns + c
                            if i < shown.count {
                                GameCard(game: shown[i], cheer: cheer, rowHeight: rowH)
                                    .frame(width: w, height: h)
                            } else {
                                Color.clear.frame(width: w, height: h)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct GameCard: View {
    let game: DailyGameBoard
    let cheer: TVBoardState.Cheer?
    /// Each row's height (`rowHeight(cardHeight:more:)`).
    let rowHeight: CGFloat

    private static let title: CGFloat = 56
    private static let more: CGFloat = 40
    private static let padding: CGFloat = 32
    static let gap: CGFloat = 8

    /// The row height that fits six rows in a card `cardHeight` tall, with room for "+N more"
    /// when any card needs it: up to 80, never under 52 (its words stay at 28 or more).
    static func rowHeight(cardHeight: CGFloat, more: Bool) -> CGFloat {
        let rows = CGFloat(TVBoardState.rowsShown)
        let free = cardHeight - padding - title - gap - (more ? Self.more + gap : 0) - gap * (rows - 1)
        return min(80, max(52, free / rows))
    }

    var body: some View {
        let shown = TVBoardState.visibleRows(game)
        let rowH = rowHeight
        VStack(alignment: .leading, spacing: Self.gap) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                OutlinedText(TVBoardState.title(game.game), size: 48, width: 4, alignment: .leading)
                    .fixedSize()
                if game.number > 0 {
                    Text("#\(game.number)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.yellow)
                }
            }
            if game.rows.isEmpty {
                Text("Nobody yet", comment: "TV board: a game nobody has played today")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                VStack(spacing: Self.gap) {
                    ForEach(shown.rows, id: \.player) { row in
                        let cheering = cheer?.player == row.player && cheer?.game == game.game
                        GameRow(row: row, game: game.game, cheering: cheering, height: rowH)
                            .id(cheering ? "\(row.player)-cheer" : row.player)
                    }
                }
            }
            if shown.more > 0 {
                Text("+\(shown.more) more", comment: "TV board: how many more people played this game than the card shows")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Palette.ink.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(Palette.ink, lineWidth: 6))
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TVBoardState.title(game.game))
        .accessibilityIdentifier("tv.board.game.\(game.game)")
    }
}

private struct GameRow: View {
    let row: DailyBoardRow
    let game: String
    let cheering: Bool
    /// The row's height (52 to 80): everything in it scales with it, words never under 28.
    var height: CGFloat = 80
    @State private var leap = false

    private var words: CGFloat { min(42, max(30, height * 0.56)) }
    private var disc: CGFloat { min(58, max(42, height - 14)) }
    private var cat: CGFloat { min(72, max(44, height - 6)) }

    var body: some View {
        HStack(spacing: 12) {
            if row.playing != nil {
                Image(ArtName.iconPlay)
                    .resizable()
                    .scaledToFit()
                    .padding(disc * 0.18)
                    .frame(width: disc, height: disc)
                    .background(Circle().fill(Palette.teal))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
            } else {
                RankDisc(rank: row.rank, side: disc)
            }
            Image(ArtName.cat(row.cat % ArtName.catCount, cheering ? .leap : row.playing != nil ? .awake : .idle))
                .resizable()
                .scaledToFit()
                .frame(width: cat, height: cat)
                .offset(y: leap ? -46 : 0)
                .rotationEffect(.degrees(leap ? -12 : 0))
                .scaleEffect(leap ? 1.18 : 1)
            Text(row.name)
                .font(.system(size: words, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let result = row.result {
                HStack(spacing: 10) {
                    if result.hints > 0 {
                        Text("Hint", comment: "TV board: a result that used a hint")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.orange))
                            .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3))
                    }
                    Text(TVBoardState.resultWords(result))
                        .font(.system(size: result.finished ? words : max(28, words - 6), weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(result.finished ? .white : .white.opacity(0.9))
                }
                .fixedSize()
            } else if let playing = row.playing {
                HStack(spacing: 12) {
                    Capsule()
                        .fill(Palette.ink.opacity(0.5))
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(Palette.yellow).frame(width: g.size.width * playing.progress)
                            }
                        }
                        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3))
                        .frame(width: 110, height: 24)
                        .animation(.easeOut(duration: 0.6), value: playing.progress)
                }
                .fixedSize()
                .accessibilityHidden(true)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 18)
        .frame(height: height)
        .background(RowFace(colors: row.playing != nil ? [Color(hex: 0x2AD8CB), Color(hex: 0x00A094)] : [Color(hex: 0x9D63FF), Color(hex: 0x6A22E0)]))
        .cheer(cheering)
        .onAppear {
            guard cheering else { return }
            withAnimation(.easeOut(duration: 0.35).delay(0.2)) { leap = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.6)) { leap = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(cheering ? "cheer" : "")
        .accessibilityIdentifier("tv.board.row.\(game).\(row.player)")
    }

    private var label: String {
        guard let result = row.result else { return "\(row.name), playing" }
        let hints = result.hints > 0 ? ", \(result.hints) hint\(result.hints > 1 ? "s" : "")" : ""
        return "\(row.rank.map { "\($0). " } ?? "")\(row.name), \(TVBoardState.resultWords(result))\(hints)"
    }
}

private struct RankDisc: View {
    let rank: Int?
    var side: CGFloat = 58

    var body: some View {
        let fill: Color = switch rank {
        case 1: Palette.yellow
        case 2: Color(hex: 0xD9E2F2)
        case 3: Color(hex: 0xF0A35E)
        default: Color(hex: 0x9D63FF)
        }
        Text(rank.map(String.init) ?? "")
            .font(.system(size: max(28, side * 0.62), weight: .black, design: .rounded))
            .foregroundStyle(Palette.ink)
            .frame(width: side, height: side)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
    }
}

/// A row's face: a rounded slab with an ink rim and a drop.
private struct RowFace: View {
    let colors: [Color]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        shape.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 5))
            .background(shape.fill(Palette.ink).offset(y: 8))
    }
}

private struct Cheer: ViewModifier {
    let on: Bool
    /// Where it slides in from: the right inside a game's card, the left for the Dish (off the
    /// screen's edge, never across the cards).
    var from: CGFloat = 420
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).inset(by: -8).strokeBorder(Palette.yellow, lineWidth: 6).opacity(on ? 1 : 0))
            .compositingGroup()
            .offset(x: on && !arrived ? from : 0)
            .opacity(on && !arrived ? 0 : 1)
            .onAppear {
                guard on else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { arrived = true }
            }
    }
}

private extension View {
    /// A result just landed: the row slides in, ringed.
    func cheer(_ on: Bool, from: CGFloat = 420) -> some View { modifier(Cheer(on: on, from: from)) }
}
