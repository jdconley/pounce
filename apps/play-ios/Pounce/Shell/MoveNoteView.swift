import PounceKit
import SwiftUI

/// The words for a move that didn't go (`MoveNote`): one short line, in plain words.
enum MoveNoteCopy {
    /// `turnName`: whose turn it is, when it is someone else's.
    static func text(_ note: MoveNote, turnName: String? = nil) -> String {
        switch note {
        case .notYourTurn:
            if let turnName, !turnName.isEmpty {
                return String(localized: "It's \(turnName)'s turn.", comment: "Table note: a move out of turn, with the name of the player whose turn it is")
            }
            return String(localized: "Not your turn.", comment: "Table note: a move out of turn")
        case .drawFirst:
            return String(localized: "Take a card first.", comment: "Table note: tried to play before drawing")
        case .alreadyDrew:
            return String(localized: "You already took a card.", comment: "Table note: tried to draw twice")
        case .cucumberOnDiscard:
            return String(localized: "A Cucumber can't be taken.", comment: "Table note: the discard pile's top card is a Cucumber")
        case .emptyDiscard:
            return String(localized: "The discard pile is empty.", comment: "Table note: nothing to take from the discard pile")
        case .discardOnDeck:
            return String(localized: "Discard on the face-up pile.", comment: "Table note: a card was put on the deck")
        case .trayFull:
            return String(localized: "That tray is full.", comment: "Table note: a lay-down tray has all its cards")
        case .layDownFirst:
            return String(localized: "Lay down your level first.", comment: "Table note: tried to add to a laid group before laying down")
        case .noFit:
            return String(localized: "That card doesn't fit.", comment: "Table note: a card that can't extend a laid group")
        case .notALevel:
            return String(localized: "Not a whole level yet.", comment: "Table note: the trays don't hold a valid level")
        case .alreadyLaid:
            return String(localized: "Your level is already down.", comment: "Table note: tried to lay down twice")
        case .cucumberOnly:
            return String(localized: "Only a Cucumber can go on a cat.", comment: "Table note: a number card was dropped on another player")
        case .pickACat:
            return String(localized: "Tap a cat to skip.", comment: "Table note: a Cucumber needs a player to aim at")
        case .catSkipped:
            return String(localized: "That cat can't be skipped now.", comment: "Table note: a Cucumber aimed at a player already skipped or out")
        case .yarnNoFit:
            return String(localized: "Yarn can't go there.", comment: "Table note: a wild card moved to a place it can't stand")
        case .roundOver:
            return String(localized: "This round is over.", comment: "Table note: a move after the round ended")
        case .forfeited:
            return String(localized: "You left this game.", comment: "Table note: a move from a seat that forfeited")
        case .notSent:
            return String(localized: "Didn't send. Try again.", comment: "Table note: the move never reached the server")
        case .unknown:
            return String(localized: "That move didn't work.", comment: "Table note: a move refused for a reason the app has no words for")
        }
    }
}

/// A note as the table stage shows it: each one is new, even the same words twice.
struct MoveNoteShown: Equatable {
    let note: MoveNote
    let serial: Int
}

/// One line of words over the table, just above the trays, for a moment: why the move that
/// just wiggled didn't go. It never takes a touch, so play goes on under it.
struct MoveNoteView: View {
    let text: String

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom)
            // Scene space (y up from the bottom of the screen): the strip above the trays.
            let trays = TableLayout(size: full, safeTop: insets.top, safeBottom: insets.bottom, opponents: 1).traysFrame
            Text(verbatim: text)
                .font(.system(.callout, design: .rounded, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.ink)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white, lineWidth: 2))
                .frame(maxWidth: min(geo.size.width - 24, 420))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, max(trays.maxY - insets.bottom + 12, 12))
                .accessibilityIdentifier("table.note")
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .allowsHitTesting(false)
    }
}

/// "Undo" under the discard pile while a discard waits there (`DiscardHold`), with a bar that
/// runs out as the window closes. The rest of the table stays live under it.
struct UndoPill: View {
    let offer: UndoOffer
    let action: () -> Void

    @State private var left: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let fullHeight = geo.size.height + insets.top + insets.bottom
            // Scene space to this view's space.
            let x = offer.pile.midX - insets.leading
            let y = fullHeight - offer.pile.minY - insets.top + 34
            VStack(spacing: 4) {
                PillButton(
                    icon: ArtName.iconBack, color: Palette.lime, size: .small, width: 138,
                    title: String(localized: "Undo", comment: "Table: take back the card just put on the discard pile"),
                    accessibilityLabel: "Undo discard", action: action)
                    .accessibilityIdentifier("table.undo")
                Capsule()
                    .fill(.white)
                    .frame(width: 110 * left, height: 5)
                    .frame(width: 110, alignment: .leading)
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1))
                    .accessibilityHidden(true)
            }
            .position(x: min(max(x, 80), geo.size.width - 80), y: y)
        }
        .onAppear {
            withAnimation(.linear(duration: offer.seconds).paced) { left = 0 }
            UIAccessibility.post(
                notification: .announcement,
                argument: String(localized: "Discarded. Undo for a moment.", comment: "VoiceOver: a discard can still be taken back"))
        }
    }
}

/// The game goes on without this phone: it forfeited every seat, the game started (or ended)
/// before it sat down. A picture, the reason in words, what to do next, and the way home.
struct NotPlayingCard: View {
    enum Reason: String {
        /// Every seat of this phone forfeited; the others play on.
        case out
        /// The game was dealt before this phone took a seat.
        case started
        /// The game is over and this phone wasn't in it.
        case over
    }

    let reason: Reason
    let tableName: String
    let onHome: () -> Void

    @State private var appeared = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var art: String {
        reason == .out ? ArtName.cat(5, .asleep) : ArtName.stateFull
    }

    private var title: String {
        switch reason {
        case .out: String(localized: "You left this game", comment: "Not-playing card title: this phone forfeited")
        case .started: String(localized: "This game already started", comment: "Not-playing card title: arrived after the deal")
        case .over: String(localized: "This game is over", comment: "Not-playing card title: arrived after the end")
        }
    }

    private var message: String {
        switch reason {
        case .out:
            String(
                localized: "The others play on without you.",
                comment: "Not-playing card: after a forfeit")
        case .started:
            String(
                localized: "\(tableName) started before you sat down.",
                comment: "Not-playing card: arrived after the deal; the table's name comes first")
        case .over:
            String(
                localized: "\(tableName) finished before you sat down.",
                comment: "Not-playing card: arrived after the end; the table's name comes first")
        }
    }

    var body: some View {
        ZStack {
            RoomBackground()
            VStack(spacing: 18) {
                Image(art)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 8)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("state.art")
                VStack(spacing: 8) {
                    Text(verbatim: title)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(Palette.violet)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("state.title")
                    Text(verbatim: message)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("state.message")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: 380)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
                .padding(.horizontal, 20)
                PillButton(
                    icon: ArtName.iconHome, color: Palette.orange, size: .large, width: 220,
                    title: String(localized: "Home", comment: "Not-playing card: the pill that goes Home"),
                    accessibilityLabel: "Home", action: onHome)
                    .accessibilityIdentifier("state.home")
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .scaleEffect(sizeClass == .regular ? 1.2 : 1)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.45).paced) { appeared = true }
            Sound.shared.play(ArtName.Sound.sfxNope)
        }
        .accessibilityElement(children: .contain)
        // The ids the wordless card had, so anything looking for that screen still finds it.
        .accessibilityIdentifier(reason == .out ? "state.out" : "state.full")
    }
}
