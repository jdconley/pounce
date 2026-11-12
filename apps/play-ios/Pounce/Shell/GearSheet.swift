import PounceKit
import SwiftUI

/// Home's gear (spec §10.5, §12.6): sound, haptics and the turn reminder, the notification
/// settings panel (reminders, their time, quiet hours, last chance), How to play, the
/// privacy page, Rate Pounce (an adult's device only), and the account: signed out, the sign-in
/// offer; signed in, your cat with a check, the linked providers, sign out and the trash can.
struct GearSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onRules: () -> Void

    @State private var confirmingDelete = false
    /// Reset tips was just tapped: the pill says Done for a moment.
    @State private var tipsReset = false
    @State private var showingKittens = false

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
                    // A kitten's own device: the bell a grown-up unlocks (parent consent, PR 9).
                    if model.ageBand == .kitten {
                        KittenBellView()
                    }
                    // A wrong age put right by Apple's answer (launch review).
                    if AgeCorrection.offered(model.ageRecord) {
                        AgeCorrectionRow()
                    }
                    // The notification settings (§12.6), the same panel as the Us screen's gear.
                    NotifyPanel()
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 16) {
                        PillButton(
                            icon: nil, color: Palette.orange, size: .small, width: 156,
                            title: String(localized: "How to play", comment: "Home settings: open the rules"),
                            accessibilityLabel: "How to play"
                        ) {
                            model.tips.used("settings.rules")
                            onRules()
                        }
                        .accessibilityIdentifier("settings.rules")
                        RoundIconButton(systemName: "hand.raised.fill", color: Palette.violet, side: 46, accessibilityLabel: "Privacy") {
                            openURL(model.config.endpoint("/privacy"))
                        }
                        .accessibilityIdentifier("gear.privacy")
                    }
                    // Every tip on this phone comes back, for everyone (`Tips.swift`, the table coach).
                    PillButton(
                        icon: tipsReset ? ArtName.iconCheck : nil, color: Palette.sky, size: .small, width: 156,
                        title: tipsReset
                            ? String(localized: "Done", comment: "Gear sheet: Reset tips, just tapped")
                            : String(localized: "Reset tips", comment: "Gear sheet: show every tip again"),
                        accessibilityLabel: "Reset tips"
                    ) {
                        guard !tipsReset else { return }
                        model.replayTips()
                        tipsReset = true
                        UIAccessibility.post(notification: .announcement, argument: String(
                            localized: "Tips are back.", comment: "VoiceOver: after Reset tips"))
                        Task {
                            try? await Task.sleep(for: Pace.duration(.seconds(2)))
                            tipsReset = false
                        }
                    }
                    .accessibilityIdentifier("gear.resetTips")
                    // An adult's way to the App Store's review page (never shown to a kitten or a teen).
                    if model.offersRating {
                        PillButton(
                            icon: nil, color: Palette.magenta, size: .small, width: 230,
                            title: String(localized: "Rate Pounce", comment: "Gear sheet: open the App Store's review page for the app"),
                            accessibilityLabel: "Rate Pounce"
                        ) {
                            openURL(RatingPrompt.writeReviewURL)
                        }
                        .accessibilityIdentifier("gear.rate")
                    }
                    // A signed-in adult's kittens (parent consent, PR 9), behind words.
                    if model.isParent {
                        PillButton(
                            icon: ArtName.Habit.iconKittens, color: Palette.teal, size: .small, width: 230,
                            title: String(localized: "Add a child", comment: "Gear sheet: open the parent's kittens panel"),
                            accessibilityLabel: "Add a child"
                        ) {
                            showingKittens = true
                        }
                        .accessibilityIdentifier("gear.kittens")
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
                let signedIn = model.account.isSignedIn
                let person = model.account.accountPerson ?? model.people.owner
                DeleteConfirmView(
                    cat: person?.cat ?? 0, name: person?.name ?? "", signedIn: signedIn,
                    onBack: { confirmingDelete = false },
                    onDelete: {
                        Task {
                            // Signed in: the account. Otherwise the player on this phone (a kitten's too).
                            await model.account.deleteAccount(personId: signedIn ? nil : model.people.owner?.id)
                            confirmingDelete = false
                        }
                    })
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25).paced, value: confirmingDelete)
        .tipHost(.gear, paused: confirmingDelete || showingKittens)
        .accountOverlays()
        .sheet(isPresented: $showingKittens) { KittensSheet() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-gear")
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 14) {
            WordRow(title: LocalizedStringResource("Sound", comment: "Gear sheet: the sound toggle's label")) {
                PillButton(
                    icon: settings.soundOn ? ArtName.iconSoundOn : ArtName.iconSoundOff,
                    color: settings.soundOn ? Palette.teal : Palette.violet, size: .small,
                    accessibilityLabel: settings.soundOn ? "Sound on" : "Sound off"
                ) {
                    settings.soundOn.toggle()
                    model.settingsChanged()
                }
                .accessibilityIdentifier("settings.sound")
            }
            WordRow(title: LocalizedStringResource("Buzz", comment: "Gear sheet: the haptics toggle's label")) {
                PillButton(
                    icon: settings.hapticsOn ? ArtName.iconHapticsOn : ArtName.iconHapticsOff,
                    color: settings.hapticsOn ? Palette.orange : Palette.violet, size: .small,
                    accessibilityLabel: settings.hapticsOn ? "Haptics on" : "Haptics off"
                ) {
                    settings.hapticsOn.toggle()
                    model.settingsChanged()
                }
                .accessibilityIdentifier("settings.haptics")
            }
            WordRow(title: LocalizedStringResource("Turn alerts", comment: "Gear sheet: the toggle for a notification when a game waits on you")) {
                PillButton(
                    icon: ArtName.iconBell, color: model.turnReminderOn ? Palette.magenta : Palette.violet, size: .small,
                    accessibilityLabel: model.turnReminderOn ? "Turn reminder on" : "Turn reminder off"
                ) {
                    settings.turnReminderChoice = !model.turnReminderOn
                    model.tips.used("settings.reminder")
                    model.settingsChanged()
                }
                .saturation(model.turnReminderOn ? 1 : 0.3)
                .accessibilityValue(model.turnReminderOn ? "on" : "off")
                .accessibilityIdentifier("settings.reminder")
                .tipTarget("settings.reminder")
            }
        }
    }

    @ViewBuilder private var account: some View {
        let account = model.account!
        if account.isSignedIn {
            AccountCard { confirmingDelete = true }
        } else {
            VStack(spacing: 14) {
                if account.offersSignIn, let owner = model.people.owner, account.canSignIn(owner.id) {
                    SignInOffer(identifier: "gear.signin", width: 230) {
                        Task { await account.signIn(owner) }
                    }
                }
                // Deleting isn't only for accounts (guideline 5.1.1(v)): a guest or a kitten's player too.
                if model.people.owner != nil {
                    GuestDeleteRow { confirmingDelete = true }
                        .disabled(account.busy)
                }
            }
        }
    }
}
