import PounceKit
import SpriteKit

/// The phase goal above the hand, drawn as one tray per requirement in the server's phase
/// order: the group size as a big numeral and a tiny card fan that shows the kind (same
/// number, in a row, one coat). Before laying down these are also the lay-down trays
/// (spec §5.8): cards put in a tray replace its example fan, a valid tray turns gold, and
/// trays that can take the held card brighten, grow a little and sparkle (not hue alone).
@MainActor
final class TrayNode: SKNode {
    private(set) var requirements: [Requirement] = []
    private(set) var frames: [CGRect] = []
    private var slots: [Slot] = []
    private var builtFor: (reqs: [Requirement], frame: CGRect)?
    /// The big paw that sends the lay-down; shown when every tray is valid.
    let layDownButton: SKSpriteNode
    /// Card nodes by id for the cards currently in trays.
    private var cardNodes: [CardID: CardNode] = [:]
    /// Cards shown in each tray, in display order (hidden ones left out).
    private(set) var shownCards: [[CardID]] = []
    private(set) var valid: [Bool] = []

    @MainActor private final class Slot {
        let node = SKNode()
        let tray: SKSpriteNode
        let example = SKNode()
        let cards = SKNode()
        let sparkle: SKSpriteNode
        var frame: CGRect = .zero
        var fanLeft: CGFloat = 0
        var fanRight: CGFloat = 0

        init(tray: SKSpriteNode, sparkle: SKSpriteNode) {
            self.tray = tray
            self.sparkle = sparkle
        }
    }

    private static let trayArt = CGSize(width: 120, height: 64)

