import PounceKit
import SwiftUI

/// Adding someone (trophy room design §4). On most phones: a Messages link (PR 5's link pounce,
/// target "new") through the system share sheet, and its QR code for in person: the other phone's
/// Camera opens Pounce through the universal link, and Play there makes the connection at once
/// (D2). On a kitten's device no link ever goes out (§14.1): it shows a new table's room code and
/// its QR instead, for in-person play only. No contacts, no usernames; one line says how long a link lasts.
struct InviteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private enum Loaded: Equatable {
        case loading
        case link(URL)
        case code(String)
        /// No link or table to show (the bell rests, or the server can't be reached): tap to try again.
        case resting
    }

    @State private var loaded: Loaded = .loading
    @State private var shareShown = false
    @State private var shake = 0
    @State private var attempt = 0

    private var mode: InviteLink.Mode { InviteLink.mode(model.limits) }
    private var scale: CGFloat { sizeClass == .regular ? 1.3 : 1 }

    var body: some View {
        ZStack {
            Palette.night.opacity(0.9).ignoresSafeArea().onTapGesture(perform: close)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18 * scale) {
                    header
                    content
                    buttons
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 18)
                .frame(maxWidth: 520 * scale)
                .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Palette.night)
                    .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5)))
                .padding(16)
                .wiggle(trigger: shake)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center, for: .alignment)
        }
        .background {
            if case .link(let url) = loaded {
                ShareRoom(isPresented: $shareShown, url: url, tableName: model.people.owner?.name ?? "",
                          // The sender's own cat, as the invite page shows it.
                          catArt: ArtName.cat(model.people.owner?.cat ?? 0, .awake))
            }
        }
        .task(id: attempt) { await load() }
        .accessibilityElement(children: .contain)
        .accessibilityValue(mode == .link ? "link" : "code")
        .accessibilityIdentifier("sheet-invite")
    }

    private var header: some View {
        HStack(spacing: 10 * scale) {
            Image(ArtName.cat(model.people.owner?.cat ?? 0, .awake)).resizable().scaledToFit()
                .frame(width: 96 * scale, height: 96 * scale)
            Image(ArtName.iconInvite).resizable().scaledToFit()
                .frame(width: 64 * scale, height: 64 * scale)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var content: some View {
        switch loaded {
        case .loading:
            Image(ArtName.Habit.pounceBell).resizable().scaledToFit()
                .frame(width: 120 * scale, height: 120 * scale)
                .bounceLoop(active: true)
                .frame(height: 260 * scale)
        case .link(let url):
            VStack(spacing: 10 * scale) {
                qr(url.absoluteString)
                Text("Works for 7 days, or until you play.",
                     comment: "Invite sheet: under the QR code, how long the invite link lasts")
                    .font(.system(size: 17 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("invite.note")
            }
        case .code(let code):
            VStack(spacing: 14 * scale) {
                codeCapsule(code)
                qr(DeepLink.shareURL(code: code).absoluteString)
            }
        case .resting:
            Button {
                Haptics.shared.tick()
                attempt += 1
            } label: {
                Image(ArtName.Habit.pounceBellAsleep).resizable().scaledToFit()
                    .frame(width: 140 * scale, height: 140 * scale)
                    .frame(height: 260 * scale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Try again", comment: "VoiceOver: the invite sheet's sleeping bell"))
            .accessibilityIdentifier("invite.resting")
        }
    }

    /// The QR in its frame, cat ears up.
    private func qr(_ text: String) -> some View {
        let side = 200 * scale
        // The frame's opening sits a little below its middle (the ears are on top).
        let frame = side * 1.66
        return ZStack {
            QRTile(text: text, side: side)
            Image(ArtName.Habit.qrFrame).resizable().scaledToFit()
                .frame(width: frame, height: frame)
                .offset(y: -frame * 0.055)
                .allowsHitTesting(false)
        }
        .frame(width: frame, height: frame)
        .accessibilityElement()
        .accessibilityLabel(Text("QR code", comment: "VoiceOver: the invite sheet's QR code"))
        .accessibilityAddTraits(.isImage)
        .accessibilityValue(text)
        .accessibilityIdentifier("invite.qr")
    }

    private func codeCapsule(_ code: String) -> some View {
        OutlinedText(code, size: 46 * scale, fill: .white, width: 3.5)
            .padding(.horizontal, 22)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(LinearGradient(
                        colors: [Palette.teal.mix(with: .white, by: 0.25), Palette.teal, Palette.teal.mix(with: Palette.ink, by: 0.35)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 5))
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6))
            .accessibilityElement()
            .accessibilityLabel(Text("Room code \(code.map(String.init).joined(separator: " "))"))
            .accessibilityValue(code)
            .accessibilityIdentifier("invite.code")
    }

    private var buttons: some View {
        HStack(spacing: 16 * scale) {
            PillButton(icon: ArtName.iconClose, color: Palette.violet, size: .medium, accessibilityLabel: "Close", action: close)
                .accessibilityIdentifier("invite.close")
            switch loaded {
            case .link:
                ArtIconButton(icon: ArtName.iconShare, color: Palette.sky, size: 64 * scale, label: "Send a link") {
                    shareShown = true
                }
                // No nudges to share links for a teen (§14.1).
                .bounceLoop(active: model.ageBand != .teen)
                .accessibilityIdentifier("invite.share")
            case .code(let code):
                PillButton(icon: ArtName.iconPlay, color: Palette.lime, size: .large, width: 150 * scale, accessibilityLabel: "Play") {
                    Haptics.shared.success()
                    model.inviteTableUsed()
                    model.open(code: code, intent: .create)
                }
                .accessibilityIdentifier("invite.play")
            case .loading, .resting:
                EmptyView()
            }
        }
    }

    private func load() async {
        loaded = .loading
        switch mode {
        case .link:
            if let url = await model.inviteURL() {
                loaded = .link(url)
            } else {
                fail()
            }
        case .code:
            if let code = await model.inviteTable() {
                loaded = .code(code)
            } else {
                fail()
            }
        }
    }

    private func fail() {
        loaded = .resting
        shake += 1
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope)
    }

    private func close() {
        model.inviteShown = false
    }
}
