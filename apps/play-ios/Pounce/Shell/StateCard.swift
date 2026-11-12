import SwiftUI

/// The wordless "something's up" screens (spec §5.12): one big art card and a home pill
/// (offline also gets a retry pill).
struct StateCard: View {
    enum Kind: String {
        /// The room closed (or a known table 404'd): a cat asleep on an empty rug.
        case closed
        /// The House Cat bot got stuck.
        case stalled
        /// The server can't be reached.
        case offline
        /// The game started without this phone, or every seat is taken.
        case full
        /// The server speaks a newer protocol: update the app.
        case update
        /// Too many wrong move codes from this phone: a sad cat, home.
        case locked
        /// This phone forfeited every seat it had here (§5.13) while the others play on.
        case out

        var art: String {
            switch self {
            case .closed: ArtName.stateClosed
            case .stalled: ArtName.stateStalled
            case .offline: ArtName.stateOffline
            case .full: ArtName.stateFull
            case .update: ArtName.stateUpdate
            case .locked: ArtName.cat(3, .terrified)
            case .out: ArtName.cat(5, .asleep)
            }
        }

        var label: LocalizedStringResource {
            switch self {
            case .closed: LocalizedStringResource("Table closed", comment: "State card title: the table no longer exists")
            case .stalled: LocalizedStringResource("The House Cat got stuck", comment: "State card title: the bot stopped playing")
            case .offline: LocalizedStringResource("Can't reach the server", comment: "State card title: no connection")
            case .full: LocalizedStringResource("Game already started", comment: "State card title: every seat is taken")
            case .update: LocalizedStringResource("Update Pounce to play", comment: "State card title: this app version is too old")
            case .locked: LocalizedStringResource("Too many wrong codes", comment: "State card title: room code tries are resting")
            case .out: LocalizedStringResource("You forfeited", comment: "State card title: this phone left the game")
            }
        }

        /// One plain line under the label.
        var detail: LocalizedStringResource {
            switch self {
            case .closed: LocalizedStringResource("Start a new one.", comment: "State card: under Table closed")
            case .stalled: LocalizedStringResource("Start a new game.", comment: "State card: under The House Cat got stuck")
            case .offline: LocalizedStringResource("Check your internet.", comment: "State card: under Can't reach the server")
            case .full: LocalizedStringResource("Every seat is taken.", comment: "State card: under Game already started")
            case .update: LocalizedStringResource("Get it from the App Store.", comment: "State card: under Update Pounce to play")
            case .locked: LocalizedStringResource("Wait, then try again.", comment: "State card: under Too many wrong codes")
            case .out: LocalizedStringResource("The others play on.", comment: "State card: under You forfeited")
            }
        }
    }

    let kind: Kind
    var onRetry: (() -> Void)?
    let onHome: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            RoomBackground()
            ScrollView {
            VStack(spacing: 22) {
                Image(kind.art)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .background(
                        Circle()
                            .fill(RadialGradient(
                                colors: [Palette.sky.opacity(0.9), Palette.violet.opacity(0)],
                                center: .center, startRadius: 10, endRadius: 170))
                            .frame(width: 340, height: 340)
                    )
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 8)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("state.art")
                WordLabel(title: kind.label, detail: kind.detail, alignment: .center, speaks: true)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("state.text")
                HStack(spacing: 18) {
                    if let onRetry {
                        PillButton(icon: ArtName.iconPlay, color: Palette.lime, size: .medium, width: 150,
                                   title: String(localized: "Try again", comment: "State card: retry pill"), accessibilityLabel: "Try again") {
                            onRetry()
                        }
                        .accessibilityIdentifier("state.retry")
                    }
                    PillButton(icon: ArtName.iconHome, color: Palette.orange, size: .medium, width: 150,
                               title: String(localized: "Home", comment: "State card: the pill that goes Home"), accessibilityLabel: "Home") {
                        onHome()
                    }
                    .accessibilityIdentifier("state.home")
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.45).paced) { appeared = true }
            Sound.shared.play(kind == .offline ? ArtName.Sound.sfxThud : ArtName.Sound.sfxNope)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("state.\(kind.rawValue)")
    }
}

/// The room's backdrop: the room art over the night color. The art is an overlay, so its
/// fill-scaling never grows the screen past the size it was offered.
struct RoomBackground: View {
    var body: some View {
        Palette.night
            .overlay {
                Image(ArtName.roomBg)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            }
            .clipped()
            .ignoresSafeArea()
    }
}

/// A small spinning, unraveling yarn ball: the socket is reconnecting. No text.
struct YarnIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.night.opacity(0.85))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
            // The trailing strand.
            Capsule()
                .fill(Palette.magenta)
                .frame(width: 18, height: 4)
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1.5))
                .offset(x: 14, y: 12)
                .rotationEffect(.degrees(reduceMotion ? 0 : (spin ? -20 : 10)))
            Image(ArtName.fxYarn)
                .resizable()
                .scaledToFit()
                .padding(8)
                .rotationEffect(.degrees(spin && !reduceMotion ? 360 : 0))
        }
        .frame(width: 48, height: 48)
        .groupOpacity(reduceMotion && spin ? 0.6 : 1)
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true).paced
                    : .linear(duration: 1.1).repeatForever(autoreverses: false).paced
            ) { spin = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Reconnecting")
        .accessibilityIdentifier("room.reconnecting")
    }
}

/// The round back/home pill in a screen's top-left corner.
struct CornerHomeButton: View {
    var icon: String = ArtName.iconBack
    var label: LocalizedStringKey = "Home"
    let action: () -> Void

    var body: some View {
        PillButton(icon: icon, color: Palette.violet, size: .small, width: 52, accessibilityLabel: label, action: action)
    }
}
