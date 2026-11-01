import PounceKit
import SpriteKit

/// The draw pile (backs, height implied by the count) or the discard pile (top card face up).
@MainActor
final class PileNode: SKNode {
    enum Kind { case deck, discard }

    let kind: Kind
    private var layers: [SKSpriteNode] = []
    private let empty: SKSpriteNode
    private(set) var top: CardNode?
    private(set) var count = -1
    private var cardSize: CGSize = .zero

    /// Each card under the top one, up to this many, adds a sliver of stack.
    private static let maxLayers = 4
    private static let cardsPerLayer = 10
    private static let layerStep: CGFloat = 2.5

    init(kind: Kind) {
        self.kind = kind
        empty = SKSpriteNode(texture: TableArt.cards(ArtName.cardShadow))
        super.init()
        empty.alpha = 0.35
        empty.zPosition = 0
        addChild(empty)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(count: Int, top topCard: CardID?, cardSize: CGSize) {
        let showsTop = kind == .deck ? count > 0 : topCard != nil
        let under = count <= 1 ? 0 : min(Self.maxLayers, (count - 1 + Self.cardsPerLayer - 1) / Self.cardsPerLayer)
        if cardSize != self.cardSize {
            self.cardSize = cardSize
            empty.size = CGSize(width: cardSize.width * 1.1, height: cardSize.height * 1.1)
            layers.forEach { $0.size = cardSize }
            top?.size = cardSize
        }
        self.count = count
        empty.isHidden = showsTop

        // Under-cards: backs on the deck, blank faces (edges only show) under the discard.
        while layers.count > under { layers.removeLast().removeFromParent() }
        while layers.count < under {
            let texture = kind == .deck ? CardFaceFactory.shared.back() : TableArt.cards(ArtName.cardFace)
            let n = SKSpriteNode(texture: texture, size: cardSize)
            addChild(n)
            layers.append(n)
        }
        for (i, n) in layers.enumerated() {
            // Lowest layer first, each a little lower and further back.
            let depth = CGFloat(under - i)
            n.position = CGPoint(x: 0, y: -depth * Self.layerStep)
            n.zPosition = 0.1 + CGFloat(i) * 0.1
        }

        let face: CardID? = kind == .deck ? nil : topCard
        if showsTop {
            if let top {
                top.setCard(face)
            } else {
                let n = CardNode(card: face, size: cardSize)
                addChild(n)
                top = n
            }
            top?.position = .zero
            top?.setScale(1)
            top?.alpha = 1
            top?.zPosition = 1
        } else {
            top?.removeFromParent()
            top = nil
        }
    }

    /// Touch / accessibility frame in the parent's space.
    var hitFrame: CGRect {
        let w = max(cardSize.width, 44), h = max(cardSize.height, 44)
        return CGRect(x: position.x - w / 2, y: position.y - h / 2, width: w, height: h)
    }
}
