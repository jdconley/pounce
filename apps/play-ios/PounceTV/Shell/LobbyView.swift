import PounceKit
import SwiftUI

/// The table's lobby on the TV: the invite QR and code on the left; on the right the game, its
/// rug with a cushion for every seat, and how to start. Each player's cat walks onto their
/// cushion as their phone sits down. Start is a phone's; until anyone sits, the TV may swap the
/// game ("Change game"). The web TV's `TvLobby`.
struct LobbyView: View {
    let model: TVModel
    let table: TVRoom
    /// The remote reaches this screen's buttons (not while the menu is over it).
    let live: Bool
    @FocusState private var changeFocused: Bool
    @State private var shakes = 0

    var body: some View {
        if let room = table.store.room {
            HStack(alignment: .center, spacing: 72) {
                join(room)
                    .frame(width: 560)
                VStack(spacing: 26) {
                    header(room)
                    LobbyRug(room: room)
                        .frame(width: 1128, height: 520)
                    TVHint(icon: ArtName.Habit.iconPhone, words: String(localized: "Press Start on any phone", comment: "TV lobby: a phone starts the game"))
                    if model.canChangeGame {
                        changeGame
                    }
                }
                .frame(width: 1128)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.canChangeGame)
        } else {
            TVWaiting(words: String(localized: "Finding your table", comment: "TV: connecting to the table it shows, before it arrives"))
        }
    }

    private func join(_ room: RoomView) -> some View {
        VStack(spacing: 30) {
            OutlinedText(String(localized: "Scan to join", comment: "TV lobby: over the QR a phone scans to join the table"), size: 60, width: 4)
            TVQRCode(text: model.inviteURL?.absoluteString, side: 380)
                .accessibilityLabel(Text("QR code to join table \(room.code)", comment: "TV lobby: the invite QR, for VoiceOver"))
            TVCode(code: room.code, label: String(localized: "Table code", comment: "TV lobby: VoiceOver, before the table's code is spelled out"))
        }
    }

