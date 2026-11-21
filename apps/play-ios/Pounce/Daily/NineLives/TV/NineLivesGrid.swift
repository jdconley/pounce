import PounceKit
import SwiftUI

/// What the grid draws besides the board itself. The play view fills it in; the TV's watch view
/// leaves it empty.
struct NineLivesMarks: Equatable {
    var selected: Int?
    /// Pencil marks per cell, the play view's own (never sent).
    var notes: [Set<Int>] = []
    /// Bumped on each placement, so that tile pops.
    var placed: (cell: Int, count: Int)?
    /// Bumped when a move makes a clash, so the clashing tiles wiggle.
    var clashBump = 0
    /// Set when the grid is solved: the tiles wave.
    var solved = false

    static func == (a: Self, b: Self) -> Bool {
        a.selected == b.selected && a.notes == b.notes && a.placed?.cell == b.placed?.cell
            && a.placed?.count == b.placed?.count && a.clashBump == b.clashBump && a.solved == b.solved
    }
}

/// The 9 by 9 quilt: cushions, sockets, paw tiles, notes and highlights. Square; it takes the
/// largest square that fits.
struct NineLivesGrid: View {
    let board: NineLivesBoard
    let clashes: Set<Int>
    var marks = NineLivesMarks()
    /// Nil: read only (the TV).
    var onTap: ((Int) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let m = Metrics(side: side)
            ZStack(alignment: .topLeading) {
                frame(m)
                ForEach(0..<9, id: \.self) { box in
                    RoundedRectangle(cornerRadius: m.cushionCorner, style: .continuous)
                        .fill((box % 2 == 0) ? NineLivesStyle.cushionA : NineLivesStyle.cushionB)
                        .frame(width: m.boxSide, height: m.boxSide)
                        .offset(x: m.boxOrigin(box % 3), y: m.boxOrigin(box / 3))
                }
                ForEach(0..<81, id: \.self) { i in
                    cell(i, m)
                        .frame(width: m.cell, height: m.cell)
                        .offset(x: m.cellOrigin(i % 9), y: m.cellOrigin(i / 9))
                }
            }
            .frame(width: side, height: side + m.lip)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func frame(_ m: Metrics) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: m.frameCorner, style: .continuous)
                .fill(Palette.violet.mix(with: Palette.ink, by: 0.55))
                .frame(width: m.side, height: m.side)
                .offset(y: m.lip)
            RoundedRectangle(cornerRadius: m.frameCorner, style: .continuous)
                .fill(Palette.ink)
                .frame(width: m.side, height: m.side)
        }
    }

    private func lit(_ i: Int) -> Bool {
        guard let s = marks.selected, s != i else { return false }
        return s / 9 == i / 9 || s % 9 == i % 9 || (s / 27 == i / 27 && s % 9 / 3 == i % 9 / 3)
    }

    private var selectedDigit: Int? { marks.selected.map { board.cells[$0] }.flatMap { $0 == 0 ? nil : $0 } }

    @ViewBuilder
    private func cell(_ i: Int, _ m: Metrics) -> some View {
        let digit = board.cells[i]
        let isSelected = marks.selected == i
        let content = ZStack {
            RoundedRectangle(cornerRadius: m.cell * 0.22, style: .continuous)
                .fill(lit(i) ? NineLivesStyle.socketLit : NineLivesStyle.socket)
                .padding(m.cell * 0.06)
            if digit != 0 {
                PawTile(digit: digit, kind: kind(i), size: m.cell * 0.9)
                    .overlay {
                        if selectedDigit == digit && !isSelected {
                            PawShape().stroke(NineLivesStyle.sameRing, lineWidth: max(2, m.cell * 0.07))
                                .frame(width: m.cell * 0.98, height: m.cell * 0.98)
                        }
                    }
                    .modifier(TileMotion(cell: i, marks: marks, clashing: clashes.contains(i)))
            } else if i < marks.notes.count, !marks.notes[i].isEmpty {
                NotesView(notes: marks.notes[i], size: m.cell)
            }
            if isSelected {
                RoundedRectangle(cornerRadius: m.cell * 0.26, style: .continuous)
                    .strokeBorder(NineLivesStyle.selectRing, lineWidth: max(2.5, m.cell * 0.09))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Row \(i / 9 + 1), column \(i % 9 + 1)"))
        .accessibilityValue(Text(verbatim: accessibilityValue(i)))
        .accessibilityIdentifier("nine-lives-cell-\(i)")
        if let onTap {
            content
                .onTapGesture { onTap(i) }
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { onTap(i) }
        } else {
            content
        }
    }

    private func kind(_ i: Int) -> PawTile.Kind {
        if clashes.contains(i) && !board.isGiven(i) { return .clash }
        if board.isGiven(i) { return .given }
        if board.hinted.contains(i) { return .hinted }
        return .mine
    }

    private func accessibilityValue(_ i: Int) -> String {
        let d = board.cells[i]
        if d == 0 {
            let notes = i < marks.notes.count ? marks.notes[i].sorted() : []
            return notes.isEmpty ? "Empty" : "Notes \(notes.map(String.init).joined(separator: " "))"
        }
        var parts = ["\(d)"]
        if board.isGiven(i) { parts.append("given") } else if board.hinted.contains(i) { parts.append("hint") }
        if clashes.contains(i) { parts.append("clash") }
        return parts.joined(separator: ", ")
    }

    /// The quilt's sizes for one side length.
    struct Metrics {
        let side: CGFloat
        var pad: CGFloat { side * 0.022 }
        var boxGap: CGFloat { side * 0.016 }
        var cellGap: CGFloat { side * 0.004 }
        var boxSide: CGFloat { (side - pad * 2 - boxGap * 2) / 3 }
        var cell: CGFloat { (boxSide - cellGap * 2 - boxInset * 2) / 3 }
        var boxInset: CGFloat { side * 0.006 }
        var lip: CGFloat { max(3, side * 0.014) }
        var frameCorner: CGFloat { side * 0.05 }
        var cushionCorner: CGFloat { side * 0.03 }
        func boxOrigin(_ k: Int) -> CGFloat { pad + CGFloat(k) * (boxSide + boxGap) }
        func cellOrigin(_ k: Int) -> CGFloat {
            boxOrigin(k / 3) + boxInset + CGFloat(k % 3) * (cell + cellGap)
        }
    }
}

/// Pencil marks: up to nine small digits in a 3 by 3.
private struct NotesView: View {
    let notes: Set<Int>
    let size: CGFloat

    var body: some View {
        let s = size / 3.3
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(1...3, id: \.self) { c in
                        let d = r * 3 + c
                        Text(verbatim: notes.contains(d) ? "\(d)" : " ")
                            .font(.system(size: s * 0.8, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .frame(width: s, height: s)
                    }
                }
            }
        }
    }
}

/// A tile's motion: it pops when placed, wiggles when it clashes, and waves when the grid is solved.
private struct TileMotion: ViewModifier {
    let cell: Int
    let marks: NineLivesMarks
    let clashing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let wave = marks.solved && !reduceMotion
        content
            .pop(trigger: marks.placed?.cell == cell ? marks.placed?.count ?? 0 : 0)
            .wiggle(trigger: clashing ? marks.clashBump : 0)
            .scaleEffect(wave ? 1.08 : 1)
            .animation(
                wave
                    ? .spring(duration: 0.4, bounce: 0.5).delay(Double(cell / 9 + cell % 9) * 0.035).paced
                    : .default, value: marks.solved)
    }
}
