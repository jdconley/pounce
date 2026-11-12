import PounceKit
import SwiftUI

/// One game on Home's shelf (`GameCatalog`): its cover, name, one-line pitch and how many can
/// play. A game you can start is a button that starts a table; a game on the way wears a
/// "Coming soon" sticker and answers a tap with a wiggle and a short note, never a table.
///
/// Two layouts. `poster`: the cover across the top, the words on a band in the game's colour
/// under it. `ticket`: a square of the cover on the left, the words beside it (a phone's games on
/// the way, and every game while your tables lead Home); a game you can start wears its play
/// button on the cover. At the accessibility text sizes a ticket turns into a poster, so the
/// words get the card's whole width.
struct GameCard: View {
    enum Layout { case poster, ticket }

    let game: GameCatalog.Entry
    var layout: Layout = .poster
    /// Width over height of a poster's cover (the art is 3:2; anything wider trims top and bottom).
    var coverRatio: CGFloat = 1.5
    /// An iPad's bigger card: bigger words and a bigger play mark.
    var roomy = false
    /// The play mark goes under the words, as wide as the card (an iPad's grid, where a column
    /// can be narrow); otherwise beside them. Big text always puts it under.
    var playUnder = false
    /// A table is being made: the card waits, dimmed.
    var busy = false
    var identifier: String?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 27
    @ScaledMetric(relativeTo: .title2) private var roomyTitleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title3) private var ticketTitleSize: CGFloat = 23
    @ScaledMetric(relativeTo: .subheadline) private var stickerSize: CGFloat = 15

    /// Taps on a game that isn't ready: each one wiggles the sticker.
    @State private var nudges = 0
    /// The "not ready yet" note is up.
    @State private var noteShown = false

    static let corner: CGFloat = 30
    static let outline: CGFloat = 5
    static let lip: CGFloat = 7

    private var soon: Bool { !game.isAvailable }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.corner, style: .continuous) }
    private var tint: Color { Palette.tint(game.tint) }
    /// Big text: every card is a poster.
    private var bigType: Bool { typeSize.isAccessibilitySize }
    private var shownLayout: Layout { bigType ? .poster : layout }

    var body: some View {
        Button {
            if soon {
                acknowledge()
            } else {
                Haptics.shared.tick()
                Sound.shared.play(ArtName.Sound.sfxTick)
                action()
            }
        } label: {
            face
        }
        .buttonStyle(GameCardStyle(shape: shape, lipColor: bandColors.last ?? tint))
        .disabled(busy)
        // The cover, band and lip dim as one card.
        .compositingGroup()
        .opacity(busy ? 0.7 : 1)
        // One button to VoiceOver: the words in order, then what a double tap does.
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        // While the "not ready yet" note is up, its words are the card's value.
        .accessibilityValue(noteShown ? Self.noteWords : "")
        .accessibilityIdentifier(identifier ?? "home.game.\(game.id)")
        .task(id: nudges) {
            // The note goes away by itself a moment after the last tap.
            guard nudges > 0 else { return }
            try? await Task.sleep(for: Pace.duration(.milliseconds(2600)))
            if !Task.isCancelled { noteShown = false }
        }
        .overlay(alignment: .topTrailing) { if soon { sticker } }
        .animation(.spring(duration: 0.35, bounce: 0.35).paced, value: noteShown)
    }

    // MARK: layouts

    @ViewBuilder private var face: some View {
        switch shownLayout {
        case .poster:
            VStack(spacing: 0) {
                // The cover takes the card's width first; the band gets what the row leaves.
                cover
                    .aspectRatio(bigType ? max(coverRatio, 2.1) : coverRatio, contentMode: .fit)
                    .layoutPriority(1)
                    .overlay(alignment: .bottom) { note.padding(.bottom, 10) }
                Rectangle().fill(Palette.ink).frame(height: Self.outline)
                band(titleSize: roomy ? roomyTitleSize : titleSize)
            }
        case .ticket:
            HStack(spacing: 0) {
                cover.frame(width: 108)
                    .overlay { if !soon { PlayDisc() } }
                Rectangle().fill(Palette.ink).frame(width: Self.outline)
                band(titleSize: ticketTitleSize)
                    .overlay(alignment: .bottom) { note.padding(.bottom, 8) }
            }
            .frame(minHeight: 104)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The cover, filling whatever frame the layout gives it. A game on the way is drawn duller.
    private var cover: some View {
        Color.clear
            .overlay {
                Image(game.art)
                    .resizable()
                    .scaledToFill()
                    .saturation(soon ? 0.8 : 1)
                    .overlay { if soon { Palette.night.opacity(0.2) } }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private func band(titleSize: CGFloat) -> some View {
        let words = VStack(alignment: .leading, spacing: 5) {
            OutlinedText(game.title, size: titleSize, width: 3, lines: 2, alignment: .leading)
                .padding(-3)
            Text(verbatim: game.pitch)
                .font(.system(roomy ? .title3 : .subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 1.5)
                .fixedSize(horizontal: false, vertical: true)
            PlayersChip(game: game, roomy: roomy)
                .padding(.top, 2)
        }
        .multilineTextAlignment(.leading)

        return Group {
            if soon {
                if shownLayout == .poster, playUnder || bigType {
                    // Where a playable card has its play mark, so a row of posters lines up.
                    VStack(alignment: .leading, spacing: 12) {
                        words.frame(maxWidth: .infinity, alignment: .leading)
                        NotYetMark(roomy: roomy)
                    }
                } else {
                    words.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if shownLayout == .ticket {
                words.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if playUnder || bigType {
                    VStack(alignment: .leading, spacing: 12) {
                        words.frame(maxWidth: .infinity, alignment: .leading)
                        PlayMark(wide: true, roomy: roomy)
                    }
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        words.frame(maxWidth: .infinity, alignment: .leading)
                        PlayMark(roomy: roomy)
                    }
                }
            }
        }
        .padding(.horizontal, roomy ? 20 : 16)
        .padding(.top, roomy ? 14 : 10)
        .padding(.bottom, roomy ? 16 : 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LinearGradient(colors: bandColors, startPoint: .top, endPoint: .bottom))
    }

    private var bandColors: [Color] {
        soon
            ? [tint.mix(with: .black, by: 0.2), tint.mix(with: .black, by: 0.42)]
            : [tint.mix(with: .white, by: 0.12), tint.mix(with: Palette.ink, by: 0.3)]
    }

    // MARK: coming soon

    private var sticker: some View {
        OutlinedText(Self.soonWords, size: min(stickerSize, 24) * (roomy ? 1.25 : 1), width: 2.5)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(LinearGradient(
                        colors: [Palette.magenta.mix(with: .white, by: 0.25), Palette.magenta], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4))
                    .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 4))
            .rotationEffect(.degrees(5))
            .pop(trigger: nudges)
            .wiggle(trigger: nudges)
            .offset(x: 6, y: -12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var note: some View {
        if noteShown {
            Text(verbatim: Self.noteWords)
                .font(.system(.footnote, design: .rounded, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.ink, lineWidth: 3))
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3))
                .padding(.horizontal, 10)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }

    /// A tap on a game that can't be started yet: a tick, a pop, the sticker wiggles and a short
    /// note says why. VoiceOver hears the note.
    private func acknowledge() {
        Haptics.shared.tick()
        Sound.shared.play(ArtName.Sound.sfxPop)
        nudges += 1
        noteShown = true
        UIAccessibility.post(notification: .announcement, argument: Self.noteWords)
    }

    static let soonWords = String(localized: "Coming soon", comment: "Game shelf: the sticker on a game that can't be played yet")
    static let noteWords = String(
        localized: "Not ready yet.", comment: "Game shelf: the short note after a tap on a game that can't be played yet")

    // MARK: words for VoiceOver

    private var label: Text {
        let players = PlayersChip.words(game)
        return soon
            ? Text("\(game.title), coming soon. \(game.pitch) \(players).", comment: "VoiceOver: a game on Home's shelf that can't be played yet: name, pitch, players")
            : Text("\(game.title). \(game.pitch) \(players).", comment: "VoiceOver: a game on Home's shelf: name, pitch, players")
    }

    private var hint: Text {
        soon
            ? Text("Not ready to play yet", comment: "VoiceOver hint: a game on the shelf that is coming soon")
            : Text("Starts a new table", comment: "VoiceOver hint: a game on the shelf")
    }
}

/// The card's press: the face sinks onto its lip, like a pill.
private struct GameCardStyle: ButtonStyle {
    let shape: RoundedRectangle
    let lipColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: GameCard.outline))
            .overlay(shape.strokeBorder(.white.opacity(0.28), lineWidth: 2).padding(GameCard.outline))
            .offset(y: down && !reduceMotion ? GameCard.lip - 2 : 0)
            .brightness(down ? -0.06 : 0)
            .background(
                // The lip: the card's own shape, darker, peeking out below the face.
                shape.fill(lipColor.mix(with: Palette.ink, by: 0.55))
                    .overlay(shape.strokeBorder(Palette.ink, lineWidth: GameCard.outline))
                    .offset(y: GameCard.lip))
            .padding(.bottom, GameCard.lip)
            .contentShape(Rectangle())
            .animation(.spring(duration: 0.14, bounce: 0.25).paced, value: down)
    }
}

/// "2 to 6 players", after one pip per seat in the seat ring colours (`TableCard`'s pips).
struct PlayersChip: View {
    let game: GameCatalog.Entry
    var roomy = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let pip: CGFloat = roomy ? 12 : 10
        HStack(spacing: 7) {
            HStack(spacing: 3) {
                ForEach(0..<game.maxPlayers, id: \.self) { i in
                    Circle()
                        .fill(Palette.playerRings[i % Palette.playerRings.count])
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
                        .frame(width: pip, height: pip)
                }
            }
            Text(verbatim: Self.words(game))
                .font(.system(roomy ? .subheadline : .footnote, design: .rounded, weight: .heavy))
                .foregroundStyle(.white)
                // One line, shrinking a little before it wraps; big text may take two.
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.8)
        }
        .padding(.leading, 8)
        .padding(.trailing, 11)
        .padding(.vertical, 4)
        .background(Capsule().fill(Palette.ink.opacity(0.42)))
        .accessibilityHidden(true)
    }

    static func words(_ game: GameCatalog.Entry) -> String {
        game.minPlayers == game.maxPlayers
            ? String(localized: "\(game.maxPlayers) players", comment: "Game shelf: a game for exactly this many players")
            : String(
                localized: "\(game.minPlayers) to \(game.maxPlayers) players",
                comment: "Game shelf: how many can play, e.g. '2 to 6 players'")
    }
}

