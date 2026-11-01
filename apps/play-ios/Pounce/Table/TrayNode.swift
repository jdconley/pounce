import PounceKit
import SpriteKit

/// The phase goal above the hand, drawn as one tray per requirement in the server's phase
/// order: the group size as a big numeral and a tiny card fan that shows the kind (same
/// number, in a row, one coat). Before laying down these are also the lay-down trays.
@MainActor
final class TrayNode: SKNode {
    private(set) var requirements: [Requirement] = []
    private(set) var frames: [CGRect] = []
    private var trays: [SKSpriteNode] = []
    private var builtFor: (reqs: [Requirement], frame: CGRect)?
    /// The big paw that sends the lay-down (Task 16 shows it when every tray is valid).
    let layDownButton: SKSpriteNode

    private static let trayArt = CGSize(width: 120, height: 64)

    override init() {
        layDownButton = SKSpriteNode(texture: TableArt.image(ArtName.iconPawMenu), size: CGSize(width: 56, height: 56))
        super.init()
        layDownButton.isHidden = true
        layDownButton.zPosition = 5
        addChild(layDownButton)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(requirements reqs: [Requirement], layout: TableLayout) {
        let frame = layout.traysFrame
        if let built = builtFor, built.reqs == reqs, built.frame == frame { return }
        builtFor = (reqs, frame)
        requirements = reqs
        trays.forEach { $0.removeFromParent() }
        trays.removeAll()
        frames = layout.trayFrames(count: reqs.count)
        for (i, req) in reqs.enumerated() {
            let f = frames[i]
            let tray = SKSpriteNode(texture: TableArt.table(ArtName.tray), size: Self.trayArt)
            tray.centerRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
            tray.xScale = f.width / Self.trayArt.width
            tray.yScale = f.height / Self.trayArt.height
            tray.position = CGPoint(x: f.midX, y: f.midY)
            tray.zPosition = 0
            addChild(tray)
            trays.append(tray)
            addPictogram(req, in: f)
        }
        layDownButton.position = CGPoint(x: frame.maxX - 30, y: frame.maxY + 34)
    }

    /// Spoken tray name: "Tray 1, set of 3".
    static func label(_ req: Requirement, index: Int) -> String {
        let kind: String
        switch req.kind {
        case .set: kind = String(localized: "set of \(req.size)", comment: "VoiceOver: tray goal, same number")
        case .run: kind = String(localized: "run of \(req.size)", comment: "VoiceOver: tray goal, in a row")
        case .coat: kind = String(localized: "\(req.size) of one coat", comment: "VoiceOver: tray goal, one coat")
        }
        return String(localized: "Tray \(index + 1), \(kind)", comment: "VoiceOver: a lay-down tray")
    }

    /// Example cards for a requirement: a set is one value in many coats, a run counts up,
    /// a coat group is one coat with mixed values.
    private static func example(_ req: Requirement) -> [CardID] {
        let coats = Coat.allCases
        func id(_ value: Int, _ coat: Coat) -> CardID { coats.firstIndex(of: coat)! * 24 + value - 1 }
        return (0..<req.size).map { i in
            switch req.kind {
            case .set: id(7, coats[i % coats.count])
            case .run: id(min(3 + i, 12), coats[i % coats.count])
            case .coat: id([2, 5, 9, 4, 11, 7, 1, 12, 6][i % 9], .tabby)
            }
        }
    }

    private func addPictogram(_ req: Requirement, in f: CGRect) {
        let digits = CardFaceFactory.shared.numeral(String(req.size), size: 30, outline: 3)
        let number = SKSpriteNode(texture: digits, size: digits.size())
        number.position = CGPoint(x: f.minX + 10 + digits.size().width / 2, y: f.midY)
        number.zPosition = 1
        addChild(number)
        trays.append(number)

        let cardH = f.height - 18
        let card = CGSize(width: (cardH * 64 / 90).rounded(), height: cardH)
        let left = number.frame.maxX + 6
        let avail = f.maxX - 10 - left
        let ids = Self.example(req)
        let step = ids.count > 1 ? min(card.width * 0.7, (avail - card.width) / CGFloat(ids.count - 1)) : 0
        let span = CGFloat(ids.count - 1) * step + card.width
        var x = left + max(0, (avail - span) / 2) + card.width / 2
        for (j, id) in ids.enumerated() {
            let n = CardNode(card: id, size: card, shadow: false)
            n.position = CGPoint(x: x, y: f.midY)
            n.zPosition = 1 + CGFloat(j) * 0.01
            n.alpha = 0.9
            addChild(n)
            trays.append(n)
            x += step
        }
    }
}
