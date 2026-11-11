import PounceKit
import SwiftUI

/// A player's card (tap their cat in the table's top bar), over the table like the scoreboard:
/// their cat, name and who plays it (a person here or on their own phone, or a House Cat), their
/// phase, cards in hand and points, and for a person whether you're connected and your streak
/// together (the badge that used to sit on the table). Tap outside it, or its close button, to
/// put it away.
struct PlayerCardOverlay: View {
    let card: PlayerCard
    /// The table as the scene drew it when the cat was tapped.
    let model: TableModel
    /// The seat's Nudge button as the store has it now (nil: none), and what a tap on it does.
    var nudge: () -> RoomStore.NudgeButton? = { nil }
    var onNudge: () -> Void = {}
    /// Whether this phone may retire the seat now (its move has waited days), and what confirming does.
    var canRetire: () -> Bool = { false }
    var onRetire: () -> Void = {}
    let onClose: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var appeared = false
    @State private var confirmingRetire = false

    private var scale: CGFloat { sizeClass == .regular ? 1.2 : 1 }
    private var ring: Color { SeatInfo.ringColor(card.seat) }
    private var name: String { SeatInfo.name(model.room, card.seat) }

    var body: some View {
        ZStack {
            Palette.night.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            GeometryReader { geo in
                ScrollView {
                    panel
                        .frame(maxWidth: 420 * scale)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                        // Anywhere around the card closes it (the card keeps its own taps).
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onClose)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.7)
            withAnimation(.spring(duration: 0.4, bounce: 0.35).paced) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier("player")
    }

    // MARK: the panel

    private var panel: some View {
        VStack(spacing: 14 * scale) {
            catDisc
            OutlinedText(name, size: 32 * scale, fill: .white, width: 4)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("player.name")
            kindPill
            stats
            if let text = card.phaseText {
                OutlinedText(text, size: 18 * scale, fill: .white, width: 3, lines: 2)
                    .accessibilityLabel(Text("Collecting \(text)", comment: "VoiceOver: what a player's phase needs"))
            }
            notes
            if case .away = card.kind, nudge() != nil {
                NudgeButton(name: name, state: nudge, onNudge: onNudge, scale: scale)
                    .padding(.top, 2)
            }
            if case .away = card.kind, canRetire() {
                retireButton
            }
            connection
        }
        .padding(.horizontal, 18 * scale)
        .padding(.top, 22 * scale)
        .padding(.bottom, 20 * scale)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(LinearGradient(
                    colors: [ring.mix(with: .white, by: 0.15), ring.mix(with: Palette.night, by: 0.35), Palette.night],
                    startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
        )
        .overlay(alignment: .topTrailing) { closeButton.offset(x: 10, y: -10) }
        // Taps on the card itself stay on it.
        .contentShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .onTapGesture {}
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
    }

    private var closeButton: some View {
        Button {
            Haptics.shared.tick()
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20 * scale, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 48 * scale, height: 48 * scale)
                .background(Circle().fill(Palette.magenta).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4)))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close", comment: "VoiceOver: close the player card"))
        .accessibilityIdentifier("player.close")
    }

    // MARK: retiring a stalled seat

