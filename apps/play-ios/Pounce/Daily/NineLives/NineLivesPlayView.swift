import PounceKit
import SwiftUI

/// Nine Lives being played: the quilt, the status line, the number row, and Notes, Erase and
/// Hint. The Daily Dish host draws everything else (the bar, the clock, give up, the end).
///
/// The status line sits between the quilt and the keys, where the eye already is while playing:
/// under the lives rules it holds the three cat heads, and "Out of lives" when the last goes; under
/// the first rules it holds "Not quite". Hints left ride on the Hint button.
struct NineLivesPlayView: View {
    @Bindable var model: NineLivesModel
    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.15
            if wide {
                // iPad landscape and the like: the quilt on the left; the status, the keys in a 3
                // by 3 and the tools beside it.
                let side = min(geo.size.height - 40, geo.size.width * 0.6)
                let panel = min(340, geo.size.width - side - 76)
                HStack(spacing: 36) {
                    grid(side: side)
                    VStack(spacing: 24) {
                        status(height: 80, heads: 60, words: 28)
                        numberPad(columns: 3, width: panel)
                        tools(width: panel, stacked: true, size: .medium)
                    }
                    .frame(width: panel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Phones and iPad portrait: the quilt, the status line, one row of keys, the tools.
                let width = min(geo.size.width - (geo.size.width > 600 ? 64 : 24), 780)
                let keys = (width - 5 * 8) / 9 + 6
                let roomy = width > 600
                let gap: CGFloat = roomy ? 70 : 50
                let pill = roomy ? PillSize.medium : .small
                let side = max(200, min(width, geo.size.height - keys - pill.height - 6 - gap - 40))
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    grid(side: side)
                    status(height: gap, heads: roomy ? 48 : 34, words: roomy ? 28 : 22)
                    numberPad(columns: 9, width: width)
                    Spacer(minLength: 14).frame(maxHeight: 22)
                    tools(width: width, stacked: false, size: pill)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sensoryFeedback(.success, trigger: model.isSolved) { _, solved in solved }
        .onChange(of: model.livesLostBump) { _, _ in
            Haptics.shared.nope()
            Sound.shared.play(ArtName.Sound.sfxNope)
            app?.tips.note(.lifeLost)
        }
        .onChange(of: model.hintsLeft) { before, after in
            if after < before { app?.tips.note(.hintUsed) }
        }
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

    /// The line between the quilt and the keys. It has its own room, so nothing moves when it
    /// changes.
    @ViewBuilder private func status(height: CGFloat, heads: CGFloat, words: CGFloat) -> some View {
        ZStack {
            if model.lives {
                LivesRow(left: model.livesLeft, size: heads)
                    .scaleEffect(model.outOfLives ? 0.6 : 1)
                    .opacity(model.outOfLives ? 0 : 1)
                    .animation(.spring(duration: 0.35, bounce: 0.5).paced, value: model.livesLeft)
                    .shake(trigger: model.livesLostBump)
                    .tipTarget("nine-lives-lives")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Lives", comment: "VoiceOver: Nine Lives' lives left"))
                    .accessibilityValue(Text("\(model.livesLeft) of \(NineLivesRules.lifeCount)", comment: "VoiceOver: lives left, e.g. 2 of 3"))
                    .accessibilityHidden(model.outOfLives)
                    .accessibilityIdentifier("nine-lives-lives")
                banner(String(localized: "Out of lives", comment: "Nine Lives: the third wrong number ended the run"), color: Palette.violet, size: words, shown: model.outOfLives, bump: 0)
                    .accessibilityIdentifier("nine-lives-out")
            } else {
                banner(String(localized: "Not quite", comment: "Nine Lives (first rules): the grid is full but something is wrong"), color: Palette.refuse, size: words, shown: model.notQuite, bump: model.notQuiteBump)
                    .accessibilityIdentifier("nine-lives-not-quite")
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.4, bounce: 0.35).paced, value: model.outOfLives)
    }

    private func banner(_ text: String, color: Color, size: CGFloat, shown: Bool, bump: Int) -> some View {
        OutlinedText(text, size: size, fill: .white, outline: Palette.ink, width: 2.5)
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background(Capsule().fill(color).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
            .compositingGroup()
            .shake(trigger: bump)
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .animation(.spring(duration: 0.3, bounce: 0.4).paced, value: shown)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityHidden(!shown)
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
        // Faded as one layer when play has stopped.
        .compositingGroup()
        .opacity(model.live ? 1 : 0.45)
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
            hintButton(width: w, size: size)
        }
        .frame(width: width)
        // Faded as one layer when play has stopped.
        .compositingGroup()
        .opacity(model.live ? 1 : 0.45)
    }

    /// Hint, with the hints left on a badge (lives rules). With none left it is spent: faded, and
    /// it takes no taps.
    private func hintButton(width: CGFloat, size: PillSize) -> some View {
        let spent = model.lives && model.hintsLeft == 0
        let badge = size.height * 0.56
        return PillButton(icon: nil, color: Palette.magenta, size: size, width: width, title: "Hint", accessibilityLabel: "Hint") {
            Task { await model.hint() }
        }
        .disabled(!model.canHint)
        .accessibilityValue(
            model.lives ? Text("\(model.hintsLeft) left", comment: "VoiceOver: Nine Lives' hints left, e.g. 2 left") : Text(verbatim: ""))
        .accessibilityIdentifier("nine-lives-hint")
        .compositingGroup()
        .opacity(spent && model.live ? 0.4 : 1)
        .overlay(alignment: .topTrailing) {
            if model.lives {
                Text(verbatim: "\(model.hintsLeft)")
                    .font(.system(size: badge * 0.62, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(spent ? .white : Palette.ink)
                    .frame(width: badge, height: badge)
                    .background(Circle().fill(spent ? Palette.ink.mix(with: .white, by: 0.3) : Palette.yellow))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
                    .compositingGroup()
                    .offset(x: badge * 0.28, y: -badge * 0.34)
                    .pop(trigger: model.hintsLeft)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .tipTarget("nine-lives-hint")
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
