import PounceKit
import SwiftUI

// Accounts in pictures (spec §10.5, §13.1, §14). No words: cats, icons and Apple's own button.
// Art here is drawn from the existing cats and SF Symbols until the reward-art batch (PR 8).

/// A chunky round button with an SF Symbol, drawn like Home's gear.
struct RoundIconButton: View {
    let systemName: String
    let color: Color
    var side: CGFloat = 54
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            action()
        } label: {
            Circle()
                .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.3), color], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                .overlay {
                    Image(systemName: systemName)
                        .font(.system(size: side * 0.42, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: Palette.ink.opacity(0.6), radius: 0, x: 0, y: 2)
                }
                .frame(width: side, height: side)
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A cat on a disc, optionally with a lime check (signed in).
struct CatDisc: View {
    let cat: Int
    var side: CGFloat = 96
    var color: Color = Palette.sky
    var check = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(LinearGradient(
                    colors: [color.mix(with: .white, by: 0.25), color.mix(with: Palette.violet, by: 0.3)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: max(3, side * 0.05)))
                .overlay {
                    Image(ArtName.cat(cat, .idle)).resizable().scaledToFit().padding(side * 0.1)
                }
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: side * 0.05)
            if check { CheckBadge(side: side * 0.36) }
        }
        .frame(width: side, height: side)
    }
}

/// The lime check that marks a signed-in cat.
struct CheckBadge: View {
    var side: CGFloat = 30

    var body: some View {
        Circle()
            .fill(Palette.lime)
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: max(2, side * 0.1)))
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: side * 0.5, weight: .black))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// "Keep this on all your devices": a cloud with a plus, then the provider buttons (v1: Apple).
struct SignInOffer: View {
    @Environment(AppModel.self) private var model
    let identifier: String
    var width: CGFloat = 250
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(.white, Palette.sky)
                    .shadow(color: Palette.ink.opacity(0.6), radius: 0, x: 0, y: 3)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Palette.ink, Palette.lime)
                    .offset(x: 6, y: 6)
            }
            .accessibilityHidden(true)
            AppleSignInButton(identifier: identifier, action: action)
                .frame(width: width, height: 54)
                .opacity(model.account.busy ? 0.5 : 1)
                .disabled(model.account.busy)
                .overlay { if model.account.busy { YarnIndicator() } }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Palette.ink.opacity(0.35)))
    }
}

/// A linked sign-in provider: its mark on a disc, with a check.
struct ProviderIcon: View {
    let provider: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(.black)
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
                .overlay {
                    Image(systemName: provider == "apple" ? "apple.logo" : "person.badge.key.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
            CheckBadge(side: 22)
        }
        .accessibilityElement()
        .accessibilityLabel(provider == "apple" ? Text("Sign in with Apple") : Text(verbatim: provider))
        .accessibilityIdentifier("gear.provider.\(provider)")
    }
}

/// The gear sheet's account panel: you (your cat with a check), linked providers, sign out and
/// the trash can for deleting the account.
struct AccountCard: View {
    @Environment(AppModel.self) private var model
    let onDelete: () -> Void

    var body: some View {
        let account = model.account!
        HStack(spacing: 16) {
            CatDisc(cat: account.accountPerson?.cat ?? 0, side: 84, color: Palette.teal, check: true)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: account.accountPerson?.name ?? ""))
                .accessibilityValue("signed in")
                .accessibilityIdentifier("gear.account")
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(account.record.providers, id: \.self) { ProviderIcon(provider: $0) }
                    if account.offersSignIn {
                        ForEach(account.linkableProviders, id: \.self) { provider in
                            AppleSignInButton(identifier: "gear.link.\(provider)", style: .white, cornerRadius: 22) {
                                Task { await account.link(provider) }
                            }
                            .frame(width: 150, height: 44)
                        }
                    }
                }
                HStack(spacing: 14) {
                    RoundIconButton(
                        systemName: "rectangle.portrait.and.arrow.right", color: Palette.sky, accessibilityLabel: "Sign out"
                    ) {
                        Task { await account.signOut() }
                    }
                    .accessibilityIdentifier("gear.signout")
                    DeleteButton(action: onDelete)
                        .accessibilityLabel("Delete account")
                        .accessibilityIdentifier("gear.delete")
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Palette.ink.opacity(0.35)))
        .opacity(account.busy ? 0.6 : 1)
    }
}

/// Two cats becoming one (spec §13.1): asked first when linking finds another player, or shown
/// after a sign-in merged this device into its account.
struct MergeView: View {
    @Environment(AppModel.self) private var model
    let merge: AccountModel.Merge
    @State private var together = false

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            VStack(spacing: 28) {
                HStack(spacing: together ? -36 : 18) {
                    CatDisc(cat: merge.mine, side: 120, color: Palette.sky)
                    CatDisc(cat: merge.theirs, side: 120, color: Palette.magenta)
                }
                .animation(.spring(duration: 0.7, bounce: 0.35).paced, value: together)
                Image(systemName: "arrow.down")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(Palette.lime)
                    .shadow(color: Palette.ink, radius: 0, x: 0, y: 3)
                    .accessibilityHidden(true)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Palette.orange, .clear], center: .center, startRadius: 10, endRadius: 120))
                        .frame(width: 230, height: 230)
                    CatDisc(cat: merge.theirs, side: 160, color: Palette.teal, check: !merge.asking)
                }
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: merge.theirName))
                HStack(spacing: 20) {
                    if merge.asking {
                        PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .medium, accessibilityLabel: "Back") {
                            model.account.cancelMerge()
                        }
                        .accessibilityIdentifier("merge.back")
                        PillButton(icon: ArtName.iconCheck, color: Palette.lime, size: .large, width: 190, accessibilityLabel: "Merge") {
                            Task { await model.account.confirmMerge() }
                        }
                        .accessibilityIdentifier("merge.confirm")
                    } else {
                        PillButton(icon: ArtName.iconCheck, color: Palette.lime, size: .large, width: 220, accessibilityLabel: "Done") {
                            model.account.merge = nil
                        }
                        .accessibilityIdentifier("merge.done")
                    }
                }
            }
            .padding(24)
        }
        .task {
            try? await Task.sleep(for: Pace.duration(.milliseconds(250)))
            together = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-merge")
    }
}

