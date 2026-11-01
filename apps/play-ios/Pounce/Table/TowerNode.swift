import PounceKit
import SpriteKit

/// The cat tower down the left edge: base, 10 shelves with number badges, the top cushion,
/// and each seat's mini cat head on the shelf of its current phase.
@MainActor
final class TowerNode: SKNode {
    private let structure = SKNode()
    private let heads = SKNode()
    private var builtFor: CGRect?
    private var headNodes: [Seat: SKNode] = [:]
    private var headKeys: [Seat: Int] = [:]

    override init() {
        super.init()
        structure.zPosition = 0
        heads.zPosition = 5  // above every structure piece (layers stay inside a 10-wide z band)
        addChild(structure)
        addChild(heads)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(model: TableModel, layout: TableLayout) {
        if builtFor != layout.towerFrame { build(layout) }
        guard let game = model.game else {
            heads.removeAllChildren()
            headNodes.removeAll()
            headKeys.removeAll()
            return
        }
        let seats = Array(game.phase.indices)
        for (seat, node) in headNodes where !seats.contains(seat) {
            node.removeFromParent()
            headNodes[seat] = nil
        }
        // Seats sharing a shelf sit side by side.
        var byShelf: [Int: [Seat]] = [:]
        for seat in seats {
            byShelf[min(game.phase[seat], TableLayout.shelfCount - 1), default: []].append(seat)
        }
        let size: CGFloat = 26
        for (shelf, group) in byShelf {
            let center = layout.shelf(shelf)
            let spread = min(14, (layout.towerFrame.width - size) / CGFloat(max(group.count - 1, 1)))
            for (j, seat) in group.enumerated() {
                let cat = SeatInfo.catIndex(model.room.seats[safe: seat])
                let head: SKNode
                if let existing = headNodes[seat], headKeys[seat] == cat {
                    head = existing
                } else {
                    headNodes[seat]?.removeFromParent()
                    head = Self.makeHead(cat: cat, seat: seat, size: size)
                    headNodes[seat] = head
                    headKeys[seat] = cat
                    heads.addChild(head)
                }
                let dx = (CGFloat(j) - CGFloat(group.count - 1) / 2) * spread
                head.position = CGPoint(x: center.x + dx - 4, y: center.y + 12)
                head.zPosition = CGFloat(j) * 0.1
            }
        }
    }

    /// The head node of a seat (for leap animations later).
    func head(for seat: Seat) -> SKNode? { headNodes[seat] }

    private static func makeHead(cat: Int, seat: Seat, size: CGFloat) -> SKNode {
        let node = SKNode()
        let ring = SKSpriteNode(texture: TableArt.table(ArtName.ring), size: CGSize(width: size + 4, height: size + 4))
        ring.color = UIColor(SeatInfo.ringColor(seat))
        ring.colorBlendFactor = 0.85
        let face = SKSpriteNode(texture: TableArt.cat(cat, .idle), size: CGSize(width: size, height: size))
        face.zPosition = 1
        node.addChild(ring)
        node.addChild(face)
        return node
    }

    private func build(_ layout: TableLayout) {
        builtFor = layout.towerFrame
        structure.removeAllChildren()
        let frame = layout.towerFrame
        let w = frame.width
        let base = SKSpriteNode(texture: TableArt.table(ArtName.towerBase), size: CGSize(width: w, height: w * 34 / 44))
        base.position = CGPoint(x: frame.midX, y: frame.minY + base.size.height / 2 - 4)
        base.zPosition = 0
        structure.addChild(base)
        for i in 0..<TableLayout.shelfCount {
            let c = layout.shelf(i)
            let shelf = SKSpriteNode(texture: TableArt.table(ArtName.towerShelf), size: CGSize(width: w, height: w * 30 / 44))
            shelf.position = CGPoint(x: c.x, y: c.y - 6)
            shelf.zPosition = 0.1 + CGFloat(i) * 0.1
            structure.addChild(shelf)
            let badge = SKSpriteNode(texture: TableArt.table(ArtName.shelfBadge), size: CGSize(width: 18, height: 18))
            badge.position = CGPoint(x: frame.maxX - 4, y: c.y - 8)
            badge.zPosition = 2
            let digits = CardFaceFactory.shared.numeral(String(i + 1), size: 10, outline: 2)
            let number = SKSpriteNode(texture: digits, size: digits.size())
            number.position = CGPoint(x: 0, y: -1)
            number.zPosition = 0.01
            badge.addChild(number)
            structure.addChild(badge)
        }
        let top = SKSpriteNode(texture: TableArt.table(ArtName.towerTop), size: CGSize(width: w, height: w * 40 / 44))
        let topShelf = layout.shelf(TableLayout.shelfCount - 1)
        let step = frame.height / CGFloat(TableLayout.shelfCount)
        top.position = CGPoint(x: frame.midX, y: min(topShelf.y + step * 0.75, frame.maxY - top.size.height / 2 + 6))
        top.zPosition = 1.5
        structure.addChild(top)
    }
}
