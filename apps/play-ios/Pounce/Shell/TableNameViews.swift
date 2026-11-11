import PounceKit
import SwiftUI

/// The table's name in toy lettering, with a little pencil when this phone may rename it. Tapping
/// it (when editable) calls `onRename`. Used in the lobby's top bar and the table menu.
struct TableNameTitle: View {
    let name: String
    var size: CGFloat = 22
    let editable: Bool
    let onRename: () -> Void

    var body: some View {
        Button {
            guard editable else { return }
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            onRename()
        } label: {
            HStack(spacing: 8) {
                OutlinedText(name, size: size, fill: .white, width: 2.5)
                    .layoutPriority(1)
                if editable {
                    PencilMark()
                        .frame(width: size * 0.95, height: size * 0.95)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(Palette.ink.opacity(0.45))
                    .overlay(Capsule().strokeBorder(.white.opacity(editable ? 0.35 : 0.15), lineWidth: 2)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(editable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Table name, \(name)", comment: "VoiceOver: the table's name"))
        .accessibilityHint(editable ? Text("Rename the table", comment: "VoiceOver: tap the table's name") : Text(""))
        .accessibilityAddTraits(editable ? .isButton : .isStaticText)
    }
}

/// A chunky cartoon pencil, tilted up to the right: yellow-orange body, pink eraser, ink outline.
struct PencilMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let w = s * 0.34
            let len = s * 1.15
            ZStack {
                // Body, eraser band and eraser, drawn left to right; the tip is a triangle.
                HStack(spacing: 0) {
                    Triangle()
                        .fill(Palette.ink)
                        .frame(width: w * 0.45, height: w * 0.45)
                        .padding(.trailing, -1)
                    Triangle()
                        .fill(.white)
                        .overlay(Triangle().stroke(Palette.ink, lineWidth: 2))
                        .frame(width: w * 0.55, height: w)
                        .padding(.leading, -w * 0.12)
                    Rectangle()
                        .fill(Palette.orange.mix(with: .yellow, by: 0.45))
                        .overlay(Rectangle().stroke(Palette.ink, lineWidth: 2))
                        .frame(width: len * 0.55, height: w)
                    Rectangle()
                        .fill(Palette.magenta)
                        .overlay(Rectangle().stroke(Palette.ink, lineWidth: 2))
                        .frame(width: len * 0.18, height: w)
                }
                // Tip down-left, eraser up-right, like a pencil in a hand.
                .rotationEffect(.degrees(-45))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// A triangle pointing left (the pencil's tip).
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Renames the table: a big name field with a dice for a fresh cat-themed name, Back and Done.
/// Done is live only for a well-formed name (`TableName.clean`); the server's name filter is
/// asked before it is handed back, and a refused name says so under the field.
struct RenameTableView: View {
    @Environment(AppModel.self) private var model
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var name: String
    @State private var diceSpin = 0
    @State private var refusal: String?
    @State private var checking = false
    @FocusState private var focused: Bool

    init(current: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: current)
    }

    private var cleaned: String? { TableName.clean(name) }

    var body: some View {
        VStack(spacing: 20) {
            OutlinedText(
                String(localized: "Name this table", comment: "Rename sheet: title"), size: 26, fill: .white)
                .padding(.top, 20)
            HStack(spacing: 12) {
                TextField("", text: $name)
                    .focused($focused)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
                    .onChange(of: name) { _, new in
                        let clipped = TableName.clamp(new)
                        if clipped != new { name = clipped }
                        refusal = nil
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 58)
                    .background(Capsule().fill(.white))
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4))
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 5)
                    .accessibilityLabel(Text("Table name", comment: "VoiceOver: the rename field"))
                    .accessibilityIdentifier("rename.field")
                PillButton(icon: ArtName.iconDice, color: Palette.orange, size: .small, accessibilityLabel: "Pick a new name") {
                    var rng = SystemRandomNumberGenerator()
                    name = TableName.random(using: &rng)
                    diceSpin += 1
                }
                .wiggle(trigger: diceSpin)
                .accessibilityIdentifier("rename.dice")
            }
            if let refusal { NameRefusal(text: refusal) }
            HStack(spacing: 16) {
                PillButton(icon: ArtName.iconBack, color: Palette.sky, size: .medium, accessibilityLabel: "Back") {
                    onCancel()
                }
                .accessibilityIdentifier("rename.cancel")
                PillButton(icon: ArtName.iconCheck, color: Palette.lime, size: .large, width: 190, accessibilityLabel: "Done") {
                    save()
                }
                .disabled(cleaned == nil || checking)
                .saturation(cleaned == nil ? 0 : 1)
                .opacity(cleaned == nil ? 0.55 : 1)
                .accessibilityIdentifier("rename.done")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
        .animation(.spring(duration: 0.3, bounce: 0.3).paced, value: refusal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-rename")
    }

    private func save() {
        guard let cleaned, !checking else { return }
        checking = true
        Task {
            let verdict = await NameGate.verdict(model.api, cleaned, kind: .table)
            checking = false
            if let words = NameGate.words(verdict) {
                refusal = words
                Haptics.shared.thump()
                UIAccessibility.post(notification: .announcement, argument: words)
            } else {
                focused = false
                onSave(cleaned)
            }
        }
    }
}
