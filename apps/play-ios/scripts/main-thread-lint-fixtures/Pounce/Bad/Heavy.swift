// expect: solver, hint-search, core-image-context
import CoreImage
import PounceKit
@MainActor func heavy(_ draft: TilesDraft) {
    _ = Solver.findPhase(hand: [], phaseIndex: 0)
    _ = TilesHints.next(draft)
    _ = CIContext()
}
