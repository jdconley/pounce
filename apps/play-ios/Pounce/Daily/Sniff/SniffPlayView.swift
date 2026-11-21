import PounceKit
import SwiftUI

/// Who answers a guess with its marks: the server, through the Dish's run session (phase B), or
/// the DEBUG demo. Nil means the guess wasn't taken (too soon, a dropped connection): the row
/// stays typed to send again.
protocol SniffReferee: Sendable {
    func guess(_ word: String) async -> SniffReveal?
}

/// Sniff's play state on the main actor: the board, the allowed list once it has loaded off the
/// main actor, and the shake and note for an unknown word.
@MainActor @Observable
final class SniffPlayModel {
    private(set) var board: SniffBoard
    private(set) var words: SniffWords?
    /// Bumped for each refused row, to shake it.
    private(set) var shake = 0
    /// A word under the trail for a moment: "Not a word".
    private(set) var note: String?
    /// False once the run has ended (the host shows the end): no more input.
    private(set) var playing = true
    private let referee: any SniffReferee

    init(board: SniffBoard = SniffBoard(), referee: any SniffReferee) {
        self.board = board
        self.referee = referee
    }

    /// Reads the allowed list through the IO layer. Until it's in, Sniff can't send.
    func load() async {
        guard words == nil else { return }
        words = await SniffWords.load()
    }

    func type(_ letter: Character) {
        guard playing else { return }
        note = nil
        board.type(letter)
    }

    func delete() {
        guard playing else { return }
        note = nil
        board.delete()
    }

    func send() {
        guard playing, let words else { return }
        switch board.submit(words: words) {
        case .send(let word):
            Sound.shared.play(ArtName.Sound.sfxWhoosh)
            Task { await answer(word) }
        case .unknown:
            refuse(String(localized: "Not a word"))
        case .short:
            refuse(String(localized: "Five letters"))
        case .busy, .over:
            break
        }
    }

    func clearNote() { note = nil }

    /// The server's board replaces this one (it refused something): anything typed since is dropped.
    func resync(_ board: SniffBoard) {
        self.board = board
        note = nil
    }

    /// The run ended: the host takes over.
    func stop() {
        playing = false
        note = nil
    }

    private func refuse(_ words: String) {
        shake += 1
        note = words
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope)
        AccessibilityNotification.Announcement(words).post()
    }

    private func answer(_ word: String) async {
        guard let reveal = await referee.guess(word) else {
            board.refused()
            return
        }
        board.reveal(reveal.guess, answer: reveal.answer)
        if reveal.guess.isSolved {
            Haptics.shared.celebrate()
            Sound.shared.play(ArtName.Sound.sfxFanfare)
        } else {
            Haptics.shared.drop()
            Sound.shared.play(ArtName.Sound.sfxFlip)
        }
    }
}

/// Sniff's board and controls inside the Dish's puzzle screen (the host draws the top bar, the
/// clock and the end). Six trails of scent tags over Sniff's own keyboard; a hardware keyboard
/// types too.
struct SniffPlayView: View {
    @State var model: SniffPlayModel
    @FocusState private var focused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { geo in
            // A wide screen (an iPad on its side) puts the keyboard beside the trail, so the tags
            // keep the whole height; anything else stacks them.
            if geo.size.width > geo.size.height * 1.2 && geo.size.width >= 900 {
                wide(geo.size)
            } else {
                tall(geo.size)
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            if press.key == .return { model.send(); return .handled }
            if press.key == .delete { model.delete(); return .handled }
            guard let c = press.characters.first, press.characters.count == 1, c.isASCII, c.isLetter else { return .ignored }
            model.type(c)
            return .handled
        }
        .task { await model.load() }
        .onAppear { focused = true }
    }

    private static let margin: CGFloat = 16
    private static let noteHeight: CGFloat = 30

    private var showsAnswer: Bool { model.board.answer != nil && !model.board.isSolved }

    private func tag(fitting size: CGSize) -> CGFloat {
        SniffTrail.tagWidth(fitting: size, rows: SniffBoard.tries + (showsAnswer ? 1 : 0), cap: sizeClass == .regular ? 96 : 72)
    }

    private func keyboard(width: CGFloat) -> some View {
        SniffKeyboard(
            marks: model.board.keyboard, width: width,
            enabled: model.playing && model.board.pending == nil,
            canSend: model.words != nil && model.board.draft.count == SniffBoard.letters,
            onLetter: model.type, onDelete: model.delete, onSend: model.send)
    }

    /// The trail over the keyboard.
    private func tall(_ size: CGSize) -> some View {
        let keysWidth = min(size.width - 2 * Self.margin, 640)
        let keysHeight = model.board.isOver ? 0 : SniffKeyboard.height(width: keysWidth)
        let trail = CGSize(
            width: min(size.width - 2 * Self.margin, 560),
            height: max(0, size.height - keysHeight - Self.noteHeight - 24))
        return VStack(spacing: 8) {
            Spacer(minLength: 0)
            SniffTrail(board: model.board, tagWidth: tag(fitting: trail), shake: model.shake)
            Spacer(minLength: 0)
            note.frame(height: Self.noteHeight)
            if !model.board.isOver {
                keyboard(width: keysWidth).padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The trail on the left at full height; the note and the keyboard beside it.
    private func wide(_ size: CGSize) -> some View {
        let keysWidth = model.board.isOver ? 0 : min(size.width * 0.46, 600)
        let trail = CGSize(
            width: size.width - keysWidth - 3 * Self.margin,
            height: size.height - 2 * Self.margin)
        return HStack(spacing: Self.margin) {
            SniffTrail(board: model.board, tagWidth: tag(fitting: trail), shake: model.shake)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !model.board.isOver {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    note.frame(height: Self.noteHeight)
                    keyboard(width: keysWidth)
                    Spacer(minLength: 0)
                }
                .frame(width: keysWidth)
            }
        }
        .padding(.horizontal, Self.margin)
    }

    @ViewBuilder private var note: some View {
        if let note = model.note {
            Text(note)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(Palette.yellow))
                .overlay(Capsule().stroke(Palette.ink, lineWidth: 2.5))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityIdentifier("sniff.note")
                .transition(.scale.combined(with: .opacity))
                .task(id: model.shake) {
                    try? await Task.sleep(for: Pace.duration(.milliseconds(1400)))
                    withAnimation { model.clearNote() }
                }
        }
    }
}
