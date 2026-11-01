import SwiftUI

/// Chunky toy lettering: SF Pro Rounded Black with a thick dark outline, drawn as
/// 8 offset copies behind the fill.
struct OutlinedText: View {
    let text: String
    let size: CGFloat
    let fill: Color
    let outline: Color
    let width: CGFloat

    init(_ text: String, size: CGFloat, fill: Color = .white, outline: Color = Palette.ink, width: CGFloat = 3) {
        self.text = text
        self.size = size
        self.fill = fill
        self.outline = outline
        self.width = width
    }

    private static let directions: [CGSize] = [
        CGSize(width: 1, height: 0), CGSize(width: -1, height: 0),
        CGSize(width: 0, height: 1), CGSize(width: 0, height: -1),
        CGSize(width: 0.7071, height: 0.7071), CGSize(width: -0.7071, height: 0.7071),
        CGSize(width: 0.7071, height: -0.7071), CGSize(width: -0.7071, height: -0.7071),
    ]

    private var label: Text {
        Text(text).font(.system(size: size, weight: .black, design: .rounded))
    }

    var body: some View {
        ZStack {
            ForEach(Self.directions.indices, id: \.self) { i in
                label
                    .foregroundStyle(outline)
                    .offset(x: Self.directions[i].width * width, y: Self.directions[i].height * width)
                    .accessibilityHidden(true)
            }
            label.foregroundStyle(fill)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }
}
