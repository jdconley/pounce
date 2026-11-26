import PounceKit
import SwiftUI

/// The TV's home: across the top, the link a phone scans (or types the code of) to put its table,
/// or its Daily Dish board, here; under it a shelf of posters, one per game, each making a table
/// with this TV as its screen, and Tonight's board while the server has the Dish on. The remote
/// moves along the shelf left to right. Nothing is typed on the TV. Menu here leaves the app, as
/// tvOS users expect (or closes the board's link panel).
///
/// Sized for the TV's 1920x1080 points inside its safe area (80 at the sides, 60 at the top and
/// bottom): the link row and the shelf take about 930 of the 960 between. Four posters of 404 with
/// 48 between fill the 1760 across, leaving room for the focus ring and its grow.
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
        HStack(alignment: .top, spacing: PosterCard<EmptyView, EmptyView>.gap) {
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
    }
}

/// A poster on the shelf: art across the top, then the name (up to two lines) and a pill.
private struct PosterCard<Art: View, Badge: View>: View {
    static var width: CGFloat { 404 }
    static var gap: CGFloat { 48 }
    static var artHeight: CGFloat { 236 }
    static var wordsHeight: CGFloat { 262 }

    let title: String
    @ViewBuilder let art: Art
    @ViewBuilder let badge: Badge

    var body: some View {
        VStack(spacing: 0) {
            art
                .frame(width: Self.width, height: Self.artHeight)
                .clipped()
                // Decoration: the button says its name, and a drawn-big sunburst inside mustn't
                // widen the poster's frame for VoiceOver or the UI tests.
                .accessibilityHidden(true)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink).frame(height: 6) }
            VStack(alignment: .leading, spacing: 0) {
                OutlinedText(title, size: 58, width: 5, lines: 2, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                badge
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .frame(width: Self.width, height: Self.wordsHeight, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
    }
}

/// The pill under a poster's name.
private struct PosterPill<Lead: View>: View {
    let words: String
    @ViewBuilder let lead: Lead

    var body: some View {
        HStack(spacing: 12) {
            lead
            Text(verbatim: words)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Capsule().fill(Palette.ink.opacity(0.5)))
    }
}

/// A game's poster: its cover, its name and how many play.
private struct Poster: View {
    static func tint(_ game: GameCatalog.Entry) -> Color {
        switch game.id {
        case GameCatalog.tiles.id: Palette.sky
        case GameCatalog.birdwatch.id: Palette.lime
        default: Palette.violet
        }
    }

    let game: GameCatalog.Entry
    let refused: Int
    let press: () -> Void
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
                    HStack(spacing: -5) {
                        ForEach(0..<game.maxPlayers, id: \.self) { seat in
                            Circle()
                                .fill(tvRing(seat))
                                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
                                .frame(width: 20, height: 20)
                        }
                    }
                }
            }
        }
        .buttonStyle(TVButtonStyle(tint: Self.tint(game), corner: 40))
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

    var body: some View {
        Button(action: press) {
            PosterCard(title: String(localized: "Tonight's board", comment: "TV home: the Daily Dish board's poster")) {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xFFE066), Palette.orange], startPoint: .top, endPoint: .bottom)
                    // The sunburst, 640 across from the art's middle, drawn in a canvas the art's
                    // size: a 640-point view inside would widen the poster's frame past the screen.
                    Canvas { context, size in
                        context.opacity = 0.55
                        context.draw(
                            Image(ArtName.sunburst),
                            in: CGRect(x: (size.width - 640) / 2, y: (size.height - 640) / 2, width: 640, height: 640))
                    }
                    Image(ArtName.iconTrophy)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .offset(y: -34)
                    HStack {
                        Image(ArtName.cat(3, .celebrate)).resizable().scaledToFit().frame(width: 140, height: 140)
                        Spacer()
                        Image(ArtName.cat(5, .leap)).resizable().scaledToFit().frame(width: 140, height: 140)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: PosterCard<EmptyView, EmptyView>.width, height: PosterCard<EmptyView, EmptyView>.artHeight, alignment: .bottom)
                }
            } badge: {
                PosterPill(words: String(localized: "Daily puzzles", comment: "TV home: under Tonight's board, what it is")) { EmptyView() }
            }
        }
        .buttonStyle(TVButtonStyle(tint: Palette.magenta, corner: 40))
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
