import PounceKit
import SpriteKit

/// One card: a composited face, or the back when `card` is nil. Sized by the caller (hand,
/// pile and laid rows draw the same texture at different sizes).
@MainActor
final class CardNode: SKSpriteNode {
    private(set) var card: CardID?
    private let shadow: SKSpriteNode

    init(card: CardID?, size: CGSize = CardFaceFactory.cardSize, shadow hasShadow: Bool = true) {
        self.card = card
        shadow = SKSpriteNode(texture: TableArt.cards(ArtName.cardShadow))
        let texture = card.map { CardFaceFactory.shared.texture(for: $0) } ?? CardFaceFactory.shared.back()
        super.init(texture: texture, color: .clear, size: size)
        shadow.zPosition = -0.05  // between this card and the one under it
        shadow.isHidden = !hasShadow
        addChild(shadow)
        layoutShadow()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    override var size: CGSize {
        didSet { layoutShadow() }
    }

    /// Swaps the texture (face or back) without animating.
    func setCard(_ card: CardID?) {
        guard card != self.card else { return }
        self.card = card
        texture = card.map { CardFaceFactory.shared.texture(for: $0) } ?? CardFaceFactory.shared.back()
    }

    /// card-glow is 88x114 around a 64x90 card.
    static func glowSize(for card: CGSize) -> CGSize {
        CGSize(width: card.width * 88 / 64, height: card.height * 114 / 90)
    }

    private func layoutShadow() {
        // card-shadow is 80x106 for a 64x90 card, offset a little down-right.
        let k = size.width / CardFaceFactory.cardSize.width
        shadow.size = CGSize(width: 80 * k, height: 106 * k)
        shadow.position = CGPoint(x: 2 * k, y: -3 * k)
    }

    /// Spoken name: "7, tabby", "Yarn, wild", "Cucumber, skip"; a back is just "Card".
    static func label(_ card: CardID?) -> String {
        guard let card else { return String(localized: "Card", comment: "VoiceOver: a face-down card") }
        switch Card(id: card) {
        case .yarn:
            return String(localized: "Yarn, wild", comment: "VoiceOver: the wild card")
        case .cucumber:
            return String(localized: "Cucumber, skip", comment: "VoiceOver: the skip card")
        case .number(let value, let coat):
            return String(localized: "\(value), \(coatName(coat))", comment: "VoiceOver: a number card, value then coat")
        }
    }

    static func coatName(_ coat: Coat) -> String {
        switch coat {
        case .tabby: String(localized: "tabby", comment: "VoiceOver: coat name")
        case .tuxedo: String(localized: "tuxedo", comment: "VoiceOver: coat name")
        case .calico: String(localized: "calico", comment: "VoiceOver: coat name")
        case .gray: String(localized: "gray", comment: "VoiceOver: coat name")
        }
    }
}
