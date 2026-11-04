import PounceKit
import SwiftUI

/// Home's gear (spec §10.5, §12.6): sound, haptics and the turn reminder, How to play, the
/// privacy page, and the account: signed out, the sign-in offer; signed in, your cat with a
/// check, the linked providers, sign out and the trash can.
struct GearSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onRules: () -> Void

    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Spacer()
                        PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .small, accessibilityLabel: "Close") {
                            dismiss()
                        }
                        .accessibilityIdentifier("gear.close")
                    }
                    toggles
                    HStack(spacing: 16) {
                        PillButton(
                            icon: nil, color: Palette.orange, size: .small, width: 156,
                            title: String(localized: "How to play", comment: "Home settings: open the rules"),
                            accessibilityLabel: "How to play"
                        ) {
                            onRules()
                        }
                        .accessibilityIdentifier("settings.rules")
                        RoundIconButton(systemName: "hand.raised.fill", color: Palette.violet, side: 46, accessibilityLabel: "Privacy") {
                            openURL(model.config.endpoint("/privacy"))
                        }
                        .accessibilityIdentifier("gear.privacy")
                    }
                    account
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .overlay {
            if confirmingDelete {
                DeleteConfirmView(
                    cat: model.account.accountPerson?.cat ?? model.people.owner?.cat ?? 0,
                    onBack: { confirmingDelete = false },
                    onDelete: {
                        Task {
                            await model.account.deleteAccount()
                            confirmingDelete = false
                        }
                    })
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25).paced, value: confirmingDelete)
        .accountOverlays()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-gear")
    }

    private var toggles: some View {
        HStack(spacing: 16) {
            PillButton(
                icon: settings.soundOn ? ArtName.iconSoundOn : ArtName.iconSoundOff,
                color: settings.soundOn ? Palette.teal : Palette.violet, size: .small,
                accessibilityLabel: settings.soundOn ? "Sound on" : "Sound off"
            ) {
                settings.soundOn.toggle()
                model.settingsChanged()
            }
            .accessibilityIdentifier("settings.sound")
            PillButton(
                icon: settings.hapticsOn ? ArtName.iconHapticsOn : ArtName.iconHapticsOff,
                color: settings.hapticsOn ? Palette.orange : Palette.violet, size: .small,
                accessibilityLabel: settings.hapticsOn ? "Haptics on" : "Haptics off"
            ) {
                settings.hapticsOn.toggle()
                model.settingsChanged()
            }
            .accessibilityIdentifier("settings.haptics")
            PillButton(
                icon: ArtName.iconBell, color: model.turnReminderOn ? Palette.magenta : Palette.violet, size: .small,
                accessibilityLabel: model.turnReminderOn ? "Turn reminder on" : "Turn reminder off"
            ) {
                settings.turnReminderChoice = !model.turnReminderOn
                model.settingsChanged()
            }
            .saturation(model.turnReminderOn ? 1 : 0.3)
            .accessibilityValue(model.turnReminderOn ? "on" : "off")
            .accessibilityIdentifier("settings.reminder")
        }
    }

    @ViewBuilder private var account: some View {
        let account = model.account!
        if account.isSignedIn {
            AccountCard { confirmingDelete = true }
        } else if account.offersSignIn, let owner = model.people.owner, account.canSignIn(owner.id) {
            SignInOffer(identifier: "gear.signin", width: 230) {
                Task { await account.signIn(owner) }
            }
        }
    }
}
