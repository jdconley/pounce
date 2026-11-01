import PounceKit
import SwiftUI

/// People on this phone ("who's playing?"): the owner and the others who share the phone for
/// pass-and-play. Tap a cat to edit it, the dashed plus to add someone. Edits apply to tables
/// joined afterwards.
struct PeopleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Editing: Equatable {
        case owner
        case person(String)
        case new
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
        .animation(.spring(duration: 0.4, bounce: 0.3), value: editing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-people")
    }

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
                        PersonTile(person: owner, ringIndex: 0, isOwner: true) { editing = .owner }
                            .accessibilityIdentifier("people.owner")
                    }
                    ForEach(Array(model.people.others.enumerated()), id: \.element.id) { i, person in
                        PersonTile(person: person, ringIndex: i + 1, isOwner: false) {
                            editing = .person(person.id)
                        }
                        .accessibilityIdentifier("people.person.\(person.id)")
                    }
                    AddTile { editing = .new }
                        .accessibilityIdentifier("people.add")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
        }
    }

    // MARK: editor

    @ViewBuilder private func editor(_ editing: Editing) -> some View {
        switch editing {
        case .owner:
            if let owner = model.people.owner {
                CatEditorView(
                    initialName: owner.name, initialCat: owner.cat, onCancel: { self.editing = nil }
                ) { name, cat in
                    model.updateOwner(name: name, cat: cat)
                    self.editing = nil
                }
            }
        case .person(let id):
            if let person = model.people.others.first(where: { $0.id == id }) {
                CatEditorView(
                    initialName: person.name, initialCat: person.cat, onCancel: { self.editing = nil },
                    onDelete: {
                        model.removePerson(id: id)
                        self.editing = nil
                    }
                ) { name, cat in
                    model.updatePerson(Person(id: id, name: name, cat: cat))
                    self.editing = nil
                }
            }
        case .new:
            CatEditorView(
                initialName: CatEditorView.randomName(), initialCat: nextFreshCat(),
                onCancel: { self.editing = nil }
            ) { name, cat in
                model.addPerson(name: name, cat: cat)
                self.editing = nil
            }
        }
    }

    /// A cat nobody on this phone uses yet, so a new person starts out different from the others.
    private func nextFreshCat() -> Int {
        let used = Set(([model.people.owner].compactMap { $0 } + model.people.others).map(\.cat))
        return (0..<ArtName.catCount).first { !used.contains($0) } ?? 0
    }
}

/// A big round cat with a seat-colored ring and its name under it.
private struct PersonTile: View {
    let person: Person
    let ringIndex: Int
    let isOwner: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            action()
        } label: {
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
                }
                OutlinedText(person.name, size: 18, width: 2.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: person.name))
    }
}

/// The dashed "+" slot that adds a person.
private struct AddTile: View {
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