    private func header(_ room: RoomView) -> some View {
        let game = GameCatalog.entry(id: room.gameId ?? GameCatalog.catTower.id) ?? GameCatalog.catTower
        return HStack(spacing: 28) {
            Image(game.art)
                .resizable()
                .scaledToFill()
                .frame(width: 186, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5))
            OutlinedText(game.title, size: 84, width: 5)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.title)
    }

    private var changeGame: some View {
        Button {
            Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
            Task { await model.changeGame() }
        } label: {
            TVButtonLabel(icon: ArtName.iconSwap, words: String(localized: "Change game", comment: "TV lobby: make the other game's table instead"), size: 40)
                .frame(width: 520)
        }
        .buttonStyle(TVButtonStyle(tint: Palette.violet, corner: 36))
        .disabled(!live)
        .focused($changeFocused)
        .shake(trigger: shakes)
        .onChange(of: model.refused) { _, _ in
            guard changeFocused else { return }
            shakes += 1
            Sound.shared.play(ArtName.Sound.sfxNope)
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// The game's rug with a cushion for every seat that isn't closed; a cat on each taken one.
private struct LobbyRug: View {
    let room: RoomView

    /// Where each seat sits on the rug, as shares of it, by seats shown (the web TV's `SPOTS`).
    private static let spots: [Int: [CGPoint]] = [
        2: [CGPoint(x: 0.27, y: 0.5), CGPoint(x: 0.73, y: 0.5)],
        3: [CGPoint(x: 0.2, y: 0.58), CGPoint(x: 0.5, y: 0.36), CGPoint(x: 0.8, y: 0.58)],
        4: [CGPoint(x: 0.27, y: 0.28), CGPoint(x: 0.73, y: 0.28), CGPoint(x: 0.27, y: 0.74), CGPoint(x: 0.73, y: 0.74)],
        5: [CGPoint(x: 0.5, y: 0.22), CGPoint(x: 0.15, y: 0.46), CGPoint(x: 0.85, y: 0.46), CGPoint(x: 0.3, y: 0.8), CGPoint(x: 0.7, y: 0.8)],
        6: [
            CGPoint(x: 0.17, y: 0.27), CGPoint(x: 0.5, y: 0.22), CGPoint(x: 0.83, y: 0.27),
            CGPoint(x: 0.17, y: 0.77), CGPoint(x: 0.5, y: 0.8), CGPoint(x: 0.83, y: 0.77),
        ],
    ]

    struct Spot: Identifiable {
        let seat: Seat
        let filled: Bool
        /// Changes with whoever sits there, so a newcomer's cat walks on.
        let id: String
    }

    private var spots: [Spot] {
        room.seats.indices.compactMap { i in
            let s = room.seats[i]
            switch s.kind {
            case .closed: return nil
            case .open: return Spot(seat: i, filled: false, id: "\(i):open")
            case .bot: return Spot(seat: i, filled: true, id: "\(i):bot")
            case .human: return Spot(seat: i, filled: true, id: "\(i):p:\(s.person?.id ?? "")")
            }
        }
    }

    var body: some View {
        let spots = spots
        let places = Self.spots[min(max(spots.count, 2), 6)] ?? Self.spots[2]!
        let filled = spots.filter(\.filled).count
        GeometryReader { g in
            ZStack {
                Image(ArtName.rug)
                    .resizable()
                    .frame(width: g.size.width * 0.98, height: g.size.height * 0.92)
                    .position(x: g.size.width / 2, y: g.size.height / 2)
                    .accessibilityHidden(true)
                ForEach(Array(spots.enumerated()), id: \.element.id) { k, spot in
                    let at = places[safe: k] ?? CGPoint(x: 0.5, y: 0.5)
                    LobbySeat(room: room, spot: spot, crowded: spots.count > 4)
                        .position(x: at.x * g.size.width, y: at.y * g.size.height)
                        .transition(.asymmetric(
                            insertion: .offset(x: at.x < 0.5 ? -260 : 260).combined(with: .opacity),
                            removal: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: spots.map(\.id))
        .onChange(of: filled) { was, now in
            // A pop as each cat arrives.
            if now > was { Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.6) }
        }
    }
}

/// One seat on the lobby's rug: a cushion with its player's cat and name, or an open spot.
private struct LobbySeat: View {
    let room: RoomView
    let spot: LobbyRug.Spot
    let crowded: Bool

    var body: some View {
        let cat: CGFloat = crowded ? 136 : 168
        if spot.filled {
            let info = room.seats[spot.seat]
            let name = SeatInfo.name(room, spot.seat)
            VStack(spacing: -10) {
                ZStack(alignment: .topTrailing) {
                    Ellipse()
                        .fill(tvRing(spot.seat))
                        .overlay(Ellipse().strokeBorder(Palette.ink, lineWidth: 5))
                        .frame(width: cat * 1.1, height: cat * 0.42)
                        .offset(y: cat * 0.36)
                        .frame(width: cat * 1.1, height: cat)
                    Image(ArtName.cat(SeatInfo.catIndex(info), .awake))
                        .resizable()
                        .scaledToFit()
                        .frame(width: cat, height: cat)
                        .frame(width: cat * 1.1)
                    if info.kind == .bot {
                        Image(ArtName.badgeBot)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                    }
                }
                // A 20-letter name whole, even six seats across.
                NameTag(name, maxWidth: crowded ? 344 : 480, size: crowded ? 28 : 32)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
        } else {
            Image(ArtName.iconPawMenu)
                .resizable()
                .scaledToFit()
                .frame(width: cat * 0.42, height: cat * 0.42)
                .opacity(0.55)
                .frame(width: cat * 0.8, height: cat * 0.8)
                .background(Circle().fill(Palette.ink.opacity(0.35)))
                .overlay(Circle().strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 5, dash: [14, 12])))
                .accessibilityLabel(Text("Open seat", comment: "TV lobby: VoiceOver, a seat nobody took yet"))
        }
    }
}

/// While the TV finds its table: a cat and a few words.
struct TVWaiting: View {
    let words: String

    var body: some View {
        VStack(spacing: 30) {
            Image(ArtName.cat(0, .awake))
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
            OutlinedText(words, size: 56, width: 4)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 50)
        .background(RoundedRectangle(cornerRadius: 48, style: .continuous).fill(Palette.ink.opacity(0.6)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
