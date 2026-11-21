import PounceKit
import SwiftUI

/// Sniff's own keyboard: chunky candy keys that carry the server's marks as the tags do (a
/// filled paw, an outlined paw, or dimmed), with Delete at the end of the last row and a wide
/// Sniff button under it to send the word.
struct SniffKeyboard: View {
    let marks: [Character: SniffMark]
    let width: CGFloat
    let enabled: Bool
    let canSend: Bool
    let onLetter: (Character) -> Void
    let onDelete: () -> Void
    let onSend: () -> Void

    static let rows: [String] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    static let gap: CGFloat = 6

    var keyWidth: CGFloat { (width - 9 * Self.gap) / 10 }
    var keyHeight: CGFloat { min(60, max(44, keyWidth * 1.3)) }
    var sendHeight: CGFloat { max(50, keyHeight) }

    /// The keyboard's height for a given width.
    static func height(width: CGFloat) -> CGFloat {
        let k = SniffKeyboard(marks: [:], width: width, enabled: true, canSend: true, onLetter: { _ in }, onDelete: {}, onSend: {})
        return 3 * k.keyHeight + 3 * gap + k.sendHeight + 4
    }

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(Array(row), id: \.self) { letter in
                        LetterKey(letter: letter, mark: marks[letter], size: CGSize(width: keyWidth, height: keyHeight)) {
                            onLetter(letter)
                        }
                    }
                    if row == Self.rows.last {
                        DeleteKey(size: CGSize(width: keyWidth * 1.6 + Self.gap, height: keyHeight), action: onDelete)
                    }
                }
            }
            SendKey(height: sendHeight, enabled: canSend, action: onSend)
                .padding(.top, 2)
        }
        .disabled(!enabled)
        .frame(width: width)
    }
}

/// A key's chunky toy look: a colored top on a darker lip that presses down.
private struct SniffKeyStyle: ButtonStyle {
    let fill: Color
    let lip: Color
    let corner: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Palette.ink, lineWidth: 2.5))
            .offset(y: down ? 3 : 0)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(lip)
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Palette.ink, lineWidth: 2.5))
                    .offset(y: 4)
            )
            .compositingGroup()
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: down)
    }
}

private struct LetterKey: View {
    let letter: Character
    let mark: SniffMark?
    let size: CGSize
    let action: () -> Void

    private var fill: Color {
        switch mark {
        case .spot: Palette.magenta
        case .near: Palette.sky
        case .some(.none): SniffArt.plain
        case nil: .white
        }
    }

    var body: some View {
        Button {
            Haptics.shared.tick()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(String(letter).uppercased())
                    .font(.system(size: min(size.width * 0.62, 26), weight: .black, design: .rounded))
                    .foregroundStyle(mark == nil ? Palette.ink : mark == SniffMark.none ? .white.opacity(0.45) : .white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if mark == .spot {
                    PawPrint().fill(.white).frame(width: size.width * 0.32, height: size.width * 0.32).padding(3)
                } else if mark == .near {
                    PawPrint().stroke(.white, lineWidth: 1.5).frame(width: size.width * 0.32, height: size.width * 0.32).padding(3)
                }
            }
        }
        .buttonStyle(SniffKeyStyle(fill: fill, lip: fill == .white ? Color(hex: 0xC9B8FF) : Palette.ink, corner: 9))
        .frame(width: size.width, height: size.height)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityLabel(String(letter).uppercased())
        .accessibilityValue(markWords)
    }

    private var markWords: String {
        switch mark {
        case .spot: String(localized: "right spot")
        case .near: String(localized: "elsewhere")
        case .some(.none): String(localized: "not in the word")
        case nil: ""
        }
    }
}

private struct DeleteKey: View {
    let size: CGSize
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tick()
            action()
        } label: {
            Image(systemName: "delete.left.fill")
                .font(.system(size: min(size.height * 0.42, 24), weight: .bold))
                .foregroundStyle(.white)
        }
        .buttonStyle(SniffKeyStyle(fill: Palette.violet, lip: Palette.ink, corner: 9))
        .frame(width: size.width, height: size.height)
        .accessibilityLabel(String(localized: "Delete"))
    }
}

private struct SendKey: View {
    let height: CGFloat
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill").font(.system(size: height * 0.4, weight: .black))
                OutlinedText(String(localized: "Sniff"), size: height * 0.44, width: 2.5)
            }
            .foregroundStyle(.white)
            .opacity(enabled ? 1 : 0.5)
        }
        // Waiting for five letters, it sits back in violet; ready, it lights up orange.
        .buttonStyle(SniffKeyStyle(fill: enabled ? Palette.orange : Palette.violet, lip: Palette.ink, corner: height / 2))
        .frame(height: height)
        .accessibilityLabel(String(localized: "Sniff"))
        .accessibilityHint(String(localized: "Sends the word"))
    }
}
