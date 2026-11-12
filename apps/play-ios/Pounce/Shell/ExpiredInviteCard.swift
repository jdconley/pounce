import SwiftUI

/// A Messages link that no longer works (it expired, someone played on it, or it went to
/// someone else): a worded card instead of a silent thump, so the person knows to ask again.
struct ExpiredInviteCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var scale: CGFloat { sizeClass == .regular ? 1.3 : 1 }

    var body: some View {
        ZStack {
            Palette.night.opacity(0.9).ignoresSafeArea().onTapGesture(perform: close)
            VStack(spacing: 16 * scale) {
                Image(ArtName.Habit.pounceBellAsleep).resizable().scaledToFit()
                    .frame(width: 120 * scale, height: 120 * scale)
                    .accessibilityHidden(true)
                OutlinedText(
                    String(localized: "Invite expired", comment: "Card: a Messages invite link that no longer works"),
                    size: 30 * scale, fill: .white, width: 3, lines: 2)
                    .accessibilityAddTraits(.isHeader)
                Text("Ask for a new one.", comment: "Card: what to do about an expired invite link")
                    .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(
                    icon: ArtName.iconCheck, color: Palette.teal, size: .medium,
                    title: String(localized: "OK", comment: "Card: closes the expired invite card"),
                    accessibilityLabel: "OK", action: close)
                    .accessibilityIdentifier("expiredInvite.ok")
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .frame(maxWidth: 440 * scale)
            .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Palette.night)
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5)))
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-expiredInvite")
    }

    private func close() { model.expiredInviteShown = false }
}
