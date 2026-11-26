import PounceKit
import SpriteKit

/// Birdwatch's touches (design §5.2): tap a card to lift it and tap it again to play it, or drag
/// it onto the sill. While the bid winner puts cards back, a tap marks or unmarks a card. A card
/// the server's `playable` leaves out wiggles and plays nothing. The paw opens the menu and the
/// score strip opens the score sheet. A TV takes no touches.
extension BirdScene {
    #if os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        pressBegan(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        pressMoved(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        pressEnded(at: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        press = nil
        redraw()
    }
    #endif

    /// The hand card under `point`, topmost first.
    func card(at point: CGPoint) -> BirdCardID? {
        handShown.reversed().first { card in
            guard let node = handNodes[card], !node.isHidden else { return false }
            return node.frame.insetBy(dx: -2, dy: -2).contains(point)
        }
    }

    func pressBegan(at point: CGPoint) {
        guard !isScreen else { return }
        if !menuButton.isHidden, menuButton.frame.insetBy(dx: -12, dy: -12).contains(point) {
            press = Press(start: point, onMenu: true)
            return
        }
        if stripFrames.contains(where: { $0.contains(point) }) {
            press = Press(start: point, onStrip: true)
            return
        }
        press = Press(card: card(at: point), start: point)
    }

    func pressMoved(to point: CGPoint) {
        guard var press, let card = press.card, let node = handNodes[card], let model, let seat = shownSeat else { return }
        // Only a playable card on this seat's move can be dragged.
        guard model.view.phase == .play, model.playable(seat).contains(card) else { return }
        if !press.moved, hypot(point.x - press.start.x, point.y - press.start.y) < 8 { return }
        press.moved = true
        self.press = press
        node.removeAllActions()
        node.zPosition = Layer.drag.rawValue
        node.position = point
    }

    func pressEnded(at point: CGPoint) {
        defer { press = nil }
        guard let press else { return }
        if press.onMenu {
            if menuButton.frame.insetBy(dx: -12, dy: -12).contains(point) { onMenu() }
            return
        }
        if press.onStrip {
            if stripFrames.contains(where: { $0.contains(point) }) { onScores() }
            return
        }
        guard let card = press.card, let model, let seat = shownSeat else {
            onTableTap()
            return
        }
        if press.moved {
            if let layout, layout.sill.insetBy(dx: -20, dy: -20).contains(point) {
                play(card)
            }
            redraw()
            return
        }
        tap(card, model: model, seat: seat)
    }

    func tap(_ card: BirdCardID, model: BirdTableModel, seat: Seat) {
        switch model.view.phase {
        case .nest where model.currentSeat == seat:
            togglePutBack(card)
        case .play where model.currentSeat == seat:
            guard model.playable(seat).contains(card) else {
                nope(card, words: String(localized: "Follow suit", comment: "Birdwatch: a card refused because the hand holds the suit led"))
                return
            }
            if lifted == card {
                play(card)
            } else {
                lifted = card
                Haptics.shared.tick()
                redraw()
            }
        default:
            // Off turn a tap just lifts the card, to read it.
            lifted = lifted == card ? nil : card
            redraw()
            onTableTap()
        }
    }
}
