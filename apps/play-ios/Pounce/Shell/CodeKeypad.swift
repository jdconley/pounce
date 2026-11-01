import PounceKit
import SwiftUI

/// A chunky 3D keypad holding only the room-code alphabet: letters wrapped five to a row (the
/// last letter row ends with delete), digits on the last row.
struct CodeKeypad: View {
    /// The character keys take taps.
    var enabled = true
    /// The delete key takes taps (nil: same as `enabled`). Join keeps it live while a code is
    /// being checked, since deleting cancels the check.
    var deleteEnabled: Bool?
    let onKey: (Character) -> Void
    let onDelete: () -> Void

    static let letters = Array(RoomCode.alphabet.filter(\.isLetter))
    static let digits = Array(RoomCode.alphabet.filter(\.isNumber))
    private static let perRow = 5

    private static var letterRows: [[Character]] {
        stride(from: 0, to: letters.count, by: perRow).map { Array(letters[$0..<min($0 + perRow, letters.count)]) }
    }

    var body: some View {
        VStack(spacing: 10) {
            let rows = Self.letterRows
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r], id: \.self) { key($0) }
                    if r == rows.count - 1 {
                        deleteKey
                        // Pad a short row so its keys keep the full-row width.
                        ForEach(0..<max(0, Self.perRow - rows[r].count - 1), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(Self.digits, id: \.self) { key($0) }
            }
        }
    }

    private func key(_ c: Character) -> some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            onKey(c)
        } label: {
            OutlinedText(String(c), size: 30, width: 2.5)
        }
        .buttonStyle(KeyStyle(color: Palette.magenta))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
        .accessibilityLabel(Text(verbatim: String(c)))
        .accessibilityIdentifier("join.key.\(c)")
    }

    private var deleteKey: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            onDelete()
        } label: {
            Image(ArtName.iconDelete)
                .resizable()
                .scaledToFit()
                .frame(height: 30)
        }
        .buttonStyle(KeyStyle(color: Palette.teal))
        .disabled(!(deleteEnabled ?? enabled))
        .opacity(deleteEnabled ?? enabled ? 1 : 0.6)
        .accessibilityLabel("Delete")
        .accessibilityIdentifier("join.key.delete")
    }
}

/// One keypad key: a glossy rounded block with a thick ink outline, a darker lip and a press-down.
struct KeyStyle: ButtonStyle {
    let color: Color
    var height: CGFloat = 54

    private static let lip: CGFloat = 5
    private static let radius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let travel = configuration.isPressed ? Self.lip - 1 : 0
        ZStack(alignment: .top) {
            shape
                .fill(color.mix(with: Palette.ink, by: 0.5))
                .overlay(shape.strokeBorder(Palette.ink, lineWidth: 3.5))
                .frame(height: height)
                .offset(y: Self.lip)
            shape
                .fill(LinearGradient(
                    colors: [color.mix(with: .white, by: 0.3), color, color.mix(with: Palette.violet, by: 0.35)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(0.4))
                        .frame(height: 6)
                        .padding(.horizontal, 10)
                        .padding(.top, 5)
                }
                .overlay(shape.strokeBorder(Palette.ink, lineWidth: 3.5))
                .overlay { configuration.label }
                .frame(height: height)
                .offset(y: travel)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height + Self.lip)
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.1, bounce: 0.2), value: configuration.isPressed)
    }
}