    /// For a person whose move has waited days: the others can play on without them. Small and
    /// plain beside Nudge, and it asks first, saying what happens.
    private var retireButton: some View {
        Button {
            Haptics.shared.tick()
            confirmingRetire = true
        } label: {
            Text("Play on without \(name)", comment: "Player card: retire the seat of a person whose move has waited days (asks first)")
                .font(.system(size: 16 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 18 * scale)
                .frame(minHeight: 44 * scale)
                .background(Capsule().fill(Palette.magenta).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("player.retire")
        .alert(
            String(localized: "Retire \(name)'s seat?", comment: "Retire confirmation title: whose stalled seat"),
            isPresented: $confirmingRetire
        ) {
            Button(String(localized: "Retire seat", comment: "Retire confirmation: the destructive button"), role: .destructive) {
                onRetire()
            }
            .accessibilityIdentifier("retire.confirm")
            Button(String(localized: "Keep waiting", comment: "Retire confirmation: leave the seat be"), role: .cancel) {}
                .accessibilityIdentifier("retire.cancel")
        } message: {
            Text(retireMessage)
        }
    }

    /// Why it's offered and what happens (§5.13, as a forfeit): the game ends and the last player
    /// wins, or they are out and the rest play on.
    private var retireMessage: String {
        let why = String(
            localized: "It has been \(name)'s move for 3 days.",
            comment: "Retire confirmation: why the seat can be retired")
        let then: String
        switch model.forfeitOutcome(card.seat) {
        case .ends(let winner):
            let other = SeatInfo.name(model.room, winner)
            then = String(
                localized: "The game ends now and \(other) wins.",
                comment: "Retire confirmation: with one other player left, the game ends and they win")
        case .out:
            then = String(
                localized: "\(name) will be out of this game and finish last. Everyone else keeps playing.",
                comment: "Retire confirmation: that seat is out, the rest play on")
        }
        let last = String(localized: "This can't be undone.", comment: "Retire confirmation: it is final")
        return "\(why) \(then) \(last)"
    }

    private var pose: CatPose {
        switch card.kind {
        case .bot, .here: .idle
        case .away(let presence):
            switch presence {
            case .asleep: .asleep
            case .away: .away
            case .awake, nil: .awake
            }
        }
    }

    private var catDisc: some View {
        let side = 124 * scale
        return ZStack(alignment: .bottomTrailing) {
            Image(ArtName.cat(SeatInfo.catIndex(model.room.seats[safe: card.seat]), pose))
                .resizable()
                .scaledToFit()
                .padding(side * 0.06)
                .frame(width: side, height: side)
                .background(Circle().fill(ring.mix(with: .white, by: 0.25)))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 5))
                .shadow(color: card.isTurn ? Palette.orange.opacity(0.9) : .clear, radius: 14)
            if let badge = kindBadge {
                Image(badge).resizable().scaledToFit().frame(width: side * 0.32).offset(x: 4, y: 2)
            }
        }
        .accessibilityHidden(true)
    }

    private var kindBadge: String? {
        switch card.kind {
        case .bot: ArtName.badgeBot
        case .here: ArtName.badgePhone
        case .away: nil
        }
    }

    private var kindText: String {
        switch card.kind {
        case .bot: String(localized: "Computer player", comment: "Player card: a House Cat bot")
        case .here: String(localized: "Human player · this phone", comment: "Player card: someone sharing this phone")
        case .away(let presence):
            switch presence {
            case .asleep: String(localized: "Human player · asleep", comment: "Player card: a person whose app is closed")
            case .away: String(localized: "Human player · away", comment: "Player card: a person who stepped away")
            case .awake, nil: String(localized: "Human player", comment: "Player card: a person on their own phone")
            }
        }
    }

    private var kindPill: some View {
        Text(kindText)
            .font(.system(size: 16 * scale, weight: .black, design: .rounded))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
            .accessibilityIdentifier("player.kind")
    }

    // MARK: the game

    private var stats: some View {
        HStack(spacing: 10 * scale) {
            stat(
                caption: String(localized: "Phase", comment: "Player card: the phase tile's caption"),
                value: card.phaseText == nil ? "10" : String(card.phase + 1), id: "player.phase"
            ) {
                ZStack {
                    Image(ArtName.shelfBadge).resizable().frame(width: 48 * scale, height: 48 * scale)
                    if card.phaseText == nil {
                        Image(ArtName.iconTrophy).resizable().scaledToFit().frame(width: 26 * scale).offset(y: 3)
                    } else {
                        OutlinedText(String(card.phase + 1), size: 22 * scale, fill: Palette.orange, width: 3).offset(y: 3)
                    }
                }
            }
            stat(
                caption: String(localized: "Cards", comment: "Player card: the cards-in-hand tile's caption"),
                value: card.cards.map(String.init) ?? "-", id: "player.cards"
            ) {
                ZStack {
                    Image(uiImage: CardFaceFactory.backImage(ArtName.Habit.back((model.room.look ?? .standard).back)))
                        .resizable().scaledToFit().frame(height: 48 * scale)
                    OutlinedText(card.cards.map(String.init) ?? "-", size: 22 * scale, fill: .white, width: 3)
                }
            }
            stat(
                caption: String(localized: "Points", comment: "Player card: the score tile's caption"),
                value: String(card.score), id: "player.score"
            ) {
                OutlinedText(String(card.score), size: 30 * scale, fill: .white, width: 4)
                    .frame(height: 48 * scale)
            }
        }
    }

    private func stat(caption: String, value: String, id: String, @ViewBuilder art: () -> some View) -> some View {
        VStack(spacing: 4 * scale) {
            art()
            Text(caption)
                .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10 * scale)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.night.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.ink, lineWidth: 3)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(caption) \(value)"))
        .accessibilityValue(value)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var notes: some View {
        if card.laid || card.skipped {
            HStack(spacing: 14 * scale) {
                if card.laid {
                    note(ArtName.badgeLaid, String(localized: "Laid down", comment: "Player card: laid this round's phase down"))
                }
                if card.skipped {
                    note(ArtName.badgeSkip, String(localized: "Skip waiting", comment: "Player card: a skip waits on this player"))
                }
            }
        }
    }

    private func note(_ art: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(art).resizable().scaledToFit().frame(width: 26 * scale, height: 26 * scale)
            Text(text)
                .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: you and them

    @ViewBuilder private var connection: some View {
        switch card.connection {
        case .none:
            EmptyView()
        case .connected(_, let view):
            if let badge = StreakBadge.make(view, all: [], signedIn: true, offersSignIn: false) {
                VStack(spacing: 8 * scale) {
                    caption(String(localized: "Your streak together", comment: "Player card: over your shared streak"))
                    PawBadge(badge: badge, scale: 1.1 * scale)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Your streak together, \(badge.count)", comment: "VoiceOver: the player card's streak"))
                        .accessibilityValue(PawBadge.value(badge))
                        .accessibilityIdentifier("player.streak")
                    if view.best > view.count || view.lifetimeKept > 0 {
                        HStack(spacing: 16 * scale) {
                            if view.best > view.count {
                                record(
                                    ArtName.iconTrophy,
                                    String(localized: "Best \(view.best)", comment: "Player card: your best streak together"))
                            }
                            if view.lifetimeKept > 0 {
                                record(
                                    ArtName.Habit.pawBoth,
                                    String(localized: "\(view.lifetimeKept) days kept", comment: "Player card: days kept together, all time"))
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        case .notYet:
            VStack(spacing: 6 * scale) {
                Image(ArtName.Habit.pawGrey).resizable().scaledToFit().frame(width: 40 * scale)
                caption(String(localized: "Not connected yet", comment: "Player card: nobody here has a streak with this person"))
                Text("Take a turn each and you connect, with a streak of your own.",
                     comment: "Player card: how playing together connects you")
                    .font(.system(size: 15 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("player.notConnected")
        }
    }

    private func caption(_ text: String) -> some View {
        OutlinedText(text, size: 20 * scale, fill: Palette.orange, width: 3)
    }

    private func record(_ art: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(art).resizable().scaledToFit().frame(width: 24 * scale, height: 24 * scale)
            Text(text)
                .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }
}
