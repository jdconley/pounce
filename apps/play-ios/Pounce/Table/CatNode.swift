import PounceKit
import SpriteKit
import SwiftUI

/// A seat's cat in its colored ring: pose sprite, an optional glow for the current player,
/// badges (bot, skip pending, laid down) and a card-count bubble. Static by default; every
/// motion goes through the `AnimationDirector`.
@MainActor
final class CatNode: SKNode {
    let cat: Int
    let diameter: CGFloat
    private let glow: SKSpriteNode
    private let ring: SKSpriteNode
    private let sprite: SKSpriteNode
    private let botBadge: SKSpriteNode
    private let skipBadge: SKSpriteNode
    private let laidBadge: SKSpriteNode
    private let bubble: SKSpriteNode
    private let bubbleNumber: SKSpriteNode
    private(set) var pose: CatPose = .idle
    private(set) var count: Int?

    init(cat: Int, ringColor: Color, diameter: CGFloat = 72) {
        self.cat = cat
        self.diameter = diameter
        let k = diameter / 72
        glow = SKSpriteNode(texture: TableArt.table(ArtName.ringGlow), size: CGSize(width: 96 * k, height: 96 * k))
        ring = SKSpriteNode(texture: TableArt.table(ArtName.ring), size: CGSize(width: diameter, height: diameter))
        sprite = SKSpriteNode(texture: TableArt.cat(cat, .idle), size: CGSize(width: diameter * 0.92, height: diameter * 0.92))
        let badge = CGSize(width: 22 * k, height: 22 * k)
        botBadge = SKSpriteNode(texture: TableArt.image(ArtName.badgeBot), size: badge)
        skipBadge = SKSpriteNode(texture: TableArt.image(ArtName.badgeSkip), size: badge)
        laidBadge = SKSpriteNode(texture: TableArt.image(ArtName.badgeLaid), size: badge)
        bubble = SKSpriteNode(texture: CardFaceFactory.shared.back(), size: CGSize(width: 20 * k, height: 28 * k))
        bubbleNumber = SKSpriteNode()
        super.init()

        glow.zPosition = 0
        glow.isHidden = true
        ring.zPosition = 1
        ring.color = UIColor(ringColor)
        ring.colorBlendFactor = 0.85
        sprite.zPosition = 2
        let r = diameter / 2
        botBadge.position = CGPoint(x: r * 0.72, y: r * 0.72)
        skipBadge.position = CGPoint(x: -r * 0.72, y: r * 0.72)
        laidBadge.position = CGPoint(x: -r * 0.72, y: -r * 0.62)
        for b in [botBadge, skipBadge, laidBadge] {
            b.zPosition = 4
            b.isHidden = true
            addChild(b)
        }
        bubble.position = CGPoint(x: r * 0.62, y: -r * 0.62)
        bubble.zPosition = 5
        bubble.isHidden = true
        bubbleNumber.zPosition = 1
        bubble.addChild(bubbleNumber)
        [glow, ring, sprite, bubble].forEach(addChild)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func setPose(_ pose: CatPose) {
        guard pose != self.pose else { return }
        self.pose = pose
        sprite.texture = TableArt.cat(cat, pose)
    }

    func setBadges(bot: Bool, skip: Bool, laid: Bool) {
        botBadge.isHidden = !bot
        skipBadge.isHidden = !skip
        laidBadge.isHidden = !laid
    }

    /// Awake = alert, away = curled up, asleep = Zzz; nil (a bot) = idle.
    func setPresence(_ p: Presence?) {
        switch p {
        case .awake: setPose(.awake)
        case .away: setPose(.away)
        case .asleep: setPose(.asleep)
        case nil: setPose(.idle)
        }
    }

    /// The current player's ring glows (a still sprite: the table never loops an animation).
    func setActive(_ on: Bool) {
        glow.isHidden = !on
    }

    var isActive: Bool { !glow.isHidden }

    /// Card-count bubble; nil hides it.
    func setCount(_ count: Int?) {
        guard count != self.count else { return }
        self.count = count
        guard let count else {
            bubble.isHidden = true
            return
        }
        bubble.isHidden = false
        let t = CardFaceFactory.shared.numeral(String(count), size: 15 * diameter / 72)
        bubbleNumber.texture = t
        bubbleNumber.size = t.size()
    }
}
