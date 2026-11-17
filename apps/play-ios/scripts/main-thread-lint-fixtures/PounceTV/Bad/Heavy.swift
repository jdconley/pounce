// expect: solver, hint-search, keychain, thread-sleep
import Foundation
import PounceKit
// The Apple TV app is app UI too: heavy compute and IO are banned there as in Pounce/.
@MainActor func heavyOnTheTV(_ draft: TilesDraft) {
    _ = Solver.findPhase(hand: [], phaseIndex: 0)
    _ = TilesHints.next(draft)
    _ = SecItemCopyMatching([:] as CFDictionary, nil)
    Thread.sleep(forTimeInterval: 1)
}
