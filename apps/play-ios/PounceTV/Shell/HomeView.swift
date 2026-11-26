import PounceKit
import SwiftUI

/// The TV's home: on the left, the link a phone scans (or types the code of) to put its table, or
/// its Daily Dish board, here; on the right, the two games' posters, each making a table with this
/// TV as its screen, and Tonight's board while the server has the Dish on. Nothing is typed on
/// the TV. Menu here leaves the app, as tvOS users expect (or closes the board's link panel).
struct HomeView: View {
    let model: TVModel
    @FocusState private var focus: String?

    var body: some View {
        HStack(alignment: .center, spacing: 110) {
            link
                .frame(width: 700)
            posters
                .frame(width: 860)
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

    private var link: some View {
        VStack(spacing: 34) {
            OutlinedText(
                String(localized: "Scan with your phone to put your table here", comment: "TV home: over the QR a phone scans to link its table"),
                size: 54, width: 4, lines: 2)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            TVQRCode(text: model.homeLink?.url.absoluteString, side: 400)
                .accessibilityLabel(Text("QR code to put a table on this TV", comment: "TV home: the link's QR, for VoiceOver"))
            TVCode(code: model.homeLink?.code, label: String(localized: "Code", comment: "TV: VoiceOver, before a link's backup code is spelled out"))
                .accessibilityIdentifier("tv.home.code")
        }
    }

    private var posters: some View {
        // The games and, with the Dish on, its board share the height.
        let count = GameCatalog.all.count + (model.dishOn ? 1 : 0)
        let height: CGFloat = count >= 4 ? 212 : count == 3 ? 284 : 360
        return VStack(spacing: count >= 4 ? 26 : count == 3 ? 36 : 60) {
            ForEach(GameCatalog.all) { game in
                Poster(game: game, refused: model.refused, height: height) {
                    Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
                    Task { await model.make(game: game.id) }
                }
                .focused($focus, equals: game.id)
            }
            if model.dishOn {
                BoardPoster(height: height) {
                    Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
                    model.pressBoard()
                }
                .focused($focus, equals: "board")
            }
        }
    }
}

/// A game's poster: its cover on the left, its name and how many play on the right.
private struct Poster: View {
    static func tint(_ game: GameCatalog.Entry) -> Color {
        switch game.id {
        case GameCatalog.tiles.id: Palette.sky
        case GameCatalog.birdwatch.id: Palette.lime
        case GameCatalog.purrtrait.id: Palette.magenta
        default: Palette.violet
        }
    }

    let game: GameCatalog.Entry
    let refused: Int
    var height: CGFloat = 360
    let press: () -> Void
    @FocusState private var focused: Bool
    @State private var shakes = 0

    var body: some View {
        Button(action: press) {
            HStack(spacing: 0) {
                Image(game.art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 380, height: height)
                    .clipped()
                    .overlay(alignment: .trailing) { Rectangle().fill(Palette.ink).frame(width: 6) }
                VStack(alignment: .leading, spacing: 30) {
                    OutlinedText(game.title, size: height < 240 ? 64 : height < 360 ? 76 : 84, width: 5, lines: 2, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    players
                }
                .padding(.horizontal, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
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

    /// "2 to 6 players", with a dot in each seat's colour.
    private var players: some View {
        HStack(spacing: 14) {
            HStack(spacing: -6) {
                ForEach(0..<game.maxPlayers, id: \.self) { seat in
                    Circle()
                        .fill(tvRing(seat))
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
                        .frame(width: 26, height: 26)
                }
            }
            Text("\(game.minPlayers) to \(game.maxPlayers) players", comment: "TV home: under a game's name, how many can play")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Capsule().fill(Palette.ink.opacity(0.5)))
    }
}

/// Tonight's board: the Daily Dish's board on this TV. Opens the kept board, or its link.
private struct BoardPoster: View {
    let height: CGFloat
    let press: () -> Void

    var body: some View {
        Button(action: press) {
            HStack(spacing: 0) {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xFFE066), Palette.orange], startPoint: .top, endPoint: .bottom)
                    Image(ArtName.sunburst)
                        .resizable()
                        .frame(width: 640, height: 640)
                        .opacity(0.55)
                        .frame(width: 380, height: height)
                        .clipped()
                    Image(ArtName.iconTrophy)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .offset(y: -30)
                    HStack {
                        Image(ArtName.cat(3, .celebrate)).resizable().scaledToFit().frame(width: 150, height: 150)
                        Spacer()
                        Image(ArtName.cat(5, .leap)).resizable().scaledToFit().frame(width: 150, height: 150)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 380, height: height, alignment: .bottom)
                }
                .frame(width: 380, height: height)
                .clipped()
                .overlay(alignment: .trailing) { Rectangle().fill(Palette.ink).frame(width: 6) }
                VStack(alignment: .leading, spacing: 24) {
                    OutlinedText(String(localized: "Tonight's board", comment: "TV home: the Daily Dish board's poster"), size: 76, width: 5, lines: 2, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Daily puzzles", comment: "TV home: under Tonight's board, what it is")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Palette.ink.opacity(0.5)))
                }
                .padding(.horizontal, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
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
