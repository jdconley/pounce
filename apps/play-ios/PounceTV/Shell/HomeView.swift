import PounceKit
import SwiftUI

/// The TV's home: across the top, the link a phone scans (or types the code of) to put its table,
/// or its Daily Dish board, here; under it a shelf of posters, one per game, each making a table
/// with this TV as its screen, and Tonight's board while the server has the Dish on. The remote
/// moves along the shelf left to right. Nothing is typed on the TV. Menu here leaves the app, as
/// tvOS users expect (or closes the board's link panel).
///
/// Sized for the TV's 1920x1080 points inside its safe area (80 at the sides, 60 at the top and
/// bottom): the link row and the shelf take about 930 of the 960 between. The shelf spans the 1760
/// across (`TVShelf`): four posters of 404 with 48 between fill it, and five or more scale every
/// poster down together (art, name, pill and gaps) to fit the same span, so the focus grow (5%)
/// still lands in the safe area's margin.
struct HomeView: View {
    let model: TVModel
    @FocusState private var focus: String?

    var body: some View {
        VStack(spacing: 44) {
            link
            posters
                .focusSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if model.homeOffline { TVReconnecting() }
        }
        .disabled(model.boardLinkShown)
        .overlay {
            if model.boardLinkShown {
                BoardLinkView(model: model)
                    .compositingGroup()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.boardLinkShown)
        .onChange(of: model.boardLinkShown) { _, shown in
            // Back from the board's link: the remote lands where it was, on its poster.
            guard !shown else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                focus = "board"
            }
        }
        .defaultFocus($focus, GameCatalog.catTower.id)
    }

    /// What to do, and the code to type, beside the QR.
    private var link: some View {
        HStack(alignment: .center, spacing: 72) {
            VStack(alignment: .leading, spacing: 30) {
                OutlinedText(
                    String(localized: "Scan with your phone to put your table here", comment: "TV home: over the QR a phone scans to link its table"),
                    size: 58, width: 4, lines: 2, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                TVCode(code: model.homeLink?.code, size: 84, label: String(localized: "Code", comment: "TV: VoiceOver, before a link's backup code is spelled out"))
                    .accessibilityIdentifier("tv.home.code")
            }
            .frame(width: 780, alignment: .leading)
            TVQRCode(text: model.homeLink?.url.absoluteString, side: 300)
                .accessibilityLabel(Text("QR code to put a table on this TV", comment: "TV home: the link's QR, for VoiceOver"))
        }
    }

    private var posters: some View {
        let k = TVShelf.scale(GameCatalog.all.count + (model.dishOn ? 1 : 0))
        return HStack(alignment: .top, spacing: TVShelf.gap * k) {
            ForEach(GameCatalog.all) { game in
                Poster(game: game, refused: model.refused) {
                    Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
                    Task { await model.make(game: game.id) }
                }
                .focused($focus, equals: game.id)
            }
            if model.dishOn {
                BoardPoster {
                    Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
                    model.pressBoard()
                }
                .focused($focus, equals: "board")
            }
        }
        .environment(\.posterScale, k)
    }
}

/// The home shelf's size: posters of 404 with 48 between across the safe area's 1760. Up to four
/// fill it at full size; more scale down together to the same span.
enum TVShelf {
    static let span: CGFloat = 1760
    static let width: CGFloat = 404
    static let gap: CGFloat = 48

    /// The poster scale for `count` posters on the shelf.
    static func scale(_ count: Int) -> CGFloat {
        guard count > 4 else { return 1 }
        return span / (CGFloat(count) * width + CGFloat(count - 1) * gap)
    }

    /// The shelf's width at that scale.
    static func shelfWidth(_ count: Int) -> CGFloat {
        let k = scale(count)
        return CGFloat(count) * width * k + CGFloat(max(count - 1, 0)) * gap * k
    }
}

private struct PosterScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// The home shelf's poster scale (`TVShelf.scale`).
    var posterScale: CGFloat {
        get { self[PosterScaleKey.self] }
        set { self[PosterScaleKey.self] = newValue }
    }
}

/// A poster on the shelf: art across the top, then the name (up to two lines) and a pill.
private struct PosterCard<Art: View, Badge: View>: View {
    static var artHeight: CGFloat { 236 }
    static var wordsHeight: CGFloat { 262 }

    @Environment(\.posterScale) private var k
    let title: String
    @ViewBuilder let art: Art
    @ViewBuilder let badge: Badge

    var body: some View {
        VStack(spacing: 0) {
            art
                .frame(width: TVShelf.width * k, height: Self.artHeight * k)
                .clipped()
                // Decoration: the button says its name, and a drawn-big sunburst inside mustn't
                // widen the poster's frame for VoiceOver or the UI tests.
                .accessibilityHidden(true)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink).frame(height: 6 * k) }
            VStack(alignment: .leading, spacing: 0) {
                OutlinedText(title, size: 58 * k, width: 5 * k, lines: 2, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12 * k)
                badge
            }
            .padding(.horizontal, 26 * k)
            .padding(.top, 20 * k)
            .padding(.bottom, 28 * k)
            .frame(width: TVShelf.width * k, height: Self.wordsHeight * k, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 40 * k, style: .continuous))
    }
}

/// The pill under a poster's name.
private struct PosterPill<Lead: View>: View {
    @Environment(\.posterScale) private var k
    let words: String
    @ViewBuilder let lead: Lead

