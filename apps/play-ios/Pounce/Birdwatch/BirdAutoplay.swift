#if DEBUG
import PounceKit
import SpriteKit

/// DEBUG `-bird-autoplay`: this phone's seat plays itself, through the same calls a tap makes:
/// it bids the least (or passes once there is a bid), puts back the first cards that score
/// nothing, names the hint suit, calls the first card offered and plays the first playable card
/// (a tap to lift it, a tap to play it). The live UI tests play whole games with it.
@MainActor
final class BirdAutoplay {
    static let enabled = CommandLine.arguments.contains("-bird-autoplay")

    private weak var scene: BirdScene?
    private var task: Task<Void, Never>?

    static func start(_ scene: BirdScene) -> BirdAutoplay? {
        guard enabled, !scene.isScreen else { return nil }
        let play = BirdAutoplay()
        play.scene = scene
        play.task = Task { [weak play] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Pace.duration(.milliseconds(500)))
                play?.step()
            }
        }
        return play
    }

    deinit { task?.cancel() }

    private func step() {
        guard let scene, scene.view != nil, let model = scene.model, let seat = scene.shownSeat,
              model.currentSeat == seat, !scene.store.actionInFlight else { return }
        let store = scene.store
        switch model.view.phase {
        case .bidding:
            if model.view.high == nil, let range = model.view.bidRange {
                store.actBirdwatch(seat: seat, .bid(range.min))
            } else {
                store.actBirdwatch(seat: seat, .pass)
            }
        case .nest:
            let hand = model.hand(seat) ?? []
            let cheap = hand.filter { BirdCard(id: $0)?.points == 0 } + hand.filter { BirdCard(id: $0)?.points != 0 }
            for card in cheap.prefix(model.view.nestSize) where !scene.putBack.contains(card) { scene.togglePutBack(card) }
            scene.sendPutBack()
        case .trump:
            store.actBirdwatch(seat: seat, .trump(model.trumpHint(seat) ?? .fish))
        case .partner:
            let rows = BirdTableModel.partnerRows(model.view.partnerChoices ?? [], trump: model.view.trump)
            if let card = rows.first?.cards.first { store.actBirdwatch(seat: seat, .partner(card)) }
        case .play:
            let playable = model.playable(seat)
            guard let card = scene.handShown.first(where: playable.contains) else { return }
            scene.tap(card, model: model, seat: seat)
            if scene.lifted == card { scene.tap(card, model: model, seat: seat) }
        case .between, .over:
            break
        }
    }
}
#endif
