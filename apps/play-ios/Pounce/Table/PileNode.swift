import PounceKit
import SpriteKit

/// The draw pile (backs, height implied by the count) or the discard pile (top card face up).
@MainActor
final class PileNode: SKNode {
    enum Kind { case deck, discard }

    let kind: Kind
    private var layers: [SKSpriteNode] = []
    private let empty: SKSpriteNode
    /// Legal-target highlight: a pre-rendered glow, a sparkle and a little growth (spec §13:
    /// brightness and sparkle, not hue alone).
    private let glow: SKSpriteNode
    private let sparkle: SKSpriteNode
    private(set) var highlighted = false
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
        glow = SKSpriteNode(texture: TableArt.cards(ArtName.cardGlow))
        sparkle = SKSpriteNode(texture: TableArt.texture(ArtName.fxSparkle, atlas: ArtName.Atlas.fx))
        super.init()
        empty.alpha = 0.35  // fade-ok: the empty pile's outline, alone
        empty.zPosition = 0
        addChild(empty)
        glow.zPosition = 0.05
        glow.isHidden = true
        addChild(glow)
        sparkle.zPosition = 3
        sparkle.isHidden = true
        addChild(sparkle)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Draws the pile. When its card size changes (Cards and Table size the piles differently),
    /// the top card keeps the size it was drawn at and the tween to the new one is returned, for
    /// the scene's director: it never pops to the new size in one frame.
    @discardableResult
    func update(count: Int, top topCard: CardID?, cardSize: CGSize) -> [(SKAction, SKNode)] {
        let showsTop = kind == .deck ? count > 0 : topCard != nil
        let under = count <= 1 ? 0 : min(Self.maxLayers, (count - 1 + Self.cardsPerLayer - 1) / Self.cardsPerLayer)
        // The top's height as drawn now (an SKSpriteNode's `size` has its scale in it).
        let was = self.cardSize.height > 0 ? top?.size.height : nil
        if cardSize != self.cardSize {
            self.cardSize = cardSize
            empty.size = CGSize(width: cardSize.width * 1.1, height: cardSize.height * 1.1)
            layers.forEach { $0.size = cardSize }
            top?.size = cardSize
            let g = CardNode.glowSize(for: cardSize)
            glow.size = CGSize(width: g.width * 1.1, height: g.height * 1.08)
            sparkle.size = CGSize(width: cardSize.width * 0.5, height: cardSize.width * 0.5)
            sparkle.position = CGPoint(x: cardSize.width * 0.42, y: cardSize.height * 0.42)
        }
        self.count = count
        empty.isHidden = showsTop

        // Under-cards: backs on the deck, blank faces (edges only show) under the discard.
        while layers.count > under { layers.removeLast().removeFromParent() }
        while layers.count < under {
            let texture = kind == .deck ? CardFaceFactory.shared.back() : CardFaceFactory.shared.blank()
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
            top?.size = cardSize
            top?.alpha = 1
            top?.zPosition = 1
            if let top, let was, cardSize.height > 0, abs(was / cardSize.height - 1) > 0.02 {
                top.setScale(was / cardSize.height)
                return [(SKAction.scale(to: 1, duration: HandNode.resizeDuration).eased(.easeOut), top)]
            }
        } else {
            top?.removeFromParent()
            top = nil
        }
        return []
    }

    /// Glow, sparkle and grow while this pile is a legal draw or drop.
    func setHighlighted(_ on: Bool) {
        highlighted = on
        glow.isHidden = !on
        sparkle.isHidden = !on
        setScale(on ? 1.06 : 1)
    }

    /// Turn start: the glow flares up and settles twice (the reconcile that follows decides
    /// whether it stays lit).
    func flare() -> (SKAction, SKNode) {
        // fade-ok: the glow sits alone under the pile's cards
        (.sequence([
            .unhide(), .fadeAlpha(to: 0.2, duration: 0),
            .fadeAlpha(to: 1, duration: 0.15), .fadeAlpha(to: 0.45, duration: 0.18), .fadeAlpha(to: 1, duration: 0.18),
            .fadeAlpha(to: 0.55, duration: 0.18), .fadeAlpha(to: 1, duration: 0.18),
        ]), glow)
    }

    /// Touch / accessibility frame in the parent's space.
    var hitFrame: CGRect {
        let w = max(cardSize.width, 44), h = max(cardSize.height, 44)
        return CGRect(x: position.x - w / 2, y: position.y - h / 2, width: w, height: h)
    }
}
