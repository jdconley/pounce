import PounceKit
import SwiftUI

/// People on this phone ("who's playing?"): the owner and the others who share the phone for
/// pass-and-play. Tap a cat to edit it, the dashed plus to add someone. A new name reaches every
/// table they sit at (each one as it next opens; the table menu's Names renames mid-game); a
/// new cat applies to tables joined afterwards.
struct PeopleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Editing: Equatable {
        case owner
        case person(String)
        /// Adding someone: first how old they are (spec §14.1), then their name and cat.
        case age
        case new(AgeBand)
        /// Holding a household cat: that person signs in on their own (spec §10.5).
        case signIn(String)
        /// Someone added before ages were asked: their band first, then the editor.
        case ageFor(String)
        /// Holding a signed-in household cat: their account, with the trash can.
        case account(String)
    }

    @State private var editing: Editing?

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            if let editing {
                editor(editing)
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
            } else {
                list
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3).paced, value: editing)
        .accountOverlays()
        #if DEBUG
        .task {
            // `-show-household-age`: open on the age pictures for a new person (screenshots).
            if CommandLine.arguments.contains("-show-household-age") { editing = .age }
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-people")
    }

    private var account: AccountModel { model.account }

    // MARK: list

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .small, accessibilityLabel: "Close") {
                    dismiss()
                }
                .accessibilityIdentifier("people.close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 22
                ) {
                    if let owner = model.people.owner {
                        PersonTile(
                            person: owner, ringIndex: 0, isOwner: true, signedIn: account.isSignedIn(owner.id)
                        ) { editing = .owner }
                            .accessibilityIdentifier("people.owner")
                    }
                    ForEach(Array(model.people.others.enumerated()), id: \.element.id) { i, person in
                        PersonTile(
                            person: person, ringIndex: i + 1, isOwner: false,
                            signedIn: account.isSignedIn(person.id), imported: account.isImported(person.id),
                            onHold: hold(person.id)
                        ) {
                            // People from the account's other devices are edited there.
                            guard !account.isImported(person.id) else { return }
                            editing = account.band(of: person.id) == nil ? .ageFor(person.id) : .person(person.id)
                        }
                        .accessibilityIdentifier("people.person.\(person.id)")
                    }
                    // On a kitten's device everyone added is a kitten: no age pictures (§14.1).
                    AddTile { editing = model.ageBand == .kitten ? .new(.kitten) : .age }
                        .accessibilityIdentifier("people.add")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)

                if let owner = model.people.owner, !account.isSignedIn, account.canSignIn(owner.id) {
                    SignInOffer(identifier: "people.signin") {
                        Task { await account.signIn(owner) }
                    }
                    .padding(.bottom, 24)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.3).paced, value: account.isSignedIn)
        }
    }

    // MARK: editor

    @ViewBuilder private func editor(_ editing: Editing) -> some View {
        switch editing {
        case .owner:
            if let owner = model.people.owner {
                CatEditorView(
                    initialName: owner.name, initialCat: owner.cat, typedNames: model.limits.typedNames,
                    onCancel: { self.editing = nil }
                ) { name, cat in
                    model.updateOwner(name: name, cat: cat)
                    self.editing = nil
                }
            }
        case .person(let id):
            if let person = model.people.others.first(where: { $0.id == id }) {
                CatEditorView(
                    initialName: person.name, initialCat: person.cat,
                    typedNames: account.typesName(id), onCancel: { self.editing = nil },
                    onDelete: {
                        model.removePerson(id: id)
                        self.editing = nil
                    }
                ) { name, cat in
                    model.updatePerson(Person(id: id, name: name, cat: cat))
                    self.editing = nil
                }
            }
        case .age:
            AgeBandPicker(cat: nextFreshCat(), onBack: { self.editing = nil }) { band in
                self.editing = .new(band)
            }
        case .new(let band):
            CatEditorView(
                initialName: "", initialCat: nextFreshCat(), typedNames: band != .kitten,
                onCancel: { self.editing = nil }
            ) { name, cat in
                model.addPerson(name: name, cat: cat, band: band)
                self.editing = nil
            }
            // Why a kid's name comes from the dice (spec §14.1; launch review).
            .safeAreaInset(edge: .top, spacing: 0) {
                if band == .kitten {
                    WordLine(
                        String(localized: "Kids under 13 get a made-up name, for privacy.",
                               comment: "People sheet: adding a kid, why the name is generated"),
                        size: 16)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .accessibilityIdentifier("people.kittenNameHint")
                }
            }
        case .ageFor(let id):
            if let person = model.people.others.first(where: { $0.id == id }) {
                AgeBandPicker(cat: person.cat, onBack: { self.editing = nil }) { band in
                    account.setBand(id, band)
                    self.editing = .person(id)
                }
            }
        case .account(let id):
            if let person = model.people.others.first(where: { $0.id == id }) {
                HouseholdAccount(person: person, onBack: { self.editing = nil })
            }
        case .signIn(let id):
            if let person = model.people.others.first(where: { $0.id == id }) {
                HouseholdSignIn(person: person, onBack: { self.editing = nil }) {
                    Task {
                        let outcome = await account.signIn(person)
                        if outcome != .cancelled { self.editing = nil }
                    }
                }
            }
        }
    }

    /// What holding a household cat does: their own account if signed in, else sign-in when allowed.
    private func hold(_ id: String) -> (() -> Void)? {
        if account.isSignedIn(id), !account.isImported(id) { return { editing = .account(id) } }
        return account.canSignIn(id) ? { editing = .signIn(id) } : nil
    }

    /// A cat nobody on this phone uses yet, so a new person starts out different from the others.
    private func nextFreshCat() -> Int {
        let used = Set(([model.people.owner].compactMap { $0 } + model.people.others).map(\.cat))
        return (0..<ArtName.catCount).first { !used.contains($0) } ?? 0
    }
}

