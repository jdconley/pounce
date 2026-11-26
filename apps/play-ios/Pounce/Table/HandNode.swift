import PounceKit
import SpriteKit

/// The fanned hand at the bottom. Face cards exist only for the revealed seat; otherwise the
/// fan is face-down backs (a multi-seat phone between reveals) or empty. Reconciling is
/// idempotent: nodes are matched by card id and moved to their layout placement. Always fully
/// opaque, on turn or off: a see-through hand was hard to read.
@MainActor
final class HandNode: FadeGroup {
    enum Content: Equatable {
        case faces([CardID])
        case backs(Int)
        case none
    }

    /// Hand cards left to right.
    private(set) var cards: [CardNode] = []
    private var faceNodes: [CardID: CardNode] = [:]
    private var backNodes: [CardNode] = []
    private(set) var content: Content = .none
    /// The selected card is raised and straightened (and drawn above its neighbors).
    private(set) var lifted: CardID?
    /// The empty slot a dragged card will land in (`TableLayout.hand(count:gap:)`); nil closes
    /// the fan up.
    private(set) var gap: Int?

    /// Within-layer z for a lifted card, above every resting card.
    static let liftedZ: CGFloat = 6

    /// Lays the fan out for `content`. A card already drawn at another size (the hand's size
    /// changed: the Cards/Table switch, a short hand, the trays going away, a turn of the iPad) is
    /// kept at the size it was drawn and returned with the tween that takes it to the new one, for
    /// the scene's director: no card pops to a new size in one frame. New cards start at full size.
    @discardableResult
    /// `dimmed` (off turn) no longer fades the hand: it stays fully opaque.
    func update(_ content: Content, layout: TableLayout, lifted: CardID?, gap: Int? = nil, dimmed: Bool) -> [(SKAction, SKNode)] {
        self.content = content
        // Every node's height as drawn now (an SKSpriteNode's `size` has its scale in it).
        var drawn: [ObjectIdentifier: CGFloat] = [:]
        for node in faceNodes.values { drawn[ObjectIdentifier(node)] = node.size.height }
        for node in backNodes { drawn[ObjectIdentifier(node)] = node.size.height }
        let ordered: [CardNode]
        switch content {
        case .faces(let ids):
            removeBacks()
            let keep = Set(ids)
            for (id, node) in faceNodes where !keep.contains(id) {
                node.removeFromParent()
                faceNodes[id] = nil
            }
            ordered = ids.map { id in
                if let node = faceNodes[id] { return node }
                let node = CardNode(card: id, size: layout.cardSize)
                faceNodes[id] = node
                addChild(node)
                return node
            }
            self.lifted = lifted.flatMap { keep.contains($0) ? $0 : nil }
        case .backs(let count):
            removeFaces()
            while backNodes.count > count { backNodes.removeLast().removeFromParent() }
            while backNodes.count < count {
                let node = CardNode(card: nil, size: layout.cardSize)
                backNodes.append(node)
                addChild(node)
            }
            ordered = backNodes
            self.lifted = nil
        case .none:
            removeFaces()
            removeBacks()
            ordered = []
            self.lifted = nil
        }
        cards = ordered
        self.gap = gap.map { min(max($0, 0), ordered.count) }
        let liftedIndex = self.lifted.flatMap { id in ordered.firstIndex { $0.card == id } }
        let placements = placements(layout, lifted: liftedIndex)
        var resizes: [(SKAction, SKNode)] = []
        for (i, node) in ordered.enumerated() {
            let p = placements[i]
            // Scale 1 before the size: `size` includes the scale, so a card caught mid-glide or
            // mid-squash would otherwise keep that scale in its size (a card a little too small).
            node.setScale(1)  // a cancelled squash or flip never sticks
            node.size = layout.cardSize
            node.position = p.position
            node.zRotation = p.rotation
            node.alpha = 1
            node.colorBlendFactor = 0  // a cancelled dark blink never sticks
            node.zPosition = i == liftedIndex ? Self.liftedZ : Self.z(p)
            if let was = drawn[ObjectIdentifier(node)], layout.cardSize.height > 0,
               abs(was / layout.cardSize.height - 1) > 0.02 {
                node.setScale(was / layout.cardSize.height)
                resizes.append((SKAction.scale(to: 1, duration: Self.resizeDuration).eased(.easeOut), node))
            }
        }
        // Never see-through, on or off turn (JD: "for my own hand ... i want the cards to not be
        // translucent they are hard to see"). Whose turn it is, the turn cue and the rings say.
        alpha = 1
        return resizes
    }

