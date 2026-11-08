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

        var label: LocalizedStringKey {
            switch self {
            case .closed: "This table is closed"
            case .stalled: "The House Cat got stuck"
            case .offline: "Can't reach the server"
            case .full: "This table is full or already playing"
            case .update: "Update the app to play"
            case .locked: "Too many wrong codes. Try again later"
            case .out: "You forfeited this game. The others are still playing"
            }
        }
    }

    let kind: Kind
    var onRetry: (() -> Void)?
    let onHome: () -> Void

    @State private var appeared = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            RoomBackground()
            VStack(spacing: 28) {
                Image(kind.art)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
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
                    .accessibilityLabel(kind.label)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("state.art")
                HStack(spacing: 18) {
                    if let onRetry {
                        PillButton(icon: ArtName.iconPlay, color: Palette.lime, size: .large, accessibilityLabel: "Try again") {
                            onRetry()
                        }
                        .accessibilityIdentifier("state.retry")
                    }
                    PillButton(icon: ArtName.iconHome, color: Palette.orange, size: .large, accessibilityLabel: "Home") {
                        onHome()
                    }
                    .accessibilityIdentifier("state.home")
                }
            }
            // Bigger on a roomy (iPad) screen; the phone keeps its size.
            .scaleEffect(sizeClass == .regular ? 1.3 : 1)
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
        .opacity(reduceMotion && spin ? 0.6 : 1)
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