/// A big round cat with a seat-colored ring and its name under it.
struct PersonTile: View {
    let person: Person
    let ringIndex: Int
    let isOwner: Bool
    /// Has a sign-in of their own: a lime check.
    var signedIn = false
    /// Listed by the account's other device: a little cloud.
    var imported = false
    /// Holding the cat (signing that person in), when allowed.
    var onHold: (() -> Void)?
    let action: () -> Void

    @State private var nope = 0

    var body: some View {
        tile
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.shared.tick()
                Sound.shared.play(ArtName.Sound.sfxPop)
                action()
            }
            .onLongPressGesture(minimumDuration: 0.6) {
                guard let onHold else {
                    nope += 1
                    Haptics.shared.thump()
                    return
                }
                Haptics.shared.tick()
                Sound.shared.play(ArtName.Sound.sfxPop)
                onHold()
            }
            .wiggle(trigger: nope)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(verbatim: person.name))
            .accessibilityValue(signedIn ? "signed in" : "")
            .accessibilityActions {
                if let onHold {
                    Button { onHold() } label: { Text("Sign in", comment: "VoiceOver: sign this person in on their own") }
                }
            }
    }

    private var tile: some View {
        Group {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Palette.sky.mix(with: .white, by: 0.2), Palette.teal.mix(with: Palette.violet, by: 0.3)],
                                startPoint: .top, endPoint: .bottom)
                        )
                        .overlay(
                            Circle().strokeBorder(
                                Palette.playerRings[ringIndex % Palette.playerRings.count], lineWidth: 6)
                        )
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3).padding(-3))
                        .overlay {
                            Image(ArtName.cat(person.cat, .idle))
                                .resizable().scaledToFit()
                                .padding(10)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5)
                    if isOwner {
                        Image(ArtName.badgePhone)
                            .resizable().scaledToFit()
                            .frame(width: 30, height: 30)
                            .offset(x: 2, y: 2)
                    }
                    if signedIn {
                        CheckBadge(side: 30)
                            .offset(x: 2, y: isOwner ? -30 : 2)
                    }
                    if imported {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(.white, Palette.sky)
                            .shadow(color: Palette.ink, radius: 0, x: 0, y: 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                OutlinedText(person.name, size: 18, width: 2.5)
            }
        }
    }
}

/// A signed-in household person's own account: their cat with a check, and the trash can to
/// delete it (App Review 5.1.1(v), spec §14), with the same confirm and Settings picture.
struct HouseholdAccount: View {
    @Environment(AppModel.self) private var model
    let person: Person
    let onBack: () -> Void
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            CatDisc(cat: person.cat, side: 190, color: Palette.teal, check: true)
            OutlinedText(person.name, size: 30, width: 3)
            HStack(spacing: 22) {
                PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .medium, accessibilityLabel: "Back") {
                    onBack()
                }
                .accessibilityIdentifier("people.account.back")
                DeleteButton { confirming = true }
                    .accessibilityLabel("Delete account")
                    .accessibilityIdentifier("people.account.delete")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .overlay {
            if confirming {
                DeleteConfirmView(cat: person.cat, name: person.name, onBack: { confirming = false }) {
                    Task {
                        if await model.account.deleteAccount(personId: person.id) { onBack() }
                        confirming = false
                    }
                }
            }
        }
    }
}

/// Holding a household cat: that person, and the sign-in button just for them.
struct HouseholdSignIn: View {
    @Environment(AppModel.self) private var model
    let person: Person
    let onBack: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            CatDisc(cat: person.cat, side: 190, color: Palette.teal)
            OutlinedText(person.name, size: 30, width: 3)
            AppleSignInButton(identifier: "people.signin.person", action: onSignIn)
                .frame(width: 260, height: 56)
                .opacity(model.account.busy ? 0.5 : 1)
                .overlay { if model.account.busy { YarnIndicator() } }
            PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .medium, accessibilityLabel: "Back") {
                onBack()
            }
            .accessibilityIdentifier("people.signin.back")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// The dashed "+" slot that adds a person.
struct AddTile: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tick()
            action()
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .strokeBorder(
                        Palette.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [2, 12]))
                    .overlay {
                        Image(ArtName.iconPlus)
                            .resizable().scaledToFit()
                            .padding(26)
                    }
                    .aspectRatio(1, contentMode: .fit)
                // Keeps the row height level with the named tiles.
                Color.clear.frame(height: 28)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a person")
    }
}
