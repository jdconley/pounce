import Foundation
import Testing

/// "Fade groups, not pieces" (AGENTS.md). In SpriteKit, `alpha` below 1 on a node fades every
/// child on its own, so a dimmed fan of cards shows each card through the one on top of it.
/// The table and the tile game dim groups with `FadeGroup` (`Pounce/Design/FadeGroup.swift`)
/// and darken single cards that rest on others. This reads their sources: every see-through
/// alpha (a fraction set or faded to) must say why it is fine, with a `fade-ok:` comment on
/// its line or the five before it (a `FadeGroup`, or a piece with nothing over or under it).
@Suite struct GroupFadeTests {
    /// play-ios/Pounce, walking up from this file: PounceKitTests -> Tests -> PounceKit -> play-ios.
    private static let app: URL = {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { dir.deleteLastPathComponent() }
        return dir.appendingPathComponent("Pounce")
    }()

    /// A fraction such as 0.6 or .6 (not the 0.5 of 10.5).
    private static var patterns: [Regex<AnyRegexOutput>] { [
        try! Regex(#"alpha\s*=(?!=)[^/]*[^\w.]0?\.[0-9]+"#),
        try! Regex(#"fadeAlpha\((to|by):\s*-?0?\.[0-9]+"#),
    ] }

    /// `file:line: text` for each see-through alpha in `source` without a `fade-ok:` reason.
    static func unexplained(_ source: String, file: String) -> [String] {
        let lines = source.components(separatedBy: "\n")
        var found: [String] = []
        for (i, line) in lines.enumerated() {
            let code = line.trimmingCharacters(in: .whitespaces)
            guard !code.hasPrefix("//"), !code.contains("UIColor("), !code.contains("withAlphaComponent") else { continue }
            guard patterns.contains(where: { code.contains($0) }) else { continue }
            let near = lines[max(0, i - 5)...i]
            if near.contains(where: { $0.contains("fade-ok:") }) { continue }
            found.append("\(file):\(i + 1): \(code)")
        }
        return found
    }

    @Test func everySeeThroughAlphaOnTheTablesSaysWhyItIsFine() throws {
        var found: [String] = []
        var scanned = 0
        for folder in ["Table", "Tiles"] {
            let dir = Self.app.appendingPathComponent(folder)
            for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) where name.hasSuffix(".swift") {
                let source = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
                found += Self.unexplained(source, file: "\(folder)/\(name)")
                scanned += 1
            }
        }
        #expect(scanned > 20, "the table and tile sources were found")
        #expect(found.isEmpty, "Fade the group with FadeGroup, or say why this piece may fade alone (// fade-ok: ...):\n\(found.joined(separator: "\n"))")
    }

    @Test func theCheckCatchesAFadedPieceAndAcceptsAReason() {
        let bad = """
            for card in fan { card.alpha = 0.6 }
            node.alpha = dimmed ? 0.82 : 1
            pile.run(.fadeAlpha(to: 0.4, duration: 0.2))
            """
        #expect(Self.unexplained(bad, file: "x").count == 3)
        let fine = """
            hand.alpha = dimmed ? 0.82 : 1  // fade-ok: HandNode is a FadeGroup
            // fade-ok: the glow sits alone under the pile
            glow.run(.sequence([.fadeAlpha(to: 0.45, duration: 0.2),
                .fadeAlpha(to: 1, duration: 0.2)]))
            node.alpha = 1
            node.alpha = 0
            ring.color = UIColor(white: 0.1, alpha: 0.5)
            """
        #expect(Self.unexplained(fine, file: "x").isEmpty)
    }
}
