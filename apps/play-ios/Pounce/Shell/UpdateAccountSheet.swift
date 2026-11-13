import PounceKit
import SwiftUI

/// The account, reached from "Update Pounce to keep playing" (app updates design §4.3): a version
/// the server no longer supports can't get to the gear, and deleting your account has to stay
/// possible for as long as the app runs (App Store guideline 5.1.1(v)). The same card, the same
/// question and the same calls as the gear's: sign out and the trash can for someone signed in,
/// "Delete my data" for a player who isn't. The server lets exactly those two calls through.
struct UpdateAccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Spacer()
                        SheetCloseButton() {
                            dismiss()
                        }
                        .accessibilityIdentifier("update.account.close")
                    }
                    if model.account.isSignedIn {
                        AccountCard { confirmingDelete = true }
                    } else if model.people.owner != nil {
                        // Deleting isn't only for accounts: a guest's or a kitten's player too.
                        GuestDeleteRow { confirmingDelete = true }
                            .disabled(model.account.busy)
                    }
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
                            // Signed in: the account. Otherwise the player on this phone.
                            await model.account.deleteAccount(personId: signedIn ? nil : model.people.owner?.id)
                            confirmingDelete = false
                        }
                    })
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25).paced, value: confirmingDelete)
        .accountOverlays()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-update-account")
    }
}

/// The quiet way from the update screen to the account: small words under the button, never
/// competing with it. Only for someone with something to sign out of or delete.
struct UpdateAccountLink: View {
    @Environment(AppModel.self) private var model
    @State private var shown = false

    private var title: String {
        model.account.isSignedIn
            ? String(localized: "Account", comment: "Under the full-screen update notice: opens sign out and delete account")
            : String(localized: "Your data", comment: "Under the full-screen update notice, not signed in: opens delete my data")
    }

    var body: some View {
        if model.people.owner != nil {
            Button {
                Haptics.shared.tick()
                shown = true
            } label: {
                Text(verbatim: title)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .underline()
                    .foregroundStyle(.white.opacity(0.8))
                    .shadow(color: Palette.ink.opacity(0.6), radius: 0, x: 0, y: 1.5)
                    // A finger-sized target around small words.
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Sign out or delete")
            .accessibilityIdentifier("update.required.account")
            .sheet(isPresented: $shown) {
                UpdateAccountSheet()
                    .environment(model)
                    .environment(model.settings)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Palette.night)
            }
            #if DEBUG
            // `-show-update-account`: the sheet at launch (screenshots).
            .task {
                guard CommandLine.arguments.contains("-show-update-account") else { return }
                try? await Task.sleep(for: .milliseconds(700))
                shown = true
            }
            #endif
        }
    }
}
