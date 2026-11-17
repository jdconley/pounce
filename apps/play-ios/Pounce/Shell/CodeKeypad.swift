import PounceKit
import SwiftUI

/// A chunky 3D keypad holding only the room-code alphabet: letters wrapped five to a row (the
/// last letter row ends with delete), digits on the last row. Join types a room code (five
/// characters) with it, and Show on TV a TV's code (six); `CodeTiles` shows what was typed.
struct CodeKeypad: View {
    /// The character keys take taps.
    var enabled = true
    /// The delete key takes taps (nil: same as `enabled`). Join keeps it live while a code is
    /// being checked, since deleting cancels the check.
    var deleteEnabled: Bool?
    /// Key height, the characters' size and the gap between keys (bigger on a roomy screen).
    var keyHeight: CGFloat = 54
    var keySize: CGFloat = 30
    var spacing: CGFloat = 8
    /// The keys' identifiers: `join.key.B`, `join.key.delete` (Show on TV's: `tv.key.B`).
    var idPrefix = "join.key"
    let onKey: (Character) -> Void
    let onDelete: () -> Void

    static let letters = Array(RoomCode.alphabet.filter(\.isLetter))
    static let digits = Array(RoomCode.alphabet.filter(\.isNumber))
    private static let perRow = 5

    private static var letterRows: [[Character]] {
        stride(from: 0, to: letters.count, by: perRow).map { Array(letters[$0..<min($0 + perRow, letters.count)]) }
    }

    var body: some View {
        VStack(spacing: spacing + 2) {
            let rows = Self.letterRows
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: spacing) {
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
            HStack(spacing: spacing - 2) {
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
            OutlinedText(String(c), size: keySize, width: 2.5)
        }
        .buttonStyle(KeyStyle(color: Palette.magenta, height: keyHeight))
        .disabled(!enabled)
        .groupOpacity(enabled ? 1 : 0.6)
        .accessibilityLabel(Text(verbatim: String(c)))
        .accessibilityIdentifier("\(idPrefix).\(c)")
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
                .frame(height: keySize)
        }
        .buttonStyle(KeyStyle(color: Palette.teal, height: keyHeight))
        .disabled(!(deleteEnabled ?? enabled))
        .groupOpacity(deleteEnabled ?? enabled ? 1 : 0.6)
        .accessibilityLabel("Delete")
        .accessibilityIdentifier("\(idPrefix).delete")
    }
}

/// A code's tiles on their panel, one per character: five for a room code (Join), six for a
/// TV's code (Show on TV). The next slot to fill glows unless `busy` (the code is being checked).
struct CodeTiles: View {
    let typed: String
    let length: Int
    var busy = false
    /// The tiles' identifiers: `join.tile.0` … (Show on TV's: `tv.tile.0` …).
    var idPrefix = "join.tile"

    var body: some View {
        let chars = Array(typed)
        HStack(spacing: length > 5 ? 6 : 8) {
            ForEach(0..<length, id: \.self) { i in
                CodeTile(
                    char: i < chars.count ? chars[i] : nil,
                    active: i == min(chars.count, length - 1) && !busy)
                    .accessibilityIdentifier("\(idPrefix).\(i)")
            }
        }
        .padding(length > 5 ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(
                    colors: [Palette.violet.mix(with: Palette.ink, by: 0.25), Palette.night],
                    startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.ink, lineWidth: 5))
                .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 6)
        )
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
        .animation(.spring(duration: 0.1, bounce: 0.2).paced, value: configuration.isPressed)
    }
}
