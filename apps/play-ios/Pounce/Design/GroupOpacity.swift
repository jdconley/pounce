import SwiftUI

extension View {
    /// Fades this view as one layer. `.opacity` on a container fades each piece inside on its
    /// own, so overlapping pieces (a button's label on its pill, the 8 outline copies of
    /// `OutlinedText`, a badge on a cat) show through each other. Use this in place of
    /// `.opacity` on anything built from overlapping parts; `.opacity` stays fine for a single
    /// image or line of text. The SpriteKit counterpart is `FadeGroup`.
    func groupOpacity(_ value: Double) -> some View {
        compositingGroup().opacity(value)
    }
}
