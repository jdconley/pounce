#if DEBUG
import Foundation

/// DEBUG autoplay's brain (`-tumble-autoplay`, the frame gates): where to put the toy in hand,
/// and the one next input that gets it there. It drives the box through the same calls a finger
/// does (move, turn, drop), one per call, so the scene's own input path runs.
public enum TumblePlanner {
    public enum Input: Equatable, Sendable {
        case move(Int), turn, drop
    }

    /// The best spot for the toy in hand (fewest holes, lowest, most rows cleared).
    public static func best(_ local: TumbleLocal) -> TumbleSpot? {
        guard let toy = local.toy else { return nil }
        var queue = local.queue
        var best: (TumbleSpot, Double)?
        for rot in 0..<4 {
            for x in -3..<12 {
                guard let y = Tumble.restingY(local.box, toy: toy.toy, rot: rot, x: x, from: toy.spot.y) else { continue }
                guard case .success(let r) = Tumble.setDown(local.box, queue: &queue, n: toy.n, rot: rot, x: x, y: y, landed: []) else { continue }
                let score = TumbleDemoRoom.score(r.box) - Double(r.cleared) * 6
                if best == nil || score < best!.1 { best = (TumbleSpot(rot: rot, x: x, y: y), score) }
            }
        }
        return best?.0
    }

    /// The next input toward `target`: turn first, then slide, then drop.
    public static func next(_ local: TumbleLocal, toward target: TumbleSpot) -> Input? {
        guard let toy = local.toy else { return nil }
        if toy.spot.rot != target.rot { return .turn }
        if toy.spot.x != target.x { return .move(toy.spot.x < target.x ? 1 : -1) }
        return .drop
    }
}
#endif
