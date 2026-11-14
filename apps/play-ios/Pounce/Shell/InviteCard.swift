import SwiftUI

/// A Messages link that can't be opened, in words instead of a silent thump: it no longer works
/// (it expired, someone played on it, or it went to someone else), so the person knows to ask
/// again; or the server can't be reached to look it up, so they can try again.
struct InviteCard: View {
    enum Kind: Equatable {
        case expired
        /// The link's token, to look it up again.
        case offline(token: String)
    }

    let kind: Kind

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var scale: CGFloat { sizeClass == .regular ? 1.3 : 1 }

    private var title: String {
        switch kind {
        case .expired: String(localized: "Invite expired", comment: "Card: a Messages invite link that no longer works")
        case .offline: String(localized: "Can't reach Pounce", comment: "Card: an invite link that can't be looked up, no connection")
        }
    }

    private var detail: LocalizedStringResource {
        switch kind {
        case .expired: LocalizedStringResource("Ask for a new one.", comment: "Card: what to do about an expired invite link")
        case .offline: LocalizedStringResource("Check your internet.", comment: "Card: what to do when an invite can't be looked up")
        }
    }

    var body: some View {
        ZStack {
            Palette.night.opacity(0.9).ignoresSafeArea().onTapGesture(perform: close)
            VStack(spacing: 16 * scale) {
                Image(kind == .expired ? ArtName.Habit.pounceBellAsleep : ArtName.stateOffline).resizable().scaledToFit()
                    .frame(width: 120 * scale, height: 120 * scale)
                    .accessibilityHidden(true)
                OutlinedText(title, size: 30 * scale, fill: .white, width: 3, lines: 2)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                buttons
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .frame(maxWidth: 440 * scale)
            .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Palette.night)
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5)))
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(kind == .expired ? "card-expiredInvite" : "card-offlineInvite")
    }

    @ViewBuilder private var buttons: some View {
        switch kind {
        case .expired:
            PillButton(
                icon: ArtName.iconCheck, color: Palette.teal, size: .medium,
                title: String(localized: "OK", comment: "Card: closes the expired invite card"),
                accessibilityLabel: "OK", action: close)
                .accessibilityIdentifier("expiredInvite.ok")
        case .offline(let token):
            HStack(spacing: 14 * scale) {
                PillButton(icon: ArtName.iconClose, color: Palette.violet, size: .medium, accessibilityLabel: "Close", action: close)
                    .accessibilityIdentifier("offlineInvite.close")
                PillButton(
                    icon: ArtName.Habit.iconReplay, color: Palette.lime, size: .medium,
                    title: String(localized: "Try again", comment: "Card: looks up an invite link again after no connection"),
                    accessibilityLabel: "Try again") {
                        model.retryInvite(token)
                    }
                    .accessibilityIdentifier("offlineInvite.retry")
            }
        }
    }

    private func close() {
        switch kind {
        case .expired: model.expiredInviteShown = false
        case .offline: model.offlineInvite = nil
        }
    }
}
