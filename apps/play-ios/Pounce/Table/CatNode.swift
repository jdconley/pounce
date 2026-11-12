import PounceKit
import SpriteKit
import SwiftUI

/// A seat's cat in its colored ring: pose sprite, an optional glow for the current player,
/// badges (bot, skip pending), and along the bottom its two numbers: the phase on a gold "P4"
/// chip at the left (wearing the "laid down" sticker once this round's phase is down) and the
/// card count on a mini card back at the right. Static by default; every motion goes through
/// the `AnimationDirector`. Dimmed (a forfeited seat) as one layer: `FadeGroup`.
@MainActor
final class CatNode: FadeGroup {
    let cat: Int
    let diameter: CGFloat
    /// How much the card count and the level chip grow for the person's text size setting
    /// (`TableTextScale.chips`: 1 at the default, more when the bar has room).
    let textScale: CGFloat
    /// The width this cat has to itself in the top bar: its chips stay inside it.
    var slotWidth: CGFloat = .infinity {
        didSet { if slotWidth != oldValue { placeChips() } }
    }
    private let glow: SKSpriteNode
    private let ring: SKSpriteNode
    private let sprite: SKSpriteNode
    private let botBadge: SKSpriteNode
    private let skipBadge: SKSpriteNode
    /// The "laid down" sticker, on the phase chip's left end.
    private let laidBadge: SKSpriteNode
    /// The phase chip (`PhaseMark`), bottom left.
    private let phaseChip: SKSpriteNode
    private(set) var phase: PhaseMark?
    /// The seat's phone has a weak or lost connection (`SignalGlyph`).
    private let linkBadge: SKSpriteNode
    private(set) var link: SignalGlyph.Level?
    private let bubble: SKSpriteNode
    private let bubbleNumber: SKSpriteNode
    /// The current player's paw marker above the ring.
    private let paw: SKSpriteNode
    /// Cucumber aim highlight: a bigger glow, sparkles and growth (not hue alone).
    private let targetGlow: SKSpriteNode
    private let targetSparkles: [SKSpriteNode]
    private(set) var isTarget = false
    private(set) var pose: CatPose = .idle
    private(set) var count: Int?

