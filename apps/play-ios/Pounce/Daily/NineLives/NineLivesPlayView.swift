import PounceKit
import SwiftUI

/// Nine Lives being played: the quilt, the number row, and Notes, Erase and Hint. The Daily Dish
/// host draws everything else (the bar, the clock, give up, the end).
struct NineLivesPlayView: View {
    @Bindable var model: NineLivesModel

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.15
            if wide {
                // iPad landscape and the like: the quilt on the left, the keys in a 3 by 3 beside it.
                let side = min(geo.size.height - 40, geo.size.width * 0.6)
                let panel = min(340, geo.size.width - side - 76)
                HStack(spacing: 36) {
                    grid(side: side)
                    VStack(spacing: 24) {
                        notQuite
                        numberPad(columns: 3, width: panel)
                        tools(width: panel, stacked: true, size: .medium)
                    }
                    .frame(width: panel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Phones and iPad portrait: the quilt, then one row of keys, then the tools.
                let width = min(geo.size.width - (geo.size.width > 600 ? 64 : 24), 780)
                let keys = (width - 5 * 8) / 9 + 6
                let gap: CGFloat = 50
                let pill = width > 600 ? PillSize.medium : .small
                let side = max(200, min(width, geo.size.height - keys - pill.height - 6 - gap - 40))
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    grid(side: side)
                    notQuite.frame(height: gap)
                    numberPad(columns: 9, width: width)
                    Spacer(minLength: 14).frame(maxHeight: 22)
                    tools(width: width, stacked: false, size: pill)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sensoryFeedback(.success, trigger: model.isSolved) { _, solved in solved }
    }

    private func grid(side: CGFloat) -> some View {
        NineLivesGrid(board: model.board, clashes: model.clashes, marks: model.marks) { cell in
            Haptics.shared.tick()
            model.tap(cell)
        }
        .frame(width: side, height: side)
            // A container, so each cell keeps its own identifier.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nine-lives-grid")
    }

    /// "Not quite": the grid is full with a clash. It has its own room, so nothing moves when it shows.
    private var notQuite: some View {
        OutlinedText("Not quite", size: 22, fill: .white, outline: Palette.ink, width: 2.5)
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background(Capsule().fill(Palette.refuse).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
            .shake(trigger: model.notQuiteBump)
            .scaleEffect(model.notQuite ? 1 : 0.6)
            .opacity(model.notQuite ? 1 : 0)
            .animation(.spring(duration: 0.3, bounce: 0.4).paced, value: model.notQuite)
            .accessibilityHidden(!model.notQuite)
            .accessibilityIdentifier("nine-lives-not-quite")
    }

    private func numberPad(columns: Int, width: CGFloat) -> some View {
        let gap: CGFloat = columns == 9 ? 5 : 12
        let size = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: gap), count: columns), spacing: gap) {
            ForEach(1...9, id: \.self) { d in
                padKey(d, size: size)
            }
        }
        .frame(width: width)
    }

    private func padKey(_ d: Int, size: CGFloat) -> some View {
        let done = model.isDone(d)
        return Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxTick)
            model.press(d)
        } label: {
            ZStack {
                if model.notesOn {
                    // Notes: a hollow paw, so it reads as a pencil mark.
                    PawShape().fill(Palette.ink.opacity(0.5))
                        .overlay(PawShape().stroke(Palette.yellow, lineWidth: 2.5))
                        .overlay(
                            Text(verbatim: "\(d)")
                                .font(.system(size: size * 0.48, weight: .black, design: .rounded))
                                .foregroundStyle(Palette.yellow)
                                .offset(y: size * 0.13))
                        .frame(width: size, height: size)
                } else {
                    PawTile(digit: d, kind: .mine, size: size)
                }
            }
            .opacity(done ? 0.35 : 1)
            .compositingGroup()
        }
        .buttonStyle(PressDown())
        .disabled((done && !model.notesOn) || !model.live)
        .accessibilityLabel(Text(verbatim: model.notesOn ? "Note \(d)" : "\(d)"))
        .accessibilityIdentifier("nine-lives-key-\(d)")
    }

    private func tools(width: CGFloat, stacked: Bool, size: PillSize) -> some View {
        let w = stacked ? width : (width - 20) / 3
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            PillButton(
                icon: nil, color: model.notesOn ? Palette.yellow : Palette.teal, size: size, width: w,
                title: model.notesOn ? "Notes on" : "Notes", accessibilityLabel: "Notes"
            ) { model.toggleNotes() }
            .disabled(!model.live)
            .accessibilityValue(Text(model.notesOn ? "On" : "Off"))
            .accessibilityIdentifier("nine-lives-notes")
            PillButton(icon: nil, color: Palette.orange, size: size, width: w, title: "Erase", accessibilityLabel: "Erase") {
                model.erase()
            }
            .disabled(!model.live)
            .accessibilityIdentifier("nine-lives-erase")
            PillButton(icon: nil, color: Palette.magenta, size: size, width: w, title: "Hint", accessibilityLabel: "Hint") {
                Task { await model.hint() }
            }
            .disabled(model.asking || !model.live)
            .accessibilityIdentifier("nine-lives-hint")
        }
        .frame(width: width)
        // Faded as one layer when play has stopped.
        .compositingGroup()
        .opacity(model.live ? 1 : 0.45)
    }
}

/// A key that sinks a little while pressed.
private struct PressDown: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.12, bounce: 0.3).paced, value: configuration.isPressed)
    }
}
