import PounceKit
import SpriteKit

extension TilesScene {
    /// Draws the textures the action strip, the sets and the loupe may need next, about one a
    /// frame while the table is up (`docs/main-thread.md`): each is drawing, and fits in a
    /// frame, but a move that changes the strip (Draw to Play, Undo lighting up) or a set's state
    /// would otherwise draw several of them in that one frame. Again whenever the strip's size
    /// changes.
    func warmTextures(layout: TilesLayout) {
        let size = layout.turn.size
        guard size.width > 0, warmedFor != size else { return }
        warmedFor = size
        let factory = TilePieceFactory.shared
        let drawn: CGFloat = layout.arrangement == .phone ? 40 : 50
        var jobs: [@MainActor () -> Void] = []
        for dim in [false, true] {
            jobs.append { _ = factory.button(.undo, side: drawn, dim: dim) }
            jobs.append { _ = factory.button(.reset, side: drawn, dim: dim) }
        }
        for on in [false, true] {
            jobs.append { _ = factory.button(.sortNumber, side: drawn, on: on) }
            jobs.append { _ = factory.button(suit: .fish, side: drawn, on: on) }
            for dim in [false, true] { jobs.append { _ = factory.button(.hint, side: drawn, on: on, dim: dim) } }
        }
        for pill in [TilePieceFactory.Pill.draw, .pass, .play, .blocked] {
            for pressed in [false, true] { jobs.append { _ = factory.pill(pill, size: size, pressed: pressed) } }
        }
        let labelSize = (size.height * 0.46).rounded()
        let words: [String] = [TilesDraft.TurnButton.draw, .pass, .play].map { Self.turnText($0, sending: false) }
            + [Self.turnText(nil, sending: true), Self.turnText(nil, sending: false)]
        for word in words { jobs.append { _ = factory.label(word, size: labelSize, outline: 2.5) } }
        // The loupe (an open set): its panel, handle and close button.
        jobs.append { _ = factory.panel() }
        jobs.append { _ = factory.button(.close, side: 36) }
        for on in [false, true] { jobs.append { _ = factory.button(.handle, side: 36, on: on) } }
        for plate in TilePieceFactory.Plate.allCases { jobs.append { _ = factory.plate(plate) } }
        let badges: [TilePieceFactory.Badge] = [.check, .locked, .placed, .problem(.tooShort), .problem(.mixedSuits), .problem(.suitTwice), .problem(.gap)]
        for badge in badges { jobs.append { _ = factory.badge(badge) } }
        warmup?.cancel()
        warmup = Task {
            for job in jobs {
                // One a frame or so: each is a millisecond or two of drawing.
                try? await Task.sleep(for: .milliseconds(17))
                guard !Task.isCancelled else { return }
                job()
            }
        }
    }
}
