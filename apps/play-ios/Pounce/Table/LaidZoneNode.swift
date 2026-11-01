import PounceKit
import SpriteKit

/// Laid-down groups around the piles: one row per seat that laid this round, a tiny cat of
/// that seat at the left and its groups as small overlapped card fans. Card nodes keep their
/// identity by card id across updates, so a hit or a lay-down animates onto nodes that stay.
@MainActor
final class LaidZoneNode: SKNode {
    @MainActor private final class Row {
        let node = SKNode()
        var head: SKSpriteNode?
        var cards: [CardID: CardNode] = [:]
        var groups: [Group] = []
        var cat = -1
        var rect: CGRect = .zero
        var miniSize: CGSize = .zero
        /// Group frames in the zone's parent space.
        var groupFrames: [CGRect] = []
    }

    private var rows: [Seat: Row] = [:]
    /// Glows behind laid groups a held card can hit, above the rows' rings, below their cards.
    private let glowLayer = SKNode()
    private var shownTargets: Set<HitTarget> = []
    /// Enlarged while a card is held and something can be hit (spec §5.7).
    private(set) var enlarged = false

    /// Growth while enlarged, about `center`.
    static let enlargeScale: CGFloat = 1.1

    override init() {
        super.init()
        glowLayer.zPosition = 0.05
        addChild(glowLayer)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(model: TableModel, layout: TableLayout) {
        guard let game = model.game else {
            rows.values.forEach { $0.node.removeFromParent() }
            rows.removeAll()
            setTargets([], enlarged: false, about: .zero)
            return
        }
        let total = game.laid.count
        for (seat, row) in rows where (game.laid[safe: seat] ?? nil) == nil {
            row.node.removeFromParent()
            rows[seat] = nil
            invalidateGlows()
        }
        for (seat, laid) in game.laid.enumerated() {
            guard let groups = laid else { continue }
            let row = rows[seat] ?? {
                let r = Row()
                rows[seat] = r
                addChild(r.node)
                return r
            }()
            let rect = layout.laidRow(slot: seat, of: total)
            let cat = SeatInfo.catIndex(model.room.seats[safe: seat])
            if row.groups != groups || row.rect != rect || row.cat != cat || row.miniSize != layout.miniCardSize {
                row.groups = groups
                row.rect = rect
                row.cat = cat
                row.miniSize = layout.miniCardSize
                build(row, seat: seat)
                invalidateGlows()
            }
        }
    }

    /// Frames of `seat`'s laid groups, in the zone's parent space (as drawn, enlarged or not).
    func groupFrames(seat: Seat) -> [CGRect] {
        (rows[seat]?.groupFrames ?? []).map { f in
            CGRect(x: f.minX * xScale + position.x, y: f.minY * yScale + position.y,
                   width: f.width * xScale, height: f.height * yScale)
        }
    }

    /// The laid group under `point` (parent space).
    func group(at point: CGPoint) -> HitTarget? {
        for seat in laidSeats {
            for (g, f) in groupFrames(seat: seat).enumerated() where f.insetBy(dx: -4, dy: -6).contains(point) {
                return HitTarget(seat: seat, group: g)
            }
        }
        return nil
    }

    /// Glows `targets` (card-glow behind each group plus a sparkle; while there are targets,
    /// the other groups dim) and enlarges the zone about `center` (the piles) when asked.
    /// Called after every `update`.
    func setTargets(_ targets: Set<HitTarget>, enlarged: Bool, about center: CGPoint) {
        self.enlarged = enlarged
        let k: CGFloat = enlarged ? Self.enlargeScale : 1
        setScale(k)
        position = CGPoint(x: center.x * (1 - k), y: center.y * (1 - k))
        guard targets != shownTargets else { return }
        shownTargets = targets
        glowLayer.removeAllChildren()
        for (seat, row) in rows {
            for child in row.node.children {
                guard let card = child as? CardNode, let name = card.name, name.hasPrefix("g"),
                      let g = Int(name.dropFirst()) else { continue }
                // Darken (not fade: faded cards show the ones under them).
                let lit = targets.isEmpty || targets.contains(HitTarget(seat: seat, group: g))
                card.color = UIColor(white: 0.08, alpha: 1)
                card.colorBlendFactor = lit ? 0 : 0.5
            }
        }
        let sparkle = TableArt.texture(ArtName.fxSparkle, atlas: ArtName.Atlas.fx)
        for t in targets {
            guard let row = rows[t.seat], row.groupFrames.indices.contains(t.group) else { continue }
            let f = row.groupFrames[t.group]
            let glow = SKSpriteNode(texture: TableArt.cards(ArtName.cardGlow))
            let pad = CardNode.glowSize(for: row.miniSize)
            glow.size = CGSize(width: f.width + (pad.width - row.miniSize.width) * 1.8, height: f.height + (pad.height - row.miniSize.height) * 1.8)
            glow.centerRect = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
            glow.position = CGPoint(x: f.midX, y: f.midY)
            glowLayer.addChild(glow)
            for (dx, dy, d) in [(f.maxX - 2, f.maxY - 2, 20.0), (f.minX + 3, f.minY + 4, 14.0)] {
                let s = SKSpriteNode(texture: sparkle, size: CGSize(width: d, height: d))
                s.position = CGPoint(x: dx, y: dy)
                s.zPosition = 1
                glowLayer.addChild(s)
            }
        }
    }

    /// Forces the glow sprites to rebuild after rows moved.
    private func invalidateGlows() {
        shownTargets = []
        glowLayer.removeAllChildren()
    }

    var laidSeats: [Seat] { rows.keys.sorted() }

    /// Where a row's pieces go: the cat head, each group's card centers and frames (zone space).
    struct RowPlacement {
        var headCenter: CGPoint
        var headSize: CGFloat
        var cards: [[CGPoint]]
        var frames: [CGRect]
    }

    static func placement(groups: [Group], rect: CGRect, mini: CGSize) -> RowPlacement {
        let headSize = min(26, rect.height * 0.5)
        let gap: CGFloat = 6
        let left = rect.minX + headSize + 8
        let avail = rect.maxX - left
        let n = groups.count
        let overlaps = groups.reduce(0) { $0 + max($1.cards.count - 1, 0) }
        var step = overlaps > 0 ? (avail - CGFloat(n) * mini.width - gap * CGFloat(max(n - 1, 0))) / CGFloat(overlaps) : 0
        step = min(max(step, 4), mini.width * 0.62)
        var x = left
        var cards: [[CGPoint]] = []
        var frames: [CGRect] = []
        for group in groups {
            cards.append(group.cards.indices.map { j in CGPoint(x: x + mini.width / 2 + CGFloat(j) * step, y: rect.midY) })
            let width = CGFloat(max(group.cards.count - 1, 0)) * step + mini.width
            frames.append(CGRect(x: x, y: rect.midY - mini.height / 2, width: width, height: mini.height))
            x += width + gap
        }
        return RowPlacement(
            headCenter: CGPoint(x: rect.minX + headSize / 2 + 2, y: rect.midY), headSize: headSize, cards: cards, frames: frames)
    }

    /// Zone space → parent space (as drawn, enlarged or not).
    private func toParent(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * xScale + position.x, y: p.y * yScale + position.y)
    }

