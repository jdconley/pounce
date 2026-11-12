import PounceKit
import SwiftUI

/// Home's sign-in card (launch review, `SignInPrompt`; the streak's Save, §10.5): your streaks,
/// kept on a new phone, with Sign in with Apple and "Not now". `onDone` closes it, after a
/// sign-in or a "Not now".
struct SignInPromptCard: View {
    @Environment(AppModel.self) private var model
    var identifier = "home.signinPrompt"
    var appleIdentifier = "home.signinPrompt.apple"
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Palette.night.opacity(0.85).ignoresSafeArea().onTapGesture(perform: notNow)
            VStack(spacing: 16) {
                if let owner = model.people.owner {
                    Image(ArtName.cat(owner.cat, .awake)).resizable().scaledToFit().frame(height: 110)
                        .accessibilityHidden(true)
                }
                OutlinedText(
                    String(localized: "Save your streaks", comment: "Home's sign-in card: the headline"),
                    size: 28, lines: 2)
                    .accessibilityAddTraits(.isHeader)
                WordLine(
                    String(localized: "Keep them on a new phone.", comment: "Home's sign-in card: what signing in does"),
                    size: 17)
                if let owner = model.people.owner {
                    AppleSignInButton(identifier: appleIdentifier) {
                        Task {
                            await model.account.signIn(owner)
                            if model.account.isSignedIn { onDone() }
                        }
                    }
                    .frame(width: 260, height: 54)
                    .opacity(model.account.busy ? 0.5 : 1)
                    .disabled(model.account.busy)
                    .overlay { if model.account.busy { YarnIndicator() } }
                }
                PillButton(
                    icon: nil, color: Palette.sky, size: .small, width: 160,
                    title: String(localized: "Not now", comment: "Home's sign-in card: dismiss it"),
                    accessibilityLabel: "Not now", action: notNow)
                .accessibilityIdentifier("home.signinPrompt.notNow")
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Palette.violet)
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5)))
            .padding(16)
        }
        // The card and its backdrop fade in and out as one.
        .compositingGroup()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func notNow() {
        onDone()
    }
}

/// In the lobby (launch review, `KittenTablePrompt`): a kitten's own device without consent is
/// told to show a grown-up here its code; a signed-in parent with a linked kitten at the table is
/// asked to finish that kitten's turn alerts. Closed with the x for this visit to the table.
struct KittenTablePromptView: View {
    @Environment(AppModel.self) private var model
    let session: RoomSession

    @State private var closed = false
    @State private var showCode = false
    @State private var finishing: KittensPanelRequest?

    private var ask: KittenTablePrompt.Ask? {
        if let own = KittenTablePrompt.forKitten(
            isKitten: model.ageBand == .kitten, consented: model.kittenConsented, held: model.kittenPushHeld) {
            return own
        }
        let others = (session.model.map { table in
            table.room.seats.indices.filter { !table.mySeats.contains($0) }.compactMap { table.room.seats[$0].person }
        }) ?? []
        return KittenTablePrompt.forParent(isParent: model.isParent, kittens: model.kittens.kittens, others: others)
    }

    var body: some View {
        Group {
            if !closed, let ask {
                card(ask)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.3).paced, value: closed)
        .task {
            if model.isParent { await model.kittens.refreshKittens() }
        }
        .sheet(isPresented: $showCode) {
            KittenCodeSheet()
                .environment(model)
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.night)
        }
        .sheet(item: $finishing) { request in
            KittensSheet(focus: request.focus)
                .environment(model)
                .presentationBackground(Palette.night)
        }
    }

    private func card(_ ask: KittenTablePrompt.Ask) -> some View {
        HStack(spacing: 12) {
            Image(ArtName.Habit.kittenBellLocked).resizable().scaledToFit().frame(width: 46)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: line(ask))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("table.kittenPrompt.text")
                PillButton(
                    icon: nil, color: Palette.lime, size: .small, width: 170,
                    title: button(ask), accessibilityLabel: LocalizedStringKey(button(ask))
                ) {
                    switch ask {
                    case .showCode: showCode = true
                    case .finish(let kitten, _): finishing = KittensPanelRequest(focus: kitten)
                    }
                }
                .accessibilityIdentifier("table.kittenPrompt.go")
            }
            Spacer(minLength: 0)
            Button {
                Haptics.shared.tick()
                closed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Palette.ink.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close", comment: "VoiceOver: close the turn-alerts card at the table"))
            .accessibilityIdentifier("table.kittenPrompt.close")
        }
        .padding(14)
        .frame(maxWidth: 460)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.violet)
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.ink, lineWidth: 4)))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.kittenPrompt")
    }

    private func line(_ ask: KittenTablePrompt.Ask) -> String {
        switch ask {
        case .showCode:
            String(localized: "Turn alerts need a grown-up's OK.",
                   comment: "Lobby card on a kitten's device without parent consent")
        case .finish(_, let name):
            String(localized: "\(name)'s turn alerts are off.",
                   comment: "Lobby card on a parent's device: a linked kid at this table has no consent yet")
        }
    }

    private func button(_ ask: KittenTablePrompt.Ask) -> String {
        switch ask {
        case .showCode: String(localized: "Show my code", comment: "Lobby card: open the kitten's code for a grown-up")
        case .finish: String(localized: "Set it up", comment: "Lobby card: open the parent's panel on that kid")
        }
    }
}

/// The kitten's bell and code, on its own (from the lobby card).
struct KittenCodeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .small, accessibilityLabel: "Close") { dismiss() }
                        .accessibilityIdentifier("kittenCode.close")
                }
                KittenBellView()
                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-kittenCode")
    }
}
