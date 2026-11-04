import SwiftUI

/// A player's name on a pill, the SwiftUI twin of the table's (`CardFaceFactory.nameTag`): white
/// on ink inside a white keyline (18:1 on any background), or ink on orange for whoever's turn
/// it is (7.6:1). SF Pro Rounded Black at an 11 pt cap height or more; a long name is cut short
/// with an ellipsis, never shrunk.
struct NameTag: View {
    let name: String
    var maxWidth: CGFloat = 140
    var active = false
    var size: CGFloat = 16

    init(_ name: String, maxWidth: CGFloat = 140, active: Bool = false, size: CGFloat = 16) {
        self.name = name
        self.maxWidth = maxWidth
        self.active = active
        self.size = size
    }

    var body: some View {
        let pad = size * 0.45
        CappedWidth(max: maxWidth - 2 * pad) {
            Text(verbatim: name)
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundStyle(active ? Palette.ink : .white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, pad)
        .padding(.vertical, 2)
        .background(Capsule().fill(active ? Palette.orange : Palette.ink))
        .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
    }
}

/// Offers its one child at most `max` points of width, even when asked for its ideal size, so
/// text inside truncates instead of growing.
private struct CappedWidth: Layout {
    let max: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? max, max), height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Lays its children out left to right, wrapping onto new lines, each line centered.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(width: proposal.width ?? .infinity, subviews: subviews)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - line.width) / 2
            for i in line.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let grown = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if !line.items.isEmpty, grown > width {
                lines.append(line)
                line = Line()
            }
            line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.items.append(i)
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
