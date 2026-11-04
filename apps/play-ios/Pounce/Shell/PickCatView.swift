import PounceKit
import SwiftUI

/// First launch: pick a cat and type your name. A hero cat over "What's your name?", the name
/// field (focused, empty, a random name as its placeholder; the dice fills one in), the 4x2 cat
/// grid and one big check. Everyone at the table sees this name.
struct PickCatView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        CatEditorView(
            initialName: "", initialCat: 0, asksName: true
        ) { name, cat in
            model.finishPickCat(name: name, cat: cat)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-pickCat")
    }
}

/// VoiceOver names for the eight roster cats (spoken only).
enum CatNames {
    static func label(_ cat: Int) -> LocalizedStringKey {
        switch cat {
        case 0: "Orange tabby cat"
        case 1: "Tuxedo cat"
        case 2: "Calico cat"
        case 3: "Gray cat"
        case 4: "Black cat"
        case 5: "White fluffy cat"
        case 6: "Siamese cat"
        case 7: "Tortie cat"
        default: "Cat"
        }
    }
}

/// Hero cat + name field + dice + cat grid + check. Used for the first launch and for editing a
/// person in the People sheet. A new person starts with an empty name: a random one shows as
/// the placeholder, never taken unless the dice puts it in the field, and the check sends you
/// back to the field until it holds a name.
struct CatEditorView: View {
    let initialName: String
    let initialCat: Int
    /// Ask for the name out loud ("What's your name?") and focus the field at once.
    let asksName: Bool
    /// Show the extra delete button (people other than the owner).
    var onDelete: (() -> Void)?
    var onCancel: (() -> Void)?
    let onConfirm: (String, Int) -> Void

