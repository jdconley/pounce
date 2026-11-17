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
    // The Loud Toy palette (Pounce/Design/Palette.swift), until the TV shares that file.
    private static let ink = Color(red: 0x1B / 255, green: 0x0B / 255, blue: 0x3A / 255)
    private static let night = Color(red: 0x2A / 255, green: 0x0F / 255, blue: 0x5C / 255)
    private static let violet = Color(red: 0x7B / 255, green: 0x2F / 255, blue: 0xFF / 255)
    private static let magenta = Color(red: 0xFF / 255, green: 0x2E / 255, blue: 0x9A / 255)
    private static let yellow = Color(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x1F / 255)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Self.night, Self.violet, Self.magenta], startPoint: .bottomLeading, endPoint: .topTrailing)
            VStack(spacing: 24) {
                outlined("Pounce", size: 220, fill: .white)
                outlined("Family game night, every night", size: 64, fill: Self.yellow)
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
                Text(text).font(font).foregroundStyle(Self.ink).offset(offsets[i])
            }
            Text(text).font(font).foregroundStyle(fill)
        }
        .compositingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
