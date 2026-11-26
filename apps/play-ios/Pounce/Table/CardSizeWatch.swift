#if DEBUG
import QuartzCore
import SpriteKit

/// DEBUG: catches a card that pops to another size between two frames (JD: "in the card view the
/// cards are small instead of big sometimes just for a few frames"). Each rendered frame a table
/// hands it every face-up card on screen, keyed by the card, with its height as drawn (its node's
/// size times every scale above it): the hand, a held card, the piles' tops, the trays and every
/// card in flight. One card is often two nodes in turn (a flyer, then the pile or the hand that
/// takes it over at the snapshot), so the check follows the card, not the node. A blip is a card
/// drawn more than `jump` taller or shorter than the frame before: a node made at the wrong size,
/// a tween that started from one, or a layout that applied late. A tween at the app's own pace
/// never moves that much in a frame; frames after a hitch (over 25 ms) aren't judged. Heights
/// only, so a flip (which narrows a card) and a squash (15%) never count. The tables read `blips`
/// into their `*.sizes` probe; `log` keeps the last few, with what changed just before (`mark`).
struct CardSizeWatch {
    static let jump: CGFloat = 0.3
    private(set) var blips = 0
    /// How many card-frames were judged: a check that the watch saw anything at all.
    private(set) var judgedCards = 0
    private(set) var log: [String] = []
    private var last: [Int: (height: CGFloat, what: String)] = [:]
    private var lastTime: TimeInterval = 0
    private var marks: [String] = []
    private let start = CACurrentMediaTime()
    private var context = ""

    /// One rendered frame: each face-up card on screen (`card`: its id; the biggest copy counts
    /// when one card is drawn twice), with its drawn height and where it is.
    mutating func frame(_ cards: [(card: Int, height: CGFloat, what: String)], context: String = "") {
        self.context = context
        let now = CACurrentMediaTime()
        let judged = lastTime > 0 && now - lastTime < 0.025
        lastTime = now
        var next: [Int: (height: CGFloat, what: String)] = [:]
        for c in cards where c.height > 1 {
            if let have = next[c.card], have.height >= c.height { continue }
            next[c.card] = (c.height, c.what)
        }
        if judged {
            for (card, now) in next {
                guard let before = last[card] else { continue }
                judgedCards += 1
                let ratio = now.height / before.height
                if ratio > 1 + Self.jump || ratio < 1 / (1 + Self.jump) {
                    note("card \(card) \(Int(before.height)) pt (\(before.what)) to \(Int(now.height)) pt (\(now.what))")
                }
            }
        }
        last = next
    }

    /// Notes something that changes how cards are drawn (a layout pass, a new TV frame).
    mutating func mark(_ text: String) {
        marks = Array((marks + ["\(ms(CACurrentMediaTime() - start)) \(text)"]).suffix(3))
    }

    private func ms(_ t: TimeInterval) -> String { "\(Int(t * 1000)) ms" }

    /// The probe's value: "<blips>|<card-frames judged>|<the last few blips>".
    var probe: String { "\(blips)|\(judgedCards)|\(log.joined(separator: "; "))" }

    private mutating func note(_ text: String) {
        blips += 1
        log = Array((log + ["\(ms(CACurrentMediaTime() - start)) \(text) {\(context)} [\(marks.joined(separator: ", "))]"]).suffix(4))
    }

    /// A node's height as drawn: its `size` (which already has its own scale in it) times every
    /// scale above it, up to the scene.
    @MainActor static func height(_ node: SKSpriteNode) -> CGFloat {
        var s: CGFloat = 1
        var p = node.parent
        while let n = p, !(n is SKScene) {
            s *= abs(n.yScale)
            p = n.parent
        }
        return node.size.height * s
    }

    /// A node is on screen and shows: not hidden (nor anything above it), not faded out, and its
    /// frame meets the scene's.
    @MainActor static func shows(_ node: SKNode, in scene: SKScene) -> Bool {
        var n: SKNode? = node
        var alpha: CGFloat = 1
        while let m = n, !(m is SKScene) {
            if m.isHidden { return false }
            alpha *= m.alpha
            n = m.parent
        }
        guard alpha > 0.05, let parent = node.parent else { return false }
        let f = node.frame
        let a = scene.convert(CGPoint(x: f.minX, y: f.minY), from: parent)
        let b = scene.convert(CGPoint(x: f.maxX, y: f.maxY), from: parent)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            .intersects(CGRect(origin: .zero, size: scene.size))
    }
}
#endif
