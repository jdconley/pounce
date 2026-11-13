import PounceKit
import SwiftUI

/// Settings, from Home's gear (spec §10.5, §12.6). One list in groups, the everyday switches
/// first: Play (sound, buzz), Alerts (turn alerts, reminders, the live table, and pages for the
/// reminder times and quiet hours; a kitten's bell and daily reminder instead), Family (a parent's
/// kids' alerts), Help (How to play, tips, Rate Pounce for an adult, privacy) and Account (your
/// cat, with its own page: sign in or the linked providers, sign out, and delete). The X closes
/// the sheet; a page inside it has a back arrow.
struct GearSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    let onRules: () -> Void

    enum Page: Hashable {
        case main, account, quietHours, reminderTimes
    }

    @State private var page: Page = .main
    @State private var confirmingDelete = false
    /// Show tips again was just tapped: the row says Done for a moment.
    @State private var tipsReset = false
    @State private var showingKittens = false

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(
                title: title,
                onBack: page == .main ? nil : { page = .main }, backID: "settings.back",
                onClose: { dismiss() }, closeID: "gear.close")
            ZStack {
                switch page {
                case .main:
                    scroll { main }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                case .account:
                    scroll { account }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .quietHours:
                    scroll { quietHours(model.notifySettings) }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .reminderTimes:
                    scroll { reminderTimes(model.notifySettings) }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .animation(.spring(duration: 0.4, bounce: 0.2).paced, value: page)
        .background(Palette.night.ignoresSafeArea())
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
        .tipHost(.gear, paused: confirmingDelete || showingKittens || page != .main)
        .accountOverlays()
        .sheet(isPresented: $showingKittens) { KittensSheet() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-gear")
    }

    private var title: String {
        switch page {
        case .main: String(localized: "Settings", comment: "Settings sheet: title")
        case .account: String(localized: "Account", comment: "Settings: the account page's title")
        case .quietHours: String(localized: "Quiet hours", comment: "Settings: the quiet hours page's title")
        case .reminderTimes: String(localized: "Reminder times", comment: "Settings: the reminder times page's title")
        }
    }

    private func scroll(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: the list

    private var main: some View {
        VStack(alignment: .leading, spacing: 22) {
            play
            alerts
            if model.isParent { family }
            help
            accountGroup
        }
    }

    private var play: some View {
        SettingsGroup(title: Text("Play", comment: "Settings: the group with sound and buzz")) {
            SettingsRow(
                .art(settings.soundOn ? ArtName.iconSoundOn : ArtName.iconSoundOff), color: Palette.teal,
                title: Text("Sound", comment: "Settings: the sound switch"),
                end: .toggle(settings.soundOn, Palette.teal)
            ) {
                settings.soundOn.toggle()
                model.settingsChanged()
            }
            .accessibilityIdentifier("settings.sound")
            SettingsRow(
                .art(settings.hapticsOn ? ArtName.iconHapticsOn : ArtName.iconHapticsOff), color: Palette.orange,
                title: Text("Buzz", comment: "Settings: the haptics switch"),
                end: .toggle(settings.hapticsOn, Palette.orange)
            ) {
                settings.hapticsOn.toggle()
                model.settingsChanged()
            }
            .accessibilityIdentifier("settings.haptics")
        }
    }

    private var alerts: some View {
        let s = model.notifySettings
        let kitten = model.ageBand == .kitten
        return SettingsGroup(title: Text("Alerts", comment: "Settings: the notifications group")) {
            // A kitten's own device: the bell a grown-up unlocks (parent consent, PR 9).
            if kitten {
                KittenBellView(scale: 0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)
            }
            SettingsRow(
                .art(ArtName.iconBell), color: Palette.magenta,
                title: Text("Turn alerts", comment: "Settings: the switch for a notification when a game waits on you"),
                detail: Text("When it's your move", comment: "Settings: what turn alerts send"),
                end: .toggle(model.turnReminderOn, Palette.magenta)
            ) {
                settings.turnReminderChoice = !model.turnReminderOn
                model.tips.used("settings.reminder")
                model.settingsChanged()
            }
            .accessibilityIdentifier("settings.reminder")
            .tipTarget("settings.reminder")
            if kitten {
                SettingsRow(
                    .art(ArtName.Habit.iconClock), color: Palette.violet,
                    title: Text("Daily reminder", comment: "Settings: a kitten's daily reminder switch"),
                    detail: Text("At \(KittenReminder.time.text)", comment: "Settings: the kitten's daily reminder time, e.g. 5:00 PM"),
                    end: .toggle(model.kittenDailyOn, Palette.violet)
                ) {
                    model.setKittenDaily(!model.kittenDailyOn)
                }
                .accessibilityIdentifier("notify.kitten")
            } else {
                SettingsRow(
                    .art(ArtName.Habit.iconClock), color: Palette.violet,
                    title: Text("Reminders", comment: "Settings: the daily reminders switch"),
                    detail: Text("Daily, plus one before bed", comment: "Settings: what the reminders switch sends"),
                    end: .toggle(s.reminders, Palette.violet)
                ) {
                    let on = !s.reminders
                    model.setNotify(NotifyKey.reminders, .bool(on))
                    if on { model.setNotify(NotifyKey.lastChance, .bool(true)) }
                }
                .accessibilityIdentifier("notify.reminders")
                // The reminder time is learned, unless the band fixes it (a teen's dials).
                if !s.auto {
                    let weekday = s.clamped(s.weekday).text, weekend = s.clamped(s.weekend).text
                    SettingsRow(
                        .art(ArtName.Habit.iconWeekday), color: Palette.violet,
                        title: Text("Reminder times", comment: "Settings: opens the reminder time dials"),
                        value: Text(verbatim: weekday == weekend ? weekday : "\(weekday), \(weekend)")
                    ) {
                        page = .reminderTimes
                    }
                    .accessibilityIdentifier("settings.page.reminderTimes")
                }
                // The live table on the Lock Screen (§11.3): on by default, the game itself.
                SettingsRow(
                    .art(ArtName.Habit.iconLiveTable), color: Palette.teal,
                    title: Text("Live table", comment: "Settings: the live table switch"),
                    detail: Text("On the Lock Screen", comment: "Settings: where the live table shows"),
                    end: .toggle(s.liveTable, Palette.teal)
                ) {
                    model.setNotify(NotifyKey.liveTable, .bool(!s.liveTable))
                }
                .accessibilityIdentifier("notify.liveTable")
                SettingsRow(
                    .art(ArtName.Habit.iconMoon), color: Palette.violet,
                    title: Text("Quiet hours", comment: "Settings: opens the quiet hours dials"),
                    value: Text(verbatim: "\(s.quietStart.text)–\(s.quietEnd.text)")
                ) {
                    page = .quietHours
                }
                .accessibilityIdentifier("settings.page.quietHours")
            }
        }
    }

    /// A signed-in adult's kids (parent consent, PR 9).
    private var family: some View {
        SettingsGroup(title: Text("Family", comment: "Settings: the group with a parent's kids")) {
            SettingsRow(
                .art(ArtName.Habit.iconKittens), color: Palette.teal,
                title: Text("Kids' alerts", comment: "Settings: opens the parent's kids panel")
            ) {
                showingKittens = true
            }
            .accessibilityIdentifier("gear.kittens")
        }
    }

    private var help: some View {
        SettingsGroup(title: Text("Help", comment: "Settings: the group with How to play, tips and privacy")) {
            SettingsRow(
                .symbol("book.fill"), color: Palette.orange,
                title: Text("How to play", comment: "Settings: open the rules")
            ) {
                model.tips.used("settings.rules")
                onRules()
            }
            .accessibilityIdentifier("settings.rules")
            // Every tip on this phone comes back, for everyone (`Tips.swift`, the table coach).
            SettingsRow(
                .symbol("lightbulb.fill"), color: Palette.sky,
                title: Text("Show tips again", comment: "Settings: bring every tip back"),
                value: tipsReset ? Text("Done", comment: "Settings: Show tips again, just tapped") : nil,
                end: .action
            ) {
                guard !tipsReset else { return }
                model.replayTips()
                tipsReset = true
                UIAccessibility.post(notification: .announcement, argument: String(
                    localized: "Tips are back.", comment: "VoiceOver: after Show tips again"))
                Task {
                    try? await Task.sleep(for: Pace.duration(.seconds(2)))
                    tipsReset = false
                }
            }
            .accessibilityIdentifier("gear.resetTips")
            // An adult's way to the App Store's review page (never shown to a kitten or a teen).
            if model.offersRating {
                SettingsRow(
                    .symbol("star.fill"), color: Palette.magenta,
                    title: Text("Rate Pounce", comment: "Settings: open the App Store's review page for the app"),
                    end: .external
                ) {
                    openURL(RatingPrompt.writeReviewURL)
                }
                .accessibilityIdentifier("gear.rate")
            }
            SettingsRow(
                .symbol("hand.raised.fill"), color: Palette.violet,
                title: Text("Privacy", comment: "Settings: open the privacy page"),
                end: .external
            ) {
                openURL(model.config.endpoint("/privacy"))
            }
            .accessibilityIdentifier("gear.privacy")
        }
    }

    /// You, as a row: your cat (with a check when signed in) and your name; its page has the rest.
    private var accountGroup: some View {
        let account = model.account!
        let person = account.accountPerson ?? model.people.owner
        let status: Text? = account.isSignedIn
            ? Text("Signed in", comment: "Settings: the account row when signed in")
            : account.offersSignIn ? Text("Not signed in", comment: "Settings: the account row when not signed in") : nil
        return SettingsGroup(title: Text("Account", comment: "Settings: the account group")) {
            SettingsRow(
                title: person.map { Text(verbatim: $0.name) } ?? Text("Account", comment: "Settings: the account row with no name"),
                detail: status
            ) {
                CatDisc(cat: person?.cat ?? 0, side: 42, color: Palette.teal, check: account.isSignedIn)
                    .accessibilityHidden(true)
            } action: {
                page = .account
            }
            .accessibilityIdentifier("settings.page.account")
            // A wrong age put right by Apple's answer (launch review).
            if AgeCorrection.offered(model.ageRecord) {
                AgeCorrectionRow()
                    .padding(8)
            }
        }
    }

    // MARK: pages

    /// Signed in: your cat with a check, the linked providers, sign out, delete. Otherwise the
    /// sign-in offer and delete (deleting isn't only for accounts, guideline 5.1.1(v): a guest or
    /// a kitten's player too).
    private var account: some View {
        let account = model.account!
        let person = account.accountPerson ?? model.people.owner
        return VStack(spacing: 22) {
            VStack(spacing: 10) {
                if account.isSignedIn {
                    CatDisc(cat: person?.cat ?? 0, side: 110, color: Palette.teal, check: true)
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: person?.name ?? ""))
                        .accessibilityValue("signed in")
                        .accessibilityIdentifier("gear.account")
                } else {
                    CatDisc(cat: person?.cat ?? 0, side: 110, color: Palette.sky)
                        .accessibilityHidden(true)
                }
                if let name = person?.name {
                    OutlinedText(name, size: 28, fill: .white, width: 3)
                        .accessibilityHidden(account.isSignedIn)
                }
            }
            if account.isSignedIn {
                providers(account)
            } else if account.offersSignIn, let owner = model.people.owner, account.canSignIn(owner.id) {
                SignInOffer(identifier: "gear.signin", width: 230) {
                    Task { await account.signIn(owner) }
                }
            }
            if account.isSignedIn || model.people.owner != nil {
                SettingsGroup {
                    if account.isSignedIn {
                        SettingsRow(
                            .symbol("rectangle.portrait.and.arrow.right"), color: Palette.sky,
                            title: Text("Sign out", comment: "Settings: sign out of the account"),
                            end: .action
                        ) {
                            Task { await account.signOut() }
                        }
                        .accessibilityIdentifier("gear.signout")
                    }
                    SettingsRow(
                        .art(ArtName.iconDelete), color: Palette.refuse,
                        title: account.isSignedIn
                            ? Text("Delete account", comment: "Settings: delete the signed-in account (asks first)")
                            : Text("Delete my data", comment: "Settings: delete a player who isn't signed in (asks first)"),
                        end: .action, destructive: true
                    ) {
                        confirmingDelete = true
                    }
                    .accessibilityIdentifier("gear.delete")
                }
                .disabled(account.busy)
            }
        }
        .groupOpacity(account.busy ? 0.6 : 1)
    }

    /// The linked providers, each with a check, and a button for any not linked yet.
    private func providers(_ account: AccountModel) -> some View {
        HStack(spacing: 10) {
            ForEach(account.record.providers, id: \.self) { ProviderIcon(provider: $0) }
            if account.offersSignIn {
                ForEach(account.linkableProviders, id: \.self) { provider in
                    AppleSignInButton(identifier: "gear.link.\(provider)", style: .white, cornerRadius: 22) {
                        Task { await account.link(provider) }
                    }
                    .frame(width: 180, height: 44)
                }
            }
        }
    }

    private var dial: CGFloat { sizeClass == .regular ? 150 : 120 }

    /// Two dials side by side, or one over the other when they don't fit (the largest text sizes).
    private func dials(@ViewBuilder _ content: () -> some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) { content() }
            VStack(spacing: 22) { content() }
        }
        .frame(maxWidth: .infinity)
    }

    private func quietHours(_ s: NotifySettings) -> some View {
        VStack(spacing: 22) {
            WordLabel(title: "No alerts between these times.", alignment: .center, speaks: true)
            dials {
                ClockDial(icon: ArtName.Habit.iconMoon, time: s.quietStart, color: Palette.violet, side: dial,
                          label: "Quiet hours start", caption: "Starts", id: "notify.quietStart") {
                    model.setNotify(NotifyKey.quietStart, $0.json)
                }
                ClockDial(icon: ArtName.Habit.iconSun, time: s.quietEnd, color: Palette.orange, side: dial,
                          label: "Quiet hours end", caption: "Ends", id: "notify.quietEnd") {
                    model.setNotify(NotifyKey.quietEnd, $0.json)
                }
            }
        }
        .padding(.top, 8)
    }

    private func reminderTimes(_ s: NotifySettings) -> some View {
        VStack(spacing: 22) {
            WordLabel(title: "When the daily reminder comes.", alignment: .center, speaks: true)
            dials {
                ClockDial(icon: ArtName.Habit.iconWeekday, time: s.clamped(s.weekday), color: Palette.magenta,
                          side: dial, label: "Weekday reminder", caption: "Weekdays", clamp: s.clamped,
                          id: "notify.weekday") {
                    model.setNotify(NotifyKey.weekday, $0.json)
                }
                ClockDial(icon: ArtName.Habit.iconWeekend, time: s.clamped(s.weekend), color: Palette.teal,
                          side: dial, label: "Weekend reminder", caption: "Weekends", clamp: s.clamped,
                          id: "notify.weekend") {
                    model.setNotify(NotifyKey.weekend, $0.json)
                }
            }
            .groupOpacity(s.reminders ? 1 : 0.55)
        }
        .padding(.top, 8)
    }
}
