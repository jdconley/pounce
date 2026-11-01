import PounceKit
import SpriteKit

/// Laid-down groups around the piles: one row per seat that laid this round, a tiny cat of
/// that seat at the left and its groups as small overlapped card fans.
@MainActor
final class LaidZoneNode: SKNode {
    @MainActor private final class Row {
        let node = SKNode()
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

    private func build(_ row: Row, seat: Seat) {
        row.node.removeAllChildren()
        let rect = row.rect
        let mini = row.miniSize

        // The seat's tiny cat on the left.
        let headSize = min(26, rect.height * 0.5)
        let ring = SKSpriteNode(texture: TableArt.table(ArtName.ring), size: CGSize(width: headSize + 4, height: headSize + 4))
        ring.color = UIColor(SeatInfo.ringColor(seat))
        ring.colorBlendFactor = 0.85
        ring.position = CGPoint(x: rect.minX + headSize / 2 + 2, y: rect.midY)
        ring.zPosition = 0
        let face = SKSpriteNode(texture: TableArt.cat(row.cat, .idle), size: CGSize(width: headSize, height: headSize))
        face.zPosition = 0.05
        ring.addChild(face)
        row.node.addChild(ring)

        // Groups fanned left to right in the space after the cat.
        let gap: CGFloat = 6
        let left = rect.minX + headSize + 8
        let avail = rect.maxX - left
        let n = row.groups.count
        let overlaps = row.groups.reduce(0) { $0 + max($1.cards.count - 1, 0) }
        var step = overlaps > 0 ? (avail - CGFloat(n) * mini.width - gap * CGFloat(max(n - 1, 0))) / CGFloat(overlaps) : 0
        step = min(max(step, 4), mini.width * 0.62)
        var x = left
        var z: CGFloat = 0.1
        row.groupFrames = []
        for (g, group) in row.groups.enumerated() {
            let start = x
            for (j, card) in group.cards.enumerated() {
                let node = CardNode(card: card, size: mini, shadow: false)
                node.name = "g\(g)"
                node.position = CGPoint(x: x + mini.width / 2 + CGFloat(j) * step, y: rect.midY)
                node.zPosition = z
                z += 0.01
                row.node.addChild(node)
            }
            let width = CGFloat(max(group.cards.count - 1, 0)) * step + mini.width
            row.groupFrames.append(CGRect(x: start, y: rect.midY - mini.height / 2, width: width, height: mini.height))
            x += width + gap
        }
    }
}