    init(cat: Int, ringColor: Color, diameter: CGFloat = 72, textScale: CGFloat = 1) {
        self.cat = cat
        self.diameter = diameter
        self.textScale = textScale
        let k = diameter / 72
        glow = SKSpriteNode(texture: TableArt.table(ArtName.ringGlow), size: CGSize(width: 114 * k, height: 114 * k))
        ring = SKSpriteNode(texture: TableArt.table(ArtName.ring), size: CGSize(width: diameter, height: diameter))
        sprite = SKSpriteNode(texture: TableArt.cat(cat, .idle), size: CGSize(width: diameter * 0.92, height: diameter * 0.92))
        let badge = CGSize(width: 22 * k, height: 22 * k)
        botBadge = SKSpriteNode(texture: TableArt.image(ArtName.badgeBot), size: badge)
        skipBadge = SKSpriteNode(texture: TableArt.image(ArtName.badgeSkip), size: badge)
        let sticker = max(19 * k, 16)
        laidBadge = SKSpriteNode(texture: TableArt.image(ArtName.badgeLaid), size: CGSize(width: sticker, height: sticker))
        phaseChip = SKSpriteNode()
        linkBadge = SKSpriteNode(color: .clear, size: CGSize(width: 32 * k, height: 32 * k))
        // The count's mini card: never smaller than its 16 pt numeral needs, and bigger with it.
        let back = max(k, 0.8) * textScale
        bubble = SKSpriteNode(texture: CardFaceFactory.shared.back(), size: CGSize(width: 20 * back, height: 28 * back))
        bubbleNumber = SKSpriteNode()
        paw = SKSpriteNode(texture: TableArt.image(ArtName.iconPawMenu), size: CGSize(width: 26 * k, height: 26 * k))
        targetGlow = SKSpriteNode(texture: TableArt.table(ArtName.ringGlow), size: CGSize(width: 116 * k, height: 116 * k))
        let sparkle = TableArt.texture(ArtName.fxSparkle, atlas: ArtName.Atlas.fx)
        targetSparkles = [(-0.78, 0.6, 22.0), (0.82, -0.2, 16.0), (-0.5, -0.8, 14.0)].map { x, y, d in
            let n = SKSpriteNode(texture: sparkle, size: CGSize(width: d * k, height: d * k))
            n.position = CGPoint(x: x * diameter / 2, y: y * diameter / 2)
            return n
        }
        super.init(rasterize: false)
        targetGlow.zPosition = 0.5
        targetGlow.isHidden = true
        addChild(targetGlow)
        for n in targetSparkles {
            n.zPosition = 7
            n.isHidden = true
            addChild(n)
        }

        glow.zPosition = 0
        glow.isHidden = true
        // Additive, so the current player's ring reads from across the room.
        glow.blendMode = .add
        ring.zPosition = 1
        ring.color = UIColor(ringColor)
        ring.colorBlendFactor = 0.85
        sprite.zPosition = 2
        let r = diameter / 2
        botBadge.position = CGPoint(x: r * 0.72, y: r * 0.72)
        skipBadge.position = CGPoint(x: -r * 0.72, y: r * 0.72)
        for b in [botBadge, skipBadge] {
            b.zPosition = 4
            b.isHidden = true
            addChild(b)
        }
        phaseChip.zPosition = 5
        phaseChip.isHidden = true
        laidBadge.zPosition = 1
        laidBadge.isHidden = true
        phaseChip.addChild(laidBadge)
        addChild(phaseChip)
        // Where the bot badge goes (a bot has no phone), a little bigger: it's news.
        linkBadge.position = CGPoint(x: r * 0.78, y: r * 0.72)
        linkBadge.zPosition = 6.5
        linkBadge.isHidden = true
        addChild(linkBadge)
        bubble.position = CGPoint(x: r * 0.62, y: -r * 0.62)
        bubble.zPosition = 5
        bubble.isHidden = true
        bubbleNumber.zPosition = 1
        bubble.addChild(bubbleNumber)
        paw.position = CGPoint(x: 0, y: r + 2)
        paw.zPosition = 6
        paw.isHidden = true
        [glow, ring, sprite, bubble, paw].forEach(addChild)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func setPose(_ pose: CatPose) {
        guard pose != self.pose else { return }
        self.pose = pose
        sprite.texture = TableArt.cat(cat, pose)
    }

    func setBadges(bot: Bool, skip: Bool) {
        botBadge.isHidden = !bot
        skipBadge.isHidden = !skip
    }

    /// The phase chip's height: the card count's numeral size, never under 20 pt.
    var phaseChipHeight: CGFloat { (max((22 * diameter / 72).rounded(), 20) * textScale).rounded() }

    /// The phase chip (nil hides it). Returns true when the seat moved on to a later phase
    /// than the chip showed (`phasePop`); a cat's first mark never counts.
    @discardableResult func setPhase(_ mark: PhaseMark?) -> Bool {
        guard mark != phase else { return false }
        let advanced = mark?.advanced(from: phase) ?? false
        phase = mark
        guard let mark else {
            phaseChip.isHidden = true
            return false
        }
        phaseChip.isHidden = false
        let texture = CardFaceFactory.shared.phaseChip(mark, height: phaseChipHeight)
        phaseChip.texture = texture
        phaseChip.size = texture.size()
        placeChips()
        let w = phaseChip.size.width
        laidBadge.isHidden = !mark.laid
        let s = laidBadge.size.width
        // The sticker sits on the chip's top left corner, over the ring, not over the number.
        laidBadge.position = CGPoint(x: -w / 2 + s * 0.12, y: phaseChip.size.height / 2 + s * 0.12)
        return advanced
    }

    /// The chip bottom left, its left end on the ring's edge, its right end clear of the card
    /// count: a wide "10" pokes a little past the ring rather than touch the count, and in a
    /// crowded bar chip and count move right together so neither leaves this cat's own slot.
    private func placeChips() {
        let r = diameter / 2
        bubble.position.x = r * 0.62
        guard !phaseChip.isHidden else { return }
        let w = phaseChip.size.width
        let countLeft = bubble.position.x - bubble.size.width / 2
        var right = min(-r + w - 2, countLeft - 3)
        let over = (-slotWidth / 2 + 1) - (right - w)
        if over > 0 {
            right += over
            bubble.position.x = min(bubble.position.x + over, max(slotWidth / 2 - 1 - bubble.size.width / 2, bubble.position.x))
        }
        phaseChip.position = CGPoint(x: right - w / 2, y: -r * 0.7)
    }

    /// The finite pop for a seat that just moved on a phase: the chip bounces up big and back.
    /// Decorative (only the chip's scale and alpha, which reconcile never sets). Reduce Motion:
    /// a short fade in instead.
    func phasePop(reduceMotion: Bool) -> [(SKAction, SKNode)] {
        if reduceMotion {
            phaseChip.alpha = 0.2  // fade-ok: the chip alone, a 0.25 s fade in
            return [(.fadeIn(withDuration: 0.25), phaseChip)]
        }
        phaseChip.setScale(0.4)
        return [(.sequence([
            .scale(to: 1.45, duration: 0.16).eased(.easeOut),
            .scale(to: 0.92, duration: 0.1).eased(.easeInEaseOut),
            .scale(to: 1.08, duration: 0.08),
            .scale(to: 1, duration: 0.08),
        ]), phaseChip)]
    }

    /// What the bottom chips show, for the DEBUG `table.badges` probe: "P4+laid/7", "done/0".
    var badgeProbe: String {
        let p = phase.map { ($0.text ?? "done") + ($0.laid ? "+laid" : "") } ?? "-"
        return "\(p)/\(count.map(String.init) ?? "-")"
    }

    /// The weak-signal badge for a seat whose phone's connection is poor or gone; nil hides it.
    func setLink(_ level: SignalGlyph.Level?) {
        guard level != link else { return }
        link = level
        linkBadge.isHidden = level == nil
        if let level { linkBadge.texture = SignalGlyph.texture(level, side: linkBadge.size.width * 2) }
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

    /// The current player's ring glows and wears the paw marker (still sprites: the table never
    /// loops an animation; `turnPulse` pops them once). Returns true when this turned it on.
    @discardableResult func setActive(_ on: Bool) -> Bool {
        let turnedOn = on && glow.isHidden
        glow.isHidden = !on
        paw.isHidden = !on
        return turnedOn
    }

    /// The finite "your ring pulses" pop for a turn that just arrived: the paw pops in, the
    /// ring bumps three times, the glow flares and swells. Decorative: it only touches scale
    /// and alpha of children that reconcile never sets. Reduce Motion: a short fade instead.
    func turnPulse(reduceMotion: Bool) -> [(SKAction, SKNode)] {
        if reduceMotion {
            paw.alpha = 0
            return [(.fadeIn(withDuration: 0.15), paw)]
        }
        paw.setScale(0)
        let pop = SKAction.sequence([
            .scale(to: 1.25, duration: 0.14).eased(.easeOut),
            .scale(to: 1.0, duration: 0.1).eased(.easeInEaseOut),
        ])
        let bump = SKAction.sequence([
            .scale(to: 1.16, duration: 0.12), .scale(to: 1.0, duration: 0.12),
            .scale(to: 1.12, duration: 0.12), .scale(to: 1.0, duration: 0.12),
            .scale(to: 1.08, duration: 0.12), .scale(to: 1.0, duration: 0.12),
        ])
        glow.alpha = 0.4  // fade-ok: the glow sits alone behind the cat
        let flare = SKAction.group([
            .sequence([
                .fadeAlpha(to: 1, duration: 0.24), .fadeAlpha(to: 0.6, duration: 0.24),
                .fadeAlpha(to: 1, duration: 0.24), .fadeAlpha(to: 0.7, duration: 0.24), .fadeAlpha(to: 1, duration: 0.24),
            ]),
            .sequence([.scale(to: 1.25, duration: 0.3).eased(.easeOut), .scale(to: 1, duration: 0.5).eased(.easeInEaseOut)]),
        ])
        return [(pop, paw), (bump, ring), (flare, glow)]
    }

    var isActive: Bool { !glow.isHidden }

    /// Turn handoff, outgoing side: the glow and paw shrink away, then hide (reconcile agrees).
    func turnOut(reduceMotion: Bool) -> [(SKAction, SKNode)] {
        guard isActive else { return [] }
        let away: SKAction = reduceMotion
            ? .fadeOut(withDuration: 0.15)
            : .group([.scale(to: 0.4, duration: 0.18).eased(.easeIn), .fadeOut(withDuration: 0.18)])
        let reset = SKAction.sequence([away, .hide(), .scale(to: 1, duration: 0), .fadeIn(withDuration: 0)])
        return [(reset, glow), (reset, paw)]
    }

    /// Cucumber terror: the terrified pose, a leap up and back down, then the seat's pose
    /// again. Decorative (only the pose sprite's texture and offset, which reconcile never
    /// sets). Reduce Motion: the pose alone.
    func terror(reduceMotion: Bool) -> (SKAction, SKNode) {
        let scared = SKAction.setTexture(TableArt.cat(cat, .terrified))
        let move: SKAction = reduceMotion
            ? .wait(forDuration: 0.45)
            : .sequence([
                .moveBy(x: 0, y: diameter * 0.28, duration: 0.14).eased(.easeOut),
                .moveBy(x: 0, y: -diameter * 0.28, duration: 0.16).eased(.easeIn),
                Effects.squash(),
                .wait(forDuration: 0.06),
            ])
        return (.sequence([scared, move, .run { [weak self] in self?.resetMotion() }]), sprite)
    }

    /// Idle flourish: a blink (a different pose for 0.15 s) with a tiny ear-flick squash.
    func blink() -> (SKAction, SKNode) {
        let other: CatPose = pose == .awake ? .idle : .awake
        return (.sequence([
            .setTexture(TableArt.cat(cat, other)),
            .scaleX(by: 1.03, y: 0.96, duration: 0.075),
            .scaleX(by: 1 / 1.03, y: 1 / 0.96, duration: 0.075),
            .run { [weak self] in self?.resetMotion() },
        ]), sprite)
    }

    /// Where the skip badge sits, in this node's parent space.
    var skipBadgePoint: CGPoint {
        CGPoint(x: position.x + skipBadge.position.x * xScale, y: position.y + skipBadge.position.y * yScale)
    }

    var skipBadgeSize: CGSize { skipBadge.size }

    /// Hides the skip badge while a `skipped` animation pops its own copy.
    func hideSkipBadge() { skipBadge.isHidden = true }

    /// Back to the seat's pose at rest (after a terror or blink, or when the table is torn
    /// down mid-motion).
    func resetMotion() {
        sprite.texture = TableArt.cat(cat, pose)
        sprite.position = .zero
        sprite.setScale(1)
    }

    /// Glows, sparkles and grows while this seat is a legal Cucumber target. The scene sets it
    /// after each layout pass (the bar resets scale to 1).
    func setTarget(_ on: Bool) {
        isTarget = on
        targetGlow.isHidden = !on
        targetSparkles.forEach { $0.isHidden = !on }
        setScale(on ? 1.14 : 1)
    }

    /// Card-count bubble; nil hides it.
    func setCount(_ count: Int?) {
        guard count != self.count else { return }
        self.count = count
        guard let count else {
            bubble.isHidden = true
            return
        }
        bubble.isHidden = false
        // Never under an 11 pt cap height, however many cats share the bar.
        let t = CardFaceFactory.shared.numeral(String(count), size: (max(16 * diameter / 72, 16) * textScale).rounded())
        bubbleNumber.texture = t
        bubbleNumber.size = t.size()
    }
}

extension SKAction {
    /// The same action with a timing mode, for chaining.
    func eased(_ mode: SKActionTimingMode) -> SKAction {
        timingMode = mode
        return self
    }
}