    var body: some View {
        HStack(spacing: 12 * k) {
            lead
            Text(verbatim: words)
                .font(.system(size: 30 * k, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 18 * k)
        .padding(.vertical, 8 * k)
        .background(Capsule().fill(Palette.ink.opacity(0.5)))
    }
}

/// A game's poster: its cover, its name and how many play.
private struct Poster: View {
    static func tint(_ game: GameCatalog.Entry) -> Color {
        switch game.id {
        case GameCatalog.tiles.id: Palette.sky
        case GameCatalog.birdwatch.id: Palette.lime
        case GameCatalog.tumble.id: Palette.lime
        default: Palette.violet
        }
    }

    let game: GameCatalog.Entry
    let refused: Int
    let press: () -> Void
    @Environment(\.posterScale) private var k
    @FocusState private var focused: Bool
    @State private var shakes = 0

    var body: some View {
        Button(action: press) {
            PosterCard(title: game.title) {
                Image(game.art)
                    .resizable()
                    .scaledToFill()
            } badge: {
                // "2 to 6 players", with a dot in each seat's colour.
                PosterPill(words: String(localized: "\(game.minPlayers) to \(game.maxPlayers) players", comment: "TV home: under a game's name, how many can play")) {
                    HStack(spacing: -5 * k) {
                        ForEach(0..<game.maxPlayers, id: \.self) { seat in
                            Circle()
                                .fill(tvRing(seat))
                                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3 * k))
                                .frame(width: 20 * k, height: 20 * k)
                        }
                    }
                }
            }
        }
        .buttonStyle(TVButtonStyle(tint: Self.tint(game), corner: 40 * k))
        .focused($focused)
        .shake(trigger: shakes)
        .onChange(of: refused) { _, _ in
            // Not made (offline, most likely): a shake, and the poster can be pressed again.
            guard focused else { return }
            shakes += 1
            Sound.shared.play(ArtName.Sound.sfxNope)
        }
        .accessibilityLabel(game.title)
        .accessibilityIdentifier("tv.poster.\(game.id)")
    }
}

/// Tonight's board: the Daily Dish's board on this TV. Opens the kept board, or its link.
private struct BoardPoster: View {
    let press: () -> Void
    @Environment(\.posterScale) private var k

    var body: some View {
        Button(action: press) {
            PosterCard(title: String(localized: "Tonight's board", comment: "TV home: the Daily Dish board's poster")) {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xFFE066), Palette.orange], startPoint: .top, endPoint: .bottom)
                    // The sunburst, 640 across from the art's middle, drawn in a canvas the art's
                    // size: a 640-point view inside would widen the poster's frame past the screen.
                    Canvas { context, size in
                        context.opacity = 0.55
                        let side = 640 * k
                        context.draw(
                            Image(ArtName.sunburst),
                            in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side))
                    }
                    Image(ArtName.iconTrophy)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140 * k, height: 140 * k)
                        .offset(y: -34 * k)
                    HStack {
                        Image(ArtName.cat(3, .celebrate)).resizable().scaledToFit().frame(width: 140 * k, height: 140 * k)
                        Spacer()
                        Image(ArtName.cat(5, .leap)).resizable().scaledToFit().frame(width: 140 * k, height: 140 * k)
                    }
                    .padding(.horizontal, 12 * k)
                    .frame(width: TVShelf.width * k, height: PosterCard<EmptyView, EmptyView>.artHeight * k, alignment: .bottom)
                }
            } badge: {
                PosterPill(words: String(localized: "Daily puzzles", comment: "TV home: under Tonight's board, what it is")) { EmptyView() }
            }
        }
        .buttonStyle(TVButtonStyle(tint: Palette.magenta, corner: 40 * k))
        .accessibilityLabel(Text("Tonight's board", comment: "TV home: the Daily Dish board's poster"))
        .accessibilityIdentifier("tv.poster.board")
    }
}

/// Tonight's board before a phone linked one: home's own link, big, with the Dish's words.
private struct BoardLinkView: View {
    let model: TVModel
    @FocusState private var backFocused: Bool

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.74)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            HStack(spacing: 64) {
                TVQRCode(text: model.homeLink?.url.absoluteString, side: 380)
                    .accessibilityLabel(Text("QR code to show your board on this TV", comment: "TV: the board link's QR, for VoiceOver"))
                VStack(spacing: 30) {
                    OutlinedText(String(localized: "Tonight's board", comment: "TV home: the Daily Dish board's poster"), size: 72, width: 5)
                    OutlinedText(String(localized: "Scan from the Dish on your phone", comment: "TV: over the QR a phone scans to show its Daily Dish board"), size: 50, width: 4, lines: 2)
                        .fixedSize(horizontal: false, vertical: true)
                    TVCode(code: model.homeLink?.code, size: 84, label: String(localized: "Code", comment: "TV: VoiceOver, before a link's backup code is spelled out"))
                        .accessibilityIdentifier("tv.boardLink.code")
                    if model.homeOffline { TVReconnecting() }
                    Button {
                        Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
                        model.closeBoardLink()
                    } label: {
                        TVButtonLabel(icon: ArtName.iconBack, words: String(localized: "Back", comment: "TV menu: from the link back to the menu's choices"), size: 42)
                            .frame(width: 360)
                    }
                    .buttonStyle(TVButtonStyle(tint: Palette.violet))
                    .accessibilityIdentifier("tv.boardLink.back")
                    .focused($backFocused)
                }
                .frame(width: 640)
            }
            .padding(64)
            .background(RoundedRectangle(cornerRadius: 56, style: .continuous).fill(Palette.night))
            .overlay(RoundedRectangle(cornerRadius: 56, style: .continuous).strokeBorder(Palette.ink, lineWidth: 8))
            .compositingGroup()
            .focusSection()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            backFocused = true
        }
    }
}