    override init() {
        layDownButton = SKSpriteNode(texture: TableArt.image(ArtName.iconPawMenu), size: CGSize(width: 64, height: 64))
        super.init()
        layDownButton.isHidden = true
        layDownButton.zPosition = 5
        addChild(layDownButton)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(requirements reqs: [Requirement], layout: TableLayout) {
        let frame = layout.traysFrame
        layDownButton.position = CGPoint(x: frame.midX, y: frame.maxY + 40)
        if let built = builtFor, built.reqs == reqs, built.frame == frame { return }
        builtFor = (reqs, frame)
        requirements = reqs
        slots.forEach { $0.node.removeFromParent() }
        slots.removeAll()
        cardNodes.removeAll()
        shownCards = Array(repeating: [], count: reqs.count)
        valid = Array(repeating: false, count: reqs.count)
        frames = layout.trayFrames(count: reqs.count)
        for (i, req) in reqs.enumerated() {
            let f = frames[i]
            let tray = SKSpriteNode(texture: TableArt.table(ArtName.tray), size: Self.trayArt)
            tray.centerRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
            tray.xScale = f.width / Self.trayArt.width
            tray.yScale = f.height / Self.trayArt.height
            tray.zPosition = 0
            let sparkle = SKSpriteNode(texture: TableArt.texture(ArtName.fxSparkle, atlas: ArtName.Atlas.fx), size: CGSize(width: 26, height: 26))
            sparkle.position = CGPoint(x: f.width / 2 - 8, y: f.height / 2 - 6)
            sparkle.zPosition = 3
            sparkle.isHidden = true
            let slot = Slot(tray: tray, sparkle: sparkle)
            slot.frame = f
            slot.node.position = CGPoint(x: f.midX, y: f.midY)
            slot.node.addChild(tray)
            slot.example.zPosition = 1
            slot.cards.zPosition = 1
            slot.node.addChild(slot.example)
            slot.node.addChild(slot.cards)
            slot.node.addChild(sparkle)
            addChild(slot.node)
            slots.append(slot)
            addPictogram(req, to: slot)
        }
    }

    /// Shows the cards in each tray (leaving out `hidden`, e.g. a card being dragged), gold
    /// for valid trays, and the target highlight on `targets`.
    func show(_ state: TrayState, hidden: Set<CardID>, targets: Bool) {
        guard state.requirements == requirements else { return }
        var seen = Set<CardID>()
        shownCards = []
        valid = []
        for (i, slot) in slots.enumerated() {
            let cards = state.slots[i].filter { !hidden.contains($0) }
            shownCards.append(cards)
            let isValid = state.isValid(i) && cards.count == state.slots[i].count
            valid.append(isValid)
            slot.tray.texture = TableArt.table(isValid ? ArtName.trayGold : ArtName.tray)
            slot.example.isHidden = !cards.isEmpty
            layoutCards(cards, in: slot)
            seen.formUnion(cards)
            slot.node.setScale(targets ? 1.04 : 1)
            slot.tray.colorBlendFactor = 0
            slot.node.alpha = 1
            slot.sparkle.isHidden = !targets
        }
        for (id, node) in cardNodes where !seen.contains(id) {
            node.removeFromParent()
            cardNodes[id] = nil
        }
        layDownButton.isHidden = !state.allValid || !hidden.isDisjoint(with: state.cardsInTrays)
    }

    /// The tray under `point` (parent space), with a little slop above and below.
    func tray(at point: CGPoint) -> Int? {
        frames.firstIndex { $0.insetBy(dx: -2, dy: -10).contains(point) }
    }

    /// The tray card under `point` (parent space), topmost first.
    func card(at point: CGPoint) -> (card: CardID, tray: Int)? {
        let space = parent ?? self
        for (t, cards) in shownCards.enumerated() {
            let local = slots[t].cards.convert(point, from: space)
            for id in cards.reversed() {
                if let node = cardNodes[id], node.frame.contains(local) { return (id, t) }
            }
        }
        return nil
    }

    /// A tray card's frame in the parent's space.
    func frame(of card: CardID) -> CGRect? {
        guard let node = cardNodes[card], let t = shownCards.firstIndex(where: { $0.contains(card) }) else { return nil }
        return parentRect(node.frame, from: slots[t].cards)
    }

    /// The display slot in tray `t` nearest `x` (parent space) for a fan of `count` cards,
    /// for moving a Yarn.
    func slotIndex(tray t: Int, x: CGFloat, count: Int) -> Int {
        guard slots.indices.contains(t), count > 1 else { return 0 }
        let slot = slots[t]
        let localX = slot.node.convert(CGPoint(x: x, y: slot.frame.midY), from: parent ?? self).x
        let (start, step) = fan(count: count, card: Self.cardSize(slot), slot: slot)
        let i = Int(((localX - start) / max(step, 1)).rounded())
        return min(max(i, 0), count - 1)
    }

    private func parentRect(_ r: CGRect, from node: SKNode) -> CGRect {
        let space = parent ?? self
        let a = space.convert(CGPoint(x: r.minX, y: r.minY), from: node)
        let b = space.convert(CGPoint(x: r.maxX, y: r.maxY), from: node)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private static func cardSize(_ slot: Slot) -> CGSize {
        let h = slot.frame.height - 8
        return CGSize(width: (h * 64 / 90).rounded(), height: h)
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

    /// Fan geometry inside a tray (tray-local x): left edge after the numeral, right edge
    /// before the rim.
    private func fan(count: Int, card: CGSize, slot: Slot) -> (start: CGFloat, step: CGFloat) {
        let avail = slot.fanRight - slot.fanLeft
        let step = count > 1 ? min(card.width * 0.72, (avail - card.width) / CGFloat(count - 1)) : 0
        let span = CGFloat(max(count - 1, 0)) * step + card.width
        return (slot.fanLeft + max(0, (avail - span) / 2) + card.width / 2, step)
    }

    private func addPictogram(_ req: Requirement, to slot: Slot) {
        let f = slot.frame
        let digits = CardFaceFactory.shared.numeral(String(req.size), size: 30, outline: 3)
        let number = SKSpriteNode(texture: digits, size: digits.size())
        number.position = CGPoint(x: -f.width / 2 + 10 + digits.size().width / 2, y: 0)
        number.zPosition = 2
        slot.node.addChild(number)
        slot.fanLeft = number.frame.maxX + 6
        slot.fanRight = f.width / 2 - 10

        let cardH = f.height - 18
        let card = CGSize(width: (cardH * 64 / 90).rounded(), height: cardH)
        let ids = Self.example(req)
        let (start, step) = fan(count: ids.count, card: card, slot: slot)
        for (j, id) in ids.enumerated() {
            let n = CardNode(card: id, size: card, shadow: false)
            n.position = CGPoint(x: start + CGFloat(j) * step, y: 0)
            n.zPosition = CGFloat(j) * 0.01
            n.alpha = 0.55
            slot.example.addChild(n)
        }
    }

    private func layoutCards(_ cards: [CardID], in slot: Slot) {
        let size = Self.cardSize(slot)
        let (start, step) = fan(count: cards.count, card: size, slot: slot)
        for (j, id) in cards.enumerated() {
            let node: CardNode
            if let existing = cardNodes[id] {
                node = existing
                if node.parent !== slot.cards {
                    node.removeFromParent()
                    slot.cards.addChild(node)
                }
            } else {
                node = CardNode(card: id, size: size, shadow: false)
                cardNodes[id] = node
                slot.cards.addChild(node)
            }
            node.size = size
            node.position = CGPoint(x: start + CGFloat(j) * step, y: 0)
            node.zRotation = 0
            node.setScale(1)
            node.alpha = 1
            node.zPosition = CGFloat(j) * 0.01
        }
    }
}
