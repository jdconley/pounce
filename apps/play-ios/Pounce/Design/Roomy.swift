import SwiftUI

/// iPad-sized space for the shell screens. A screen switches to its roomy layout only in a
/// regular-width window (an iPad full screen or a wide multitasking window); every iPhone and a
/// narrow iPad window are compact width and keep the phone layout as it is.
enum Roomy {
    /// A roomy window wide enough for two columns side by side (an iPad in landscape, a wide
    /// Stage Manager window): wider than tall, and at least `minWidth` points across.
    static func sideBySide(_ size: CGSize, minWidth: CGFloat = 900) -> Bool {
        size.width >= minWidth && size.width > size.height * 1.1
    }
}

/// A rounded, see-through panel with a thick ink outline that groups content on a roomy screen
/// (Home's tables, the lobby's code and invite).
struct RoomyPanel<Content: View>: View {
    var color: Color = Palette.violet
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        content
            .background(
                shape
                    .fill(LinearGradient(
                        colors: [color.mix(with: Palette.ink, by: 0.35).opacity(0.82), Palette.night.opacity(0.88)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Palette.ink, lineWidth: 5))
                    .overlay(shape.strokeBorder(color.mix(with: .white, by: 0.2).opacity(0.7), lineWidth: 2).padding(5))
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 8)
            )
    }
}