    /// Where each card of `groups` will land when `seat` lays them down, in parent space, for
    /// a table with `total` seats (the lay-down animation flies there before the row exists).
    func landing(groups: [Group], seat: Seat, total: Int, layout: TableLayout) -> [[CGPoint]] {
        let rect = layout.laidRow(slot: seat, of: total)
        return Self.placement(groups: groups, rect: rect, mini: layout.miniCardSize).cards.map { $0.map(toParent) }
    }

    /// Where `card` lands when `seat`'s group `index` becomes `group` (a hit), in parent space.
    func landing(hit card: CardID, seat: Seat, index: Int, group: Group) -> CGPoint? {
        guard let row = rows[seat], row.groups.indices.contains(index),
              let j = group.cards.firstIndex(of: card) else { return nil }
        var groups = row.groups
        groups[index] = group
        let p = Self.placement(groups: groups, rect: row.rect, mini: row.miniSize)
        return p.cards[safe: index]?[safe: j].map(toParent)
    }

    /// The card nodes of `seat`'s group `index`, for a bump.
    func groupNodes(seat: Seat, index: Int) -> [CardNode] {
        guard let row = rows[seat], let group = row.groups[safe: index] else { return [] }
        return group.cards.compactMap { row.cards[$0] }
    }

    /// Displayed scale of a mini card relative to a full-size card.
    func miniScale(layout: TableLayout) -> CGFloat {
        layout.miniCardSize.width / max(layout.cardSize.width, 1) * xScale
    }

    private func build(_ row: Row, seat: Seat) {
        let mini = row.miniSize
        let place = Self.placement(groups: row.groups, rect: row.rect, mini: mini)

        // The seat's tiny cat on the left (rebuilt only when the cat changes or it moved).
        let headSize = place.headSize
        if row.head?.name != "head\(row.cat)" || row.head?.size.width != headSize + 4 {
            row.head?.removeFromParent()
            let ring = SKSpriteNode(texture: TableArt.table(ArtName.ring), size: CGSize(width: headSize + 4, height: headSize + 4))
            ring.name = "head\(row.cat)"
            ring.color = UIColor(SeatInfo.ringColor(seat))
            ring.colorBlendFactor = 0.85
            ring.zPosition = 0
            let face = SKSpriteNode(texture: TableArt.cat(row.cat, .idle), size: CGSize(width: headSize, height: headSize))
            face.zPosition = 0.05
            ring.addChild(face)
            row.node.addChild(ring)
            row.head = ring
        }
        row.head?.position = place.headCenter

        // Groups fanned left to right in the space after the cat; card nodes reused by id.
        var keep: Set<CardID> = []
        var z: CGFloat = 0.1
        for (g, group) in row.groups.enumerated() {
            for (j, card) in group.cards.enumerated() {
                keep.insert(card)
                let node: CardNode
                if let existing = row.cards[card] {
                    node = existing
                } else {
                    node = CardNode(card: card, size: mini, shadow: false)
                    row.cards[card] = node
                    row.node.addChild(node)
                }
                node.name = "g\(g)"
                node.size = mini
                node.position = place.cards[g][j]
                node.zPosition = z
                node.zRotation = 0
                node.alpha = 1
                node.colorBlendFactor = 0
                z += 0.01
            }
        }
        for (card, node) in row.cards where !keep.contains(card) {
            node.removeFromParent()
            row.cards[card] = nil
        }
        row.groupFrames = place.frames
    }
}
