import PounceKit
import SwiftUI

/// First launch: pick a cat and type your name. A hero cat over "What's your name?", the name
/// field (focused, empty, a random name as its placeholder; the dice fills one in), the 4x2 cat
/// grid and one big check. Everyone at the table sees this name.
struct PickCatView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        CatEditorView(
            initialName: "", initialCat: 0, asksName: true, typedNames: model.limits.typedNames
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
    /// Names are typed. Off (a kitten, spec §14.1): only the generated names, by the dice.
    let typedNames: Bool
    /// Show the extra delete button (people other than the owner).
    var onDelete: (() -> Void)?
    var onCancel: (() -> Void)?
    let onConfirm: (String, Int) -> Void

    @State private var name: String
    @State private var cat: Int
    @State private var blink = false
    @State private var diceSpin = 0
    @State private var nameNope = 0
    /// Why the server's name filter refused the typed name; nil while it hasn't.
    @State private var refusal: String?
    @State private var checking = false
    @Environment(AppModel.self) private var model
    /// The placeholder: a name to type over (or roll with the dice).
    @State private var suggestion = CatEditorView.randomName()
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        initialName: String, initialCat: Int, asksName: Bool = false, typedNames: Bool = true,
        onCancel: (() -> Void)? = nil, onDelete: (() -> Void)? = nil, onConfirm: @escaping (String, Int) -> Void
    ) {
        let start = typedNames || !AgeLimits.needsGeneratedName(initialName) ? initialName : Self.randomName()
        self.initialName = start
        self.initialCat = initialCat
        self.asksName = asksName
        self.typedNames = typedNames
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onConfirm = onConfirm
        _name = State(initialValue: start)
        _cat = State(initialValue: initialCat)
    }

    static func randomName() -> String {
        var rng = SystemRandomNumberGenerator()
        return NameGenerator.random(using: &rng)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canConfirm: Bool { !trimmed.isEmpty }

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            background
            if sizeClass == .regular {
                roomy
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        prompt
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
        }
        .task { await blinkLoop() }
        .task {
            // A new name is the first thing to fill in: the keyboard comes up with the screen.
            guard typedNames, asksName || initialName.isEmpty else { return }
            try? await Task.sleep(for: Pace.duration(.milliseconds(350)))
            // Not if a name went in meanwhile (the dice), which would only cover the check.
            guard trimmed.isEmpty else { return }
            nameFocused = true
        }
    }

    // MARK: roomy (iPad)

    /// A regular-width window. Wide: you (the big cat, the prompt and your name) on the left,
    /// the cats to choose from and the check on the right. Tall: one centered column with a
    /// bigger cat and grid. Both scroll when the keyboard leaves too little room.
    private var roomy: some View {
        GeometryReader { geo in
            ScrollView {
                Group {
                    if Roomy.sideBySide(geo.size, minWidth: 820) {
                        // With the keyboard up a landscape window is short: the name comes
                        // first and the big cat steps aside (the grid still shows the pick).
                        let short = geo.size.height < 460
                        HStack(alignment: short ? .top : .center, spacing: 48) {
                            VStack(spacing: 20) {
                                if !short { hero }
                                prompt
                                nameRow
                            }
                            .frame(width: min(geo.size.width * 0.4, 460))
                            VStack(spacing: 26) {
                                catGrid
                                confirmRow
                            }
                            .frame(width: min(geo.size.width * 0.42, 520))
                        }
                    } else {
                        VStack(spacing: 22) {
                            hero
                            prompt
                            nameRow
                            catGrid
                            confirmRow
                        }
                        .frame(maxWidth: 600)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: pieces

    @ViewBuilder private var prompt: some View {
        if asksName && typedNames {
            OutlinedText(
                String(localized: "What's your name?", comment: "First launch: the prompt over the name field"),
                size: sizeClass == .regular ? 38 : 30, fill: .white, width: 4)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("pickcat.prompt")
        }
    }

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
                .frame(width: 230 * heroScale, height: 230 * heroScale)
            Image(ArtName.cat(cat, blink ? .awake : .idle))
                .resizable()
                .scaledToFit()
                .frame(width: 190 * heroScale, height: 190 * heroScale)
                .shadow(color: Palette.ink.opacity(0.4), radius: 0, x: 0, y: 6)
                .id(cat)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel(CatNames.label(cat))
        }
        // Smaller while typing, so the prompt, the field and the check stay above the keyboard.
        .scaleEffect(nameFocused ? Self.typingScale : 1, anchor: .bottom)
        .frame(height: 246 * heroScale * (nameFocused ? Self.typingScale : 1))
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.4).paced, value: cat)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2).paced, value: nameFocused)
    }

    private static let typingScale: CGFloat = 0.5
    /// The hero cat is bigger on a roomy screen.
    private var heroScale: CGFloat { sizeClass == .regular ? 1.3 : 1 }

    private var nameRow: some View {
        HStack(spacing: 12) {
            if typedNames { nameField } else { generatedName }
            PillButton(icon: ArtName.iconDice, color: Palette.orange, size: .small, accessibilityLabel: "Pick a random name") {
                if typedNames {
                    name = suggestion
                    suggestion = Self.randomName()
                } else {
                    var next = Self.randomName()
                    while next == name { next = Self.randomName() }
                    name = next
                }
                diceSpin += 1
                nameFocused = false
            }
            .wiggle(trigger: diceSpin)
            .accessibilityIdentifier("pickcat.dice")
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            // Hangs just under the field, over the gap above the cats, so nothing jumps.
            if let refusal {
                NameRefusal(text: refusal, size: 14)
                    .alignmentGuide(.bottom) { $0[.top] }
                    .offset(y: -4)
                    .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.3).paced, value: refusal)
        .zIndex(1)
    }

    /// A kitten's name: one of the generated names, shown, not typed (spec §14.1).
    private var generatedName: some View {
        OutlinedText(name, size: 28, fill: .white, width: 3)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Capsule().fill(Palette.teal.mix(with: Palette.violet, by: 0.35)))
            .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4))
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5)
            .pop(trigger: name)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityIdentifier("pickcat.generatedName")
    }

    private var nameField: some View {
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
                    refusal = nil
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
                // The drop shadow on the pill alone: on the field it would sit under the faint
                // placeholder letters and show through them.
                .background(Capsule().fill(.white).shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5))
                .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4))
                .wiggle(trigger: nameNope)
                .accessibilityLabel(Text("Your name"))
                .accessibilityIdentifier("pickcat.name")
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
                confirm()
            }
            .disabled(checking)
            .saturation(canConfirm ? 1 : 0)
            .groupOpacity(canConfirm ? 1 : 0.55)
            .accessibilityHint(canConfirm ? Text("") : Text("Type your name first"))
            .accessibilityIdentifier("pickcat.confirm")
            if let onDelete {
                DeleteButton(action: onDelete)
                    .accessibilityIdentifier("pickcat.delete")
            }
        }
        .padding(.top, 6)
    }

    /// A typed name is put to the server's name filter first; a generated one needs no asking.
    private func confirm() {
        let name = trimmed, cat = cat
        guard typedNames, AgeLimits.needsGeneratedName(name) else { return onConfirm(name, cat) }
        guard !checking else { return }
        checking = true
        Task {
            let verdict = await NameGate.verdict(model.api, name, kind: .person)
            checking = false
            if let words = NameGate.words(verdict) {
                refusal = words
                nameNope += 1
                Haptics.shared.thump()
                UIAccessibility.post(notification: .announcement, argument: words)
            } else {
                onConfirm(name, cat)
            }
        }
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