/// "Delete your account?": your cat over the trash can, back or the trash.
struct DeleteConfirmView: View {
    let cat: Int
    let onBack: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            VStack(spacing: 30) {
                ZStack(alignment: .bottom) {
                    CatDisc(cat: cat, side: 170, color: Palette.magenta)
                    Circle()
                        .fill(LinearGradient(colors: [Palette.refuse.mix(with: .white, by: 0.25), Palette.refuse], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 5))
                        .overlay { Image(ArtName.iconDelete).resizable().scaledToFit().padding(18) }
                        .frame(width: 86, height: 86)
                        .offset(y: 44)
                }
                .padding(.bottom, 44)
                .accessibilityHidden(true)
                HStack(spacing: 22) {
                    PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .large, width: 150, accessibilityLabel: "Back") {
                        onBack()
                    }
                    .accessibilityIdentifier("delete.back")
                    PillButton(icon: ArtName.iconDelete, color: Palette.refuse, size: .large, width: 150, accessibilityLabel: "Delete account") {
                        onDelete()
                    }
                    .accessibilityIdentifier("delete.confirm")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-delete")
    }
}

/// After deleting: where to stop Apple sign-in for Pounce in iOS Settings, as a picture (spec
/// §13.1): Settings, then your name, then Sign in with Apple, then Pounce.
struct SettingsPathView: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            VStack(spacing: 34) {
                ViewThatFits {
                    HStack(spacing: 10) { steps }
                    VStack(spacing: 10) { steps }
                }
                PillButton(icon: ArtName.iconCheck, color: Palette.lime, size: .large, width: 220, accessibilityLabel: "Done") {
                    onDone()
                }
                .accessibilityIdentifier("settings.path.done")
            }
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("In Settings, open your name, then Sign in with Apple, then Pounce")
        .accessibilityIdentifier("settings.path")
    }

    @ViewBuilder private var steps: some View {
        tile(Image(systemName: "gearshape.fill"), colors: [Color(white: 0.75), Color(white: 0.45)])
        arrow
        tile(Image(systemName: "person.crop.circle.fill"), colors: [Palette.sky, Palette.violet])
        arrow
        tile(Image(systemName: "apple.logo"), colors: [Color(white: 0.2), .black])
        arrow
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Palette.violet, Palette.magenta], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
            Image(ArtName.cat(0, .idle)).resizable().scaledToFit().padding(8)
        }
        .frame(width: 76, height: 76)
    }

    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 26, weight: .black))
            .foregroundStyle(Palette.lime)
            .shadow(color: Palette.ink, radius: 0, x: 0, y: 2)
    }

    private func tile(_ image: Image, colors: [Color]) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
            .overlay { image.font(.system(size: 38, weight: .bold)).foregroundStyle(.white) }
            .frame(width: 76, height: 76)
    }
}

/// How old is the new person? Whoever adds them taps a kitten, a young cat or a grown cat
/// (spec §14.1). The picture's size is the age.
struct AgeBandPicker: View {
    let cat: Int
    let onBack: () -> Void
    let onPick: (AgeBand) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.violet, Palette.night], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 34) {
                HStack(alignment: .bottom, spacing: sizeClass == .regular ? 36 : 10) {
                    choice(.kitten, scale: 0.5, color: Palette.lime)
                    choice(.teen, scale: 0.75, color: Palette.sky)
                    choice(.adult, scale: 1, color: Palette.orange)
                }
                PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .medium, accessibilityLabel: "Back") {
                    onBack()
                }
                .accessibilityIdentifier("age.band.back")
            }
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-ageBand")
    }

    private func choice(_ band: AgeBand, scale: CGFloat, color: Color) -> some View {
        let base: CGFloat = sizeClass == .regular ? 220 : 96
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            onPick(band)
        } label: {
            VStack {
                Spacer(minLength: 0)
                Image(ArtName.cat(cat, band == .kitten ? .celebrate : .idle))
                    .resizable().scaledToFit()
                    .frame(width: base * scale, height: base * scale)
                    .shadow(color: Palette.ink.opacity(0.4), radius: 0, x: 0, y: 4)
            }
            .frame(width: base * 1.08, height: base * 1.2)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.25), color.mix(with: Palette.violet, by: 0.3)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4))
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(band == .kitten ? "Under 13" : band == .teen ? "13 to 17" : "18 or older")
        .accessibilityIdentifier("age.band.\(band.rawValue)")
    }
}

/// The merge picture and the Settings path, over whichever sheet started them.
struct AccountOverlays: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .overlay {
                if let merge = model.account.merge {
                    MergeView(merge: merge).transition(.opacity)
                } else if model.account.showSettingsPath {
                    SettingsPathView { model.account.showSettingsPath = false }.transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25).paced, value: model.account.merge)
            .animation(.easeOut(duration: 0.25).paced, value: model.account.showSettingsPath)
    }
}

extension View {
    func accountOverlays() -> some View { modifier(AccountOverlays()) }
}
