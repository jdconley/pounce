import SwiftUI

/// Pounce on the Apple TV. For now the title card only: the name and tagline on the brand
/// background. The home, lobby and table screens come with the shared table code.
@main
struct PounceTVApp: App {
    var body: some Scene {
        WindowGroup {
            TitleCard()
        }
    }
}

/// The name in the app's lettering (SF Rounded Black with the chunky ink outline) and the tagline,
/// centered on the violet-to-magenta brand background. Laid out for 1920x1080 points.
struct TitleCard: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.night, Palette.violet, Palette.magenta], startPoint: .bottomLeading, endPoint: .topTrailing)
            VStack(spacing: 24) {
                outlined("Pounce", size: 220, fill: .white)
                outlined("Family game night, every night", size: 64, fill: Palette.yellow)
            }
            .accessibilityElement(children: .combine)
        }
        .ignoresSafeArea()
    }

    /// Text with an ink outline: the ink copy offset round the fill, then the fill on top.
    private func outlined(_ text: String, size: CGFloat, fill: Color) -> some View {
        let font = Font.system(size: size, weight: .black, design: .rounded)
        let w = size * 0.07
        let offsets: [CGSize] = (0..<12).map { i in
            let a = Double(i) / 12 * 2 * .pi
            return CGSize(width: cos(a) * w, height: sin(a) * w + size * 0.03)
        }
        return ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                Text(text).font(font).foregroundStyle(Palette.ink).offset(offsets[i])
            }
            Text(text).font(font).foregroundStyle(fill)
        }
        .compositingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
