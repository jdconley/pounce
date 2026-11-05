import PounceKit
import SwiftUI

/// The table menu's Names page: each seat on this phone, its cat and its name in a field. A new
/// name goes to the server at once and every phone at the table shows it; for someone kept on
/// this phone (the owner, or a person from the People sheet) it sticks for later tables too.
struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    let session: RoomSession
    let onBack: () -> Void

    private var mine: [(seat: Seat, person: Person)] {
        guard let table = session.model else { return [] }
        return table.mySeats.compactMap { seat in table.room.seats[safe: seat]?.person.map { (seat, $0) } }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                CornerHomeButton(icon: ArtName.iconBack, label: "Back") { onBack() }
                    .accessibilityIdentifier("rename.back")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            OutlinedText(
                String(localized: "Names", comment: "Table menu: the page for renaming this phone's players"),
                size: 30, fill: .white, width: 4)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(mine, id: \.seat) { entry in
                        RenameRow(seat: entry.seat, person: entry.person, typed: typesName(entry.person)) { name in
                            model.renamePerson(seat: entry.seat, person: entry.person, to: name)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-rename")
    }

    /// A kitten's name comes from the dice, never the keyboard (spec §14.1).
    private func typesName(_ person: Person) -> Bool {
        guard model.limits.typedNames else { return false }
        return model.everyone.contains { $0.id == person.id } ? model.account.typesName(person.id) : true
    }
}

/// One seat: its cat in its ring, the name field and a check that lights up once the name
/// changed. Focusing the field selects the whole name, so typing replaces it. Return or the
/// check saves.
private struct RenameRow: View {
    let seat: Seat
    let person: Person
    /// Typed; otherwise a generated name, rolled with the dice.
    let typed: Bool
    let onSave: (String) -> Void

    @State private var name: String
    @State private var roll = 0
    @State private var selection: TextSelection?
    @State private var saved = 0
    @FocusState private var focused: Bool

    init(seat: Seat, person: Person, typed: Bool, onSave: @escaping (String) -> Void) {
        self.seat = seat
        self.person = person
        self.typed = typed
        self.onSave = onSave
        _name = State(initialValue: person.name)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { !trimmed.isEmpty && trimmed != person.name }

    var body: some View {
        HStack(spacing: 12) {
            Image(ArtName.cat(person.cat, .idle))
                .resizable()
                .scaledToFit()
                .padding(3)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Palette.night))
                .overlay(Circle().strokeBorder(SeatInfo.ringColor(seat), lineWidth: 5))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2).padding(-1))
                .accessibilityHidden(true)
            if typed { field } else { dice }
            PillButton(
                icon: ArtName.iconCheck, color: Palette.lime, size: .small, accessibilityLabel: "Save name"
            ) {
                save()
            }
            .saturation(changed ? 1 : 0)
            .opacity(changed ? 1 : 0.55)
            .wiggle(trigger: saved)
            .accessibilityIdentifier("rename.save.\(seat)")
        }
    }

    /// A kitten's row: the generated name, and the dice for another.
    private var dice: some View {
        HStack(spacing: 10) {
            OutlinedText(name, size: 24, fill: .white, width: 2.5)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(Palette.teal.mix(with: Palette.violet, by: 0.35)))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4))
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: name))
                .accessibilityIdentifier("rename.name.\(seat)")
            PillButton(icon: ArtName.iconDice, color: Palette.orange, size: .small, accessibilityLabel: "Pick a random name") {
                var next = CatEditorView.randomName()
                while next == name { next = CatEditorView.randomName() }
                name = next
                roll += 1
            }
            .wiggle(trigger: roll)
            .accessibilityIdentifier("rename.dice.\(seat)")
        }
    }

    private var field: some View {
            TextField("", text: $name, selection: $selection)
                .focused($focused)
                .onChange(of: focused) { _, on in
                    if on { selection = TextSelection(range: name.startIndex..<name.endIndex) }
                }
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
                .onChange(of: name) { _, new in
                    var clipped = new
                    while clipped.utf16.count > PeopleStore.maxNameLength { clipped.removeLast() }
                    if clipped != new { name = clipped }
                }
                .onChange(of: person.name) { _, new in
                    if !focused { name = new }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4))
                .accessibilityLabel(Text("Name"))
                .accessibilityIdentifier("rename.name.\(seat)")
    }

    private func save() {
        focused = false
        guard changed else { return }
        onSave(trimmed)
        saved += 1
        Haptics.shared.success()
        Sound.shared.play(ArtName.Sound.sfxPop)
    }
}
