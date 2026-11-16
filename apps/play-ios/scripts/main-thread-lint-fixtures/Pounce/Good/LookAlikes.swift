// expect: none
import Foundation
import SpriteKit
/// Data(contentsOf:) and FileManager are named in this doc comment, Thread.sleep too.
/* A block comment with SecItemCopyMatching and /* a nested */ DispatchSemaphore. */
@MainActor func fine(_ node: SKNode, sleep: (Duration) async throws -> Void) async {
    let text = "Data(contentsOf: url) and FileManager.default in a string"
    let raw = #"Thread.sleep and "quoted" usleep(1) in a raw string"#
    let multi = """
        DispatchQueue.main.sync { } and NSLock() in a multiline string
        """
    node.run(.wait(forDuration: 0.2))
    node.run(.sequence([SKAction.wait(forDuration: 1), .wait(forDuration: 1, withRange: 0.5)]))
    try? await Task.sleep(for: .milliseconds(10))
    try? await sleep(.seconds(1))
    _ = TilesHintsLike.fits()
    _ = (text, raw, multi)
}
enum TilesHintsLike { static func fits() -> Bool { true } }
