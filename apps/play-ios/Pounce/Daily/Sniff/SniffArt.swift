import PounceKit
import SwiftUI

// Sniff's drawing, shared by the play view and the TV's watch view: scent tags hung on six
// trails, each tag stamped by the server's mark. Marks are shapes as well as colors (spec §1):
// a filled paw for the right spot, an outlined paw for elsewhere, and a plain tag for neither.
// SwiftUI and Palette only, so the Apple TV target can build it.

/// A paw print: one pad and four toes, in a unit square.
struct PawPrint: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.addEllipse(in: CGRect(x: rect.minX + w * 0.22, y: rect.minY + h * 0.44, width: w * 0.56, height: h * 0.46))
        let toes: [(CGFloat, CGFloat)] = [(0.02, 0.30), (0.24, 0.06), (0.52, 0.06), (0.74, 0.30)]
        for (x, y) in toes {
            p.addEllipse(in: CGRect(x: rect.minX + w * x, y: rect.minY + h * y, width: w * 0.24, height: h * 0.30))
        }
        return p
    }
}

/// A scent tag: a card with its top corners clipped and a hole to hang it by.
struct TagShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cut = w * 0.26
        let r = w * 0.14
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        p.closeSubpath()
        p.addEllipse(in: Self.hole(in: rect))
        return p
    }

    static func hole(in rect: CGRect) -> CGRect {
        let d = rect.width * 0.16
        return CGRect(x: rect.midX - d / 2, y: rect.minY + rect.width * 0.09, width: d, height: d)
    }
}

/// What a tag shows.
enum TagFace: Equatable {
    /// Not reached yet.
    case empty
    /// An empty tag on the row being typed.
    case slot
    /// Typed, not sent (or sent and waiting).
    case typed(Character)
    /// The server's mark.
    case marked(Character, SniffMark)
    /// The answer, shown when the run ended without it.
    case answer(Character)

    var letter: Character? {
        switch self {
        case .empty, .slot: nil
        case .typed(let c), .marked(let c, _), .answer(let c): c
        }
    }

    var fill: Color {
        switch self {
        case .empty: Palette.violet.opacity(0.22)
        case .slot: Palette.violet.opacity(0.55)
        case .typed: .white
        case .marked(_, .spot): Palette.magenta
        case .marked(_, .near): Palette.sky
        case .marked(_, .none): SniffArt.plain
        case .answer: Palette.yellow
        }
    }

    var ink: Color {
        switch self {
        case .typed, .answer: Palette.ink
        case .marked(_, .none): .white.opacity(0.6)
        default: .white
        }
    }

    var spoken: String {
        guard let letter else { return String(localized: "Empty") }
        let l = letter.uppercased()
        switch self {
        case .marked(_, .spot): return String(localized: "\(l), right spot")
        case .marked(_, .near): return String(localized: "\(l), elsewhere")
        case .marked(_, .none): return String(localized: "\(l), not in the word")
        case .answer: return String(localized: "\(l), the word")
        default: return l
        }
    }
}

enum SniffArt {
    /// A plain tag: the panel violet, darker than the night background's tags.
    static let plain = Color(hex: 0x3B1580)
    /// Each tag's tilt in a row, so a trail reads as tags hung by hand, not a grid.
    static let tilts: [Double] = [-4, 3, -2, 4, -3]
}

/// One scent tag, `width` wide, swung from its hole.
struct ScentTag: View {
    let face: TagFace
    let width: CGFloat
    var tilt: Double = 0

    var height: CGFloat { width * 1.2 }

