#if DEBUG
import PounceKit
import SpriteKit

/// DEBUG `-tumble-autoplay`: this phone's box plays itself through the same calls a finger
/// makes (turn, move, drop), one input every few frames, and uses each trick it pockets, so the
/// frame gate and the screenshots see a live game. `TumblePlanner` picks the spot.
@MainActor
final class TumbleAutoplay {
    static let enabled = CommandLine.arguments.contains("-tumble-autoplay")

    private weak var scene: TumbleScene?
    private var plan: (r: Int, n: Int, spot: TumbleSpot)?
    private var lastInput: Double = 0
    /// Ms between inputs: a quick player.
    static let pace: Double = 90

    static func start(_ scene: TumbleScene) -> TumbleAutoplay? {
        guard enabled, !scene.isScreen else { return nil }
        let play = TumbleAutoplay()
        play.scene = scene
        return play
    }

    func tick(_ now: Double) {
        guard let scene, let local = scene.table.local, let toy = local.toy, now - lastInput >= Self.pace / max(Pace.factor, 1) else { return }
        lastInput = now
        if !local.box.held.isEmpty, let target = target(scene, local) {
            scene.use(0, on: target)
            return
        }
        if plan?.n != toy.n || plan?.r != local.r { plan = TumblePlanner.best(local).map { (local.r, toy.n, $0) } }
        guard let spot = plan?.spot else { return }
        switch TumblePlanner.next(local, toward: spot) {
        case .turn: local.turn(1)
        case .move(let dx): local.move(dx)
        case .drop: local.drop(now)
        case nil: break
        }
    }

    /// Harmful tricks on the first opponent still in, helpful ones on this box.
    private func target(_ scene: TumbleScene, _ local: TumbleLocal) -> Int? {
        let trick = local.box.held[0]
        if TumbleScene.selfTarget(trick) { return local.seat }
        return scene.shown.first { $0 != local.seat && !scene.table.isOut($0) }
    }
}
#endif
