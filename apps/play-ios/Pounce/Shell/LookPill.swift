import PounceKit
import SwiftUI

/// The pill that floats down when someone changes the table's look (§9.4): their cat and the new
/// rug or back. No words.
struct LookPill: View {
    let cat: Int
    let art: String
    let isBack: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(ArtName.cat(cat, .awake)).resizable().scaledToFit().frame(width: 40, height: 40)
            Image(systemName: "arrow.right").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
            Group {
                if isBack {
                    Image(uiImage: CardFaceFactory.backImage(art)).resizable().scaledToFit().frame(width: 30, height: 42)
                } else {
                    Image(art).resizable().scaledToFit().frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.magenta).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4)))
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("The table changed", comment: "VoiceOver: someone changed the table's rug or card back"))
        .accessibilityIdentifier("look.pill")
    }
}