    var body: some View {
        let outline = max(2, width * 0.05)
        ZStack {
            TagShape().fill(face.fill, style: FillStyle(eoFill: true))
            if face == .empty || face == .slot {
                TagShape().stroke(.white.opacity(face == .slot ? 0.75 : 0.28), style: StrokeStyle(lineWidth: outline * 0.6, dash: [width * 0.08, width * 0.06]))
            } else {
                TagShape().stroke(Palette.ink, lineWidth: outline)
            }
            if let letter = face.letter {
                OutlinedText(
                    String(letter).uppercased(), size: width * 0.52, fill: face.ink,
                    outline: face.ink == Palette.ink ? .clear : Palette.ink, width: max(1.5, width * 0.035)
                )
                .offset(y: width * 0.1)
            }
            if case .marked(_, let mark) = face, mark != .none {
                stamp(mark).frame(width: width * 0.3, height: width * 0.3)
                    .position(x: width * 0.78, y: height * 0.82)
            }
        }
        .frame(width: width, height: height)
        .compositingGroup()
        .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.5, y: 0.14))
        .accessibilityElement()
        .accessibilityLabel(face.spoken)
    }

    @ViewBuilder private func stamp(_ mark: SniffMark) -> some View {
        if mark == .spot {
            PawPrint().fill(.white).overlay(PawPrint().stroke(Palette.ink, lineWidth: max(1, width * 0.02)))
        } else {
            PawPrint().stroke(.white, lineWidth: max(1.5, width * 0.035))
        }
    }
}

/// The six trails: the server's guesses, the row being typed, and empty tags for what's left.
/// The answer hangs on its own trail below when the run ended without it.
struct SniffTrail: View {
    let board: SniffBoard
    let tagWidth: CGFloat
    var shake = 0
    var showAnswer = true

    static let gap: CGFloat = 0.14
    static let rowGap: CGFloat = 0.2

    /// The tag width that fits six rows (seven with the answer) in `size`.
    static func tagWidth(fitting size: CGSize, rows: Int = SniffBoard.tries, cap: CGFloat = 72) -> CGFloat {
        let byWidth = size.width / (5 + 4 * gap)
        let byHeight = size.height / (CGFloat(rows) * 1.2 + CGFloat(rows - 1) * rowGap)
        return max(18, min(byWidth, byHeight, cap))
    }

    var body: some View {
        VStack(spacing: tagWidth * Self.rowGap) {
            ForEach(0..<SniffBoard.tries, id: \.self) { row in
                trail(faces(row))
                    .shake(trigger: row == board.guesses.count ? shake : 0)
            }
            if showAnswer, let answer = board.answer, !board.isSolved {
                trail(answer.map { .answer($0) })
                    .padding(.top, tagWidth * 0.12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "The word was \(answer.uppercased())"))
            }
        }
    }

    private func faces(_ row: Int) -> [TagFace] {
        if row < board.guesses.count {
            let g = board.guesses[row]
            return zip(g.word, g.marks).map { .marked($0, $1) }
        }
        if row == board.guesses.count, !board.isOver {
            let typed = Array(board.pending ?? board.draft)
            return (0..<SniffBoard.letters).map { $0 < typed.count ? .typed(typed[$0]) : .slot }
        }
        return Array(repeating: .empty, count: SniffBoard.letters)
    }

    private func trail(_ faces: [TagFace]) -> some View {
        let gap = tagWidth * Self.gap
        return HStack(spacing: gap) {
            ForEach(Array(faces.enumerated()), id: \.offset) { i, face in
                ScentTag(face: face, width: tagWidth, tilt: SniffArt.tilts[i])
                    .pop(trigger: face.letter)
            }
        }
        .background(alignment: .top) {
            // The string the tags hang on, through their holes, sagging a little.
            Canvas { ctx, size in
                let y = tagWidth * 0.17
                var p = Path()
                p.move(to: CGPoint(x: -gap, y: y))
                p.addQuadCurve(to: CGPoint(x: size.width + gap, y: y), control: CGPoint(x: size.width / 2, y: y + tagWidth * 0.18))
                ctx.stroke(p, with: .color(.white.opacity(0.35)), lineWidth: max(1.5, tagWidth * 0.03))
            }
            .frame(height: tagWidth * 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}