/// The orange "Play" mark on a game you can start. A picture of a pill, not a button: the whole
/// card is the button.
private struct PlayMark: View {
    var wide = false
    var roomy = false
    @ScaledMetric(relativeTo: .headline) private var wordSize: CGFloat = 20

    var body: some View {
        let height: CGFloat = wide || roomy ? 58 : 46
        let capsule = Capsule()
        HStack(spacing: 6) {
            Image(ArtName.iconPlay)
                .resizable().scaledToFit()
                .frame(width: height * 0.5, height: height * 0.5)
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 2)
            OutlinedText(Self.word, size: min(wordSize, 30) * (roomy ? 1.25 : 1), width: 2.5)
                .fixedSize()
        }
        .padding(.leading, roomy ? 16 : 12)
        .padding(.trailing, roomy ? 20 : 16)
        .frame(maxWidth: wide ? .infinity : nil)
        .frame(height: height)
        .background(
            capsule
                .fill(LinearGradient(
                    colors: [Palette.orange.mix(with: .white, by: 0.35), Palette.orange, Palette.orange.mix(with: Palette.ink, by: 0.15)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    Capsule().fill(.white.opacity(0.5)).frame(height: height * 0.18).padding(.horizontal, height * 0.42).padding(.top, height * 0.1)
                }
                .overlay(capsule.strokeBorder(Palette.ink, lineWidth: 4))
                .background(
                    capsule.fill(Palette.orange.mix(with: Palette.ink, by: 0.5))
                        .overlay(capsule.strokeBorder(Palette.ink, lineWidth: 4))
                        .offset(y: 5)))
        .padding(.bottom, 5)
        .accessibilityHidden(true)
    }

    static let word = String(localized: "Play", comment: "Game shelf: the mark on a game you can start")
}

/// Where the play mark would be on a game that is on its way: a flat, sunken bar with a padlock.
/// Nothing to press; the sticker says "Coming soon".
private struct NotYetMark: View {
    var roomy = false

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: roomy ? 24 : 20, weight: .black))
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                Capsule().fill(.black.opacity(0.28))
                    .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.85), lineWidth: 4)))
            .padding(.bottom, 5)
            .accessibilityHidden(true)
    }
}