    /// How long a hand card takes to grow or shrink to a new hand size.
    static let resizeDuration: TimeInterval = 0.2

    /// Opens the fan at `gap` (or closes it, nil) without snapping: the moves that slide each
    /// card to its new place, for the scene to run through its director.
    func slide(gap: Int?, layout: TableLayout) -> [(SKAction, SKNode)] {
        let gap = gap.map { min(max($0, 0), cards.count) }
        guard gap != self.gap else { return [] }
        self.gap = gap
        let liftedIndex = lifted.flatMap { id in cards.firstIndex { $0.card == id } }
        return zip(cards, placements(layout, lifted: liftedIndex)).map { node, p in
            node.zPosition = Self.z(p)
            let move = SKAction.group([
                .move(to: p.position, duration: Self.slideDuration),
                .rotate(toAngle: p.rotation, duration: Self.slideDuration, shortestUnitArc: true),
            ])
            move.timingMode = .easeOut
            return (move, node)
        }
    }

    /// A card spreading apart or closing up for a dragged card, at normal speed (the scene's
    /// speed is the Pace factor).
    static let slideDuration: TimeInterval = 0.14

    private func placements(_ layout: TableLayout, lifted: Int?) -> [CardPlacement] {
        if let gap { return layout.hand(count: cards.count, gap: gap) }
        return layout.hand(count: cards.count, lifted: lifted)
    }

    /// TableLayout's z climbs from 10; keep the hand inside its 10-wide layer band.
    private static func z(_ p: CardPlacement) -> CGFloat { (p.z - 10) * 0.1 + 0.1 }

    /// The card at `index` in the fan, with its frame in the parent's space.
    func frame(at index: Int) -> CGRect? {
        guard cards.indices.contains(index) else { return nil }
        let node = cards[index]
        // The rotated card's bounding box, cut at the next card's edge so frames don't overlap
        // (the lifted card and the last card keep their whole box).
        var f = node.frame
        if index < cards.count - 1, node.card == nil || node.card != lifted {
            let next = cards[index + 1].frame.minX
            f.size.width = max(next - f.minX, 24)
        }
        return f.offsetBy(dx: position.x, dy: position.y)
    }

    /// The face card under `point` (parent space): the lifted card first, then right to left
    /// (the fan's stacking order), tested against each card's own rotated rectangle.
    func card(at point: CGPoint) -> CardID? {
        let space = parent ?? self
        let order = cards.sorted { $0.zPosition > $1.zPosition }
        for node in order {
            guard let id = node.card else { continue }
            let local = node.convert(point, from: space)
            let half = CGSize(width: node.size.width / 2 + 2, height: node.size.height / 2 + 2)
            if abs(local.x) <= half.width, abs(local.y) <= half.height { return id }
        }
        return nil
    }

    func node(for card: CardID) -> CardNode? { faceNodes[card] }

    /// Whether the fan holds a card at all (for the hand-area drop zone).
    var isEmpty: Bool { cards.isEmpty }

    private func removeFaces() {
        faceNodes.values.forEach { $0.removeFromParent() }
        faceNodes.removeAll()
    }

    private func removeBacks() {
        backNodes.forEach { $0.removeFromParent() }
        backNodes.removeAll()
    }
}
