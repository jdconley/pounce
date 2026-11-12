import SwiftUI

/// Chunky toy lettering: SF Pro Rounded Black with a thick dark outline, drawn as
/// 8 offset copies behind the fill, composited as one layer (faded, the copies would show
/// through each other).
struct OutlinedText: View {
    let text: String
    let size: CGFloat
    let fill: Color
    let outline: Color
    let width: CGFloat
    /// Wraps onto up to this many lines (centered unless `alignment` says otherwise) before shrinking.
    let lines: Int
    let alignment: TextAlignment

    init(
        _ text: String, size: CGFloat, fill: Color = .white, outline: Color = Palette.ink, width: CGFloat = 3,
        lines: Int = 1, alignment: TextAlignment = .center
    ) {
        self.text = text
        self.size = size
        self.fill = fill
        self.outline = outline
        self.width = width
        self.lines = lines
        self.alignment = alignment
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
        ZStack(alignment: alignment == .leading ? .leading : alignment == .trailing ? .trailing : .center) {
            ForEach(Self.directions.indices, id: \.self) { i in
                label
                    .foregroundStyle(outline)
                    .offset(x: Self.directions[i].width * width, y: Self.directions[i].height * width)
                    .accessibilityHidden(true)
            }
            label.foregroundStyle(fill)
        }
        // One layer, so a fade on any parent fades the lettering whole, not each copy.
        .compositingGroup()
        .lineLimit(lines)
        .multilineTextAlignment(alignment)
        .minimumScaleFactor(0.5)
        .padding(width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }
}