/// A ticket's play button, on its cover: an orange disc with the play mark. A picture, not a
/// button: the whole card is the button.
private struct PlayDisc: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: [Palette.orange.mix(with: .white, by: 0.35), Palette.orange, Palette.orange.mix(with: Palette.ink, by: 0.15)],
                startPoint: .top, endPoint: .bottom))
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
            .overlay {
                Image(ArtName.iconPlay)
                    .resizable().scaledToFit()
                    .padding(13)
                    .offset(x: 2)
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 2)
            }
            .frame(width: 54, height: 54)
            .compositingGroup()
            .shadow(color: Palette.ink.opacity(0.55), radius: 0, x: 0, y: 4)
            .accessibilityHidden(true)
    }
}

extension Palette {
    /// A catalog entry's colour in the app's palette.
    static func tint(_ tint: GameCatalog.Entry.Tint) -> Color {
        switch tint {
        case .violet: violet
        case .magenta: magenta
        case .teal: teal
        case .orange: orange
        case .sky: sky
        case .lime: lime
        }
    }
}

/// The shelf's entrance: each card rises into place a beat after the one before. Reduce Motion
/// keeps the fade and drops the travel.
private struct ShelfEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            // The card's layers fade in as one.
            .compositingGroup()
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 28)
            .scaleEffect(shown || reduceMotion ? 1 : 0.94)
            .onAppear {
                withAnimation(.spring(duration: 0.5, bounce: 0.32).delay(0.05 + 0.08 * Double(index)).paced) { shown = true }
            }
    }
}

extension View {
    /// Rises and fades in as part of the game shelf, `index` cards down.
    func shelfEntrance(index: Int) -> some View { modifier(ShelfEntrance(index: index)) }
}