    @State private var name: String
    @State private var cat: Int
    @State private var blink = false
    @State private var diceSpin = 0
    @State private var nameNope = 0
    /// The placeholder: a name to type over (or roll with the dice).
    @State private var suggestion = CatEditorView.randomName()
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        initialName: String, initialCat: Int, asksName: Bool = false, onCancel: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil, onConfirm: @escaping (String, Int) -> Void
    ) {
        self.initialName = initialName
        self.initialCat = initialCat
        self.asksName = asksName
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onConfirm = onConfirm
        _name = State(initialValue: initialName)
        _cat = State(initialValue: initialCat)
    }

    static func randomName() -> String {
        var rng = SystemRandomNumberGenerator()
        return NameGenerator.random(using: &rng)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canConfirm: Bool { !trimmed.isEmpty }

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    if asksName {
                        OutlinedText(
                            String(localized: "What's your name?", comment: "First launch: the prompt over the name field"),
                            size: 30, fill: .white, width: 4)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("pickcat.prompt")
                    }
                    nameRow
                    catGrid
                    confirmRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .task { await blinkLoop() }
        .task {
            // A new name is the first thing to fill in: the keyboard comes up with the screen.
            guard asksName || initialName.isEmpty else { return }
            try? await Task.sleep(for: Pace.duration(.milliseconds(350)))
            // Not if a name went in meanwhile (the dice), which would only cover the check.
            guard trimmed.isEmpty else { return }
            nameFocused = true
        }
    }

    // MARK: pieces

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.violet, Palette.night], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Palette.magenta.opacity(0.55), .clear], center: .init(x: 0.5, y: 0.2),
                startRadius: 10, endRadius: 320)
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.sky, Palette.teal.mix(with: Palette.violet, by: 0.35)],
                        center: .center, startRadius: 4, endRadius: 130)
                )
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 6))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 8)
                .frame(width: 230, height: 230)
            Image(ArtName.cat(cat, blink ? .awake : .idle))
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 190)
                .shadow(color: Palette.ink.opacity(0.4), radius: 0, x: 0, y: 6)
                .id(cat)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel(CatNames.label(cat))
        }
        // Smaller while typing, so the prompt, the field and the check stay above the keyboard.
        .scaleEffect(nameFocused ? Self.typingScale : 1, anchor: .bottom)
        .frame(height: 246 * (nameFocused ? Self.typingScale : 1))
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.4).paced, value: cat)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2).paced, value: nameFocused)
    }

    private static let typingScale: CGFloat = 0.5

    private var nameRow: some View {
        HStack(spacing: 12) {
            TextField(
                "", text: $name,
                prompt: Text(verbatim: suggestion).foregroundStyle(Palette.ink.opacity(0.4))
            )
                .focused($nameFocused)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
                .onChange(of: name) { _, new in
                    var clipped = new
                    while clipped.utf16.count > PeopleStore.maxNameLength { clipped.removeLast() }
                    if clipped != new { name = clipped }
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5)
                .wiggle(trigger: nameNope)
                .accessibilityLabel(Text("Your name"))
                .accessibilityIdentifier("pickcat.name")

            PillButton(icon: ArtName.iconDice, color: Palette.orange, size: .small, accessibilityLabel: "Pick a random name") {
                name = suggestion
                suggestion = Self.randomName()
                diceSpin += 1
                nameFocused = false
            }
            .wiggle(trigger: diceSpin)
            .accessibilityIdentifier("pickcat.dice")
        }
        .padding(.bottom, 6)
    }

    private var catGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
            ForEach(0..<ArtName.catCount, id: \.self) { i in
                CatTile(cat: i, selected: i == cat) {
                    cat = i
                    nameFocused = false
                    Haptics.shared.tick()
                    Sound.shared.play(ArtName.Sound.sfxPop)
                }
                .accessibilityIdentifier("pickcat.cat.\(i)")
            }
        }
    }

    private var confirmRow: some View {
        HStack(spacing: 16) {
            if let onCancel {
                PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .medium, accessibilityLabel: "Back") {
                    onCancel()
                }
                .accessibilityIdentifier("pickcat.cancel")
            }
            PillButton(
                icon: ArtName.iconCheck, color: Palette.lime, size: .large,
                width: onCancel == nil ? 260 : 190, accessibilityLabel: "Done"
            ) {
                guard canConfirm else {
                    // No name yet: back to the field, which wiggles.
                    nameNope += 1
                    nameFocused = true
                    Haptics.shared.thump()
                    return
                }
                onConfirm(trimmed, cat)
            }
            .saturation(canConfirm ? 1 : 0)
            .opacity(canConfirm ? 1 : 0.55)
            .accessibilityHint(canConfirm ? Text("") : Text("Type your name first"))
            .accessibilityIdentifier("pickcat.confirm")
            if let onDelete {
                DeleteButton(action: onDelete)
                    .accessibilityIdentifier("pickcat.delete")
            }
        }
        .padding(.top, 6)
    }

    // MARK: blink

    /// Idle cat blinks by swapping to the awake pose for a moment, every few seconds.
    private func blinkLoop() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.2...4.2)))
            if Task.isCancelled { return }
            blink = true
            try? await Task.sleep(for: .milliseconds(140))
            blink = false
        }
    }
}

/// One cat in the grid: a chunky rounded square with a thick outline; the chosen one glows orange.
struct CatTile: View {
    let cat: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: selected
                            ? [Palette.orange.mix(with: .white, by: 0.3), Palette.orange]
                            : [Palette.violet.mix(with: .white, by: 0.2), Palette.violet.mix(with: Palette.ink, by: 0.25)],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay {
                    Image(ArtName.cat(cat, .idle))
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Palette.ink, lineWidth: 4)
                )
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white, lineWidth: 2)
                            .padding(5)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: selected ? Palette.orange.opacity(0.9) : Palette.ink.opacity(0.5),
                        radius: selected ? 10 : 0, x: 0, y: selected ? 0 : 4)
                .scaleEffect(selected ? 1.08 : 1)
                .animation(.spring(duration: 0.3, bounce: 0.5).paced, value: selected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CatNames.label(cat))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Round magenta remove button, drawn like the pills, with the manifest's delete icon.
struct DeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tick()
            action()
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Palette.magenta.mix(with: .white, by: 0.3), Palette.magenta],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                .overlay {
                    Image(ArtName.iconDelete)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 2)
                }
                .frame(width: 58, height: 58)
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }
}
