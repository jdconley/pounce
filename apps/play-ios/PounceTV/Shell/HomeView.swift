import PounceKit
import SwiftUI

/// The TV's home: on the left, the link a phone scans (or types the code of) to put its table
/// here; on the right, the two games' posters, each making a table with this TV as its screen.
/// Nothing is typed on the TV. Menu here leaves the app, as tvOS users expect.
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
        }
    }

    private var posters: some View {
        VStack(spacing: 60) {
            ForEach(GameCatalog.all) { game in
                Poster(game: game, making: model.making, refused: model.refused) {
                    Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
                    Task { await model.make(game: game.id) }
                }
                .focused($focus, equals: game.id)
            }
        }
    }
}

/// A game's poster: its cover on the left, its name and how many play on the right.
private struct Poster: View {
    let game: GameCatalog.Entry
    let making: Bool
    let refused: Int
    let press: () -> Void
    @FocusState private var focused: Bool
    @State private var shakes = 0

    var body: some View {
        Button(action: press) {
            HStack(spacing: 0) {
                Image(game.art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 380, height: 360)
                    .clipped()
                    .overlay(alignment: .trailing) { Rectangle().fill(Palette.ink).frame(width: 6) }
                VStack(alignment: .leading, spacing: 30) {
                    OutlinedText(game.title, size: 84, width: 5, lines: 2, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    players
                }
                .padding(.horizontal, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
        .buttonStyle(TVButtonStyle(tint: game.id == GameCatalog.tiles.id ? Palette.sky : Palette.violet, corner: 40))
        .focused($focused)
        .shake(trigger: shakes)
        .onChange(of: refused) { _, _ in
            // Not made (offline, most likely): a shake, and the poster can be pressed again.
            guard focused else { return }
            shakes += 1
            Sound.shared.play(ArtName.Sound.sfxNope)
        }
        .accessibilityLabel(game.title)
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
