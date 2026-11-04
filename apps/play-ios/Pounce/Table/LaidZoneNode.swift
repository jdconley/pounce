import PounceKit
import SpriteKit

/// Laid-down groups around the piles: one row per seat that laid this round, a tiny cat of
/// that seat at the left with its name under it, and its groups as small card fans (compact
/// faces, each card overlapped only past its corner index). A group too long for its row folds its middle
/// cards under a "+N" badge. Card nodes keep their identity by card id across updates, so a
/// hit or a lay-down animates onto nodes that stay.
@MainActor
final class LaidZoneNode: SKNode {
    @MainActor private final class Row {
        let node = SKNode()
        var head: SKSpriteNode?
        let tag = SKSpriteNode()
        var name = ""
        var cards: [CardID: CardNode] = [:]
        var badges: [SKSpriteNode] = []
        var groups: [Group] = []
        var cat = -1
        var rect: CGRect = .zero
        var miniSize: CGSize = .zero
        /// Group frames in the zone's parent space.
        var groupFrames: [CGRect] = []
    }

    private var rows: [Seat: Row] = [:]
    /// Every seat's shown name, as of the last update (the lay-down landing needs it first).
    private var names: [String] = []
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
        names = SeatInfo.names(model.room)
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
            let name = names[safe: seat] ?? ""
            if row.groups != groups || row.rect != rect || row.cat != cat || row.miniSize != layout.miniCardSize
                || row.name != name {
                row.groups = groups
                row.rect = rect
                row.cat = cat
                row.name = name
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

    /// Where a row's pieces go: the cat head, the name under it, each group's card centers and
    /// frames (zone space). Folded cards (`shown` false) sit under their group's last shown card.
    struct RowPlacement {
        var headCenter: CGPoint
        var headSize: CGFloat
        var nameCenter: CGPoint
        var cards: [[CGPoint]]
        var shown: [[Bool]]
        /// Per group, how many cards are folded away and where their badge goes.
        var folded: [(count: Int, at: CGPoint)]
        var frames: [CGRect]
    }

    /// "+N" badge text size: an 11 pt cap height.
    static let badgeSize: CGFloat = 16

    /// The widest a row's name pill gets: a fair share of a two-column row, more of a wide one.
    static func nameWidth(row: CGRect) -> CGFloat {
        min(84, max(56, row.width * 0.3))
    }

    /// The name pill for a row, cut to fit `nameWidth(row:)`.
    static func nameTexture(_ name: String, row: CGRect) -> SKTexture {
        CardFaceFactory.shared.nameTag(name, maxWidth: nameWidth(row: row), active: false)
    }

    /// `name`: the drawn name pill's size; the cat sits over it and the groups start after the
    /// wider of the two.
    static func placement(groups: [Group], rect: CGRect, mini: CGSize, name: CGSize) -> RowPlacement {
        let headSize = min(26, rect.height * 0.5)
        let gap: CGFloat = 8
        let column = max(headSize + 4, name.width)
        let left = rect.minX + column + 6
        let avail = rect.maxX - left
        // Each card shows up to the end of its corner index before the next one covers it.
        let k = mini.width / CardFaceFactory.cardSize.width
        let strips = groups.map { $0.cards.map { min(CardFaceFactory.indexWidth($0) * k, mini.width) } }
        var counts = groups.map(\.cards.count)
        // A folded group shows its first cards and its last (a run keeps both ends).
        func visible(_ g: Int) -> [Int] {
            let n = groups[g].cards.count, v = counts[g]
            if v >= n { return Array(0..<n) }
            return v <= 1 ? [0] : Array(0..<(v - 1)) + [n - 1]
        }
        func width(_ g: Int) -> CGFloat {
            visible(g).dropLast().reduce(mini.width) { $0 + strips[g][$1] }
        }
        func total() -> CGFloat {
            groups.indices.reduce(gap * CGFloat(max(groups.count - 1, 0))) { $0 + width($1) }
        }
        // Fold the group showing the most cards, one card at a time, until the row fits.
        while total() > avail,
              let g = counts.indices.filter({ counts[$0] > 1 }).max(by: { counts[$0] < counts[$1] }) {
            counts[g] -= 1
        }

        var x = left
        var cards: [[CGPoint]] = []
        var shown: [[Bool]] = []
        var folded: [(count: Int, at: CGPoint)] = []
        var frames: [CGRect] = []
        for (g, group) in groups.enumerated() {
            let vis = visible(g)
            var centers = Array(repeating: CGPoint.zero, count: group.cards.count)
            var on = Array(repeating: false, count: group.cards.count)
            var cx = x + mini.width / 2
            for j in vis {
                centers[j] = CGPoint(x: cx, y: rect.midY)
                on[j] = true
                cx += strips[g][j]
            }
            let last = centers[vis.last ?? 0]
            for j in centers.indices where !on[j] { centers[j] = last }
            // Low on the cards, clear of the corner indexes: over the fold, or on a lone card.
            let badgeX = vis.count > 1 ? last.x - mini.width / 2 : last.x + mini.width * 0.2
            folded.append((group.cards.count - vis.count, CGPoint(x: badgeX, y: rect.midY - mini.height * 0.24)))
            cards.append(centers)
            shown.append(on)
            let w = width(g)
            frames.append(CGRect(x: x, y: rect.midY - mini.height / 2, width: w, height: mini.height))
            x += w + gap
        }
        // Cat over name, the pair centered on the row's middle and on the column.
        let stack = headSize + 4 + 1 + name.height
        let headY = rect.midY + stack / 2 - (headSize + 4) / 2
        let nameY = rect.midY - stack / 2 + name.height / 2
        let columnX = rect.minX + column / 2
        return RowPlacement(
            headCenter: CGPoint(x: columnX, y: headY), headSize: headSize,
            nameCenter: CGPoint(x: columnX, y: nameY),
            cards: cards, shown: shown, folded: folded, frames: frames)
    }

    /// Zone space → parent space (as drawn, enlarged or not).
    private func toParent(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * xScale + position.x, y: p.y * yScale + position.y)
    }

    /// Where each card of `groups` will land when `seat` lays them down, in parent space, for
    /// a table with `total` seats (the lay-down animation flies there before the row exists).
    func landing(groups: [Group], seat: Seat, total: Int, layout: TableLayout) -> [[CGPoint]] {
        let rect = layout.laidRow(slot: seat, of: total)
        let name = Self.nameTexture(names[safe: seat] ?? "", row: rect).size()
        return Self.placement(groups: groups, rect: rect, mini: layout.miniCardSize, name: name).cards.map { $0.map(toParent) }
    }

    /// Where `card` lands when `seat`'s group `index` becomes `group` (a hit), in parent space.
    func landing(hit card: CardID, seat: Seat, index: Int, group: Group) -> CGPoint? {
        guard let row = rows[seat], row.groups.indices.contains(index),
              let j = group.cards.firstIndex(of: card) else { return nil }
        var groups = row.groups
        groups[index] = group
        let p = Self.placement(groups: groups, rect: row.rect, mini: row.miniSize, name: row.tag.size)
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
        let nameTexture = Self.nameTexture(row.name, row: row.rect)
        row.tag.texture = nameTexture
        row.tag.size = nameTexture.size()
        row.tag.zPosition = 0.06
        if row.tag.parent == nil { row.node.addChild(row.tag) }
        let place = Self.placement(groups: row.groups, rect: row.rect, mini: mini, name: row.tag.size)
        row.tag.position = place.nameCenter

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
                    node = CardNode(card: card, size: mini, shadow: false, compact: true)
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
                node.isHidden = !place.shown[g][j]
                z += 0.01
            }
        }
        row.badges.forEach { $0.removeFromParent() }
        row.badges = place.folded.filter { $0.count > 0 }.map { fold in
            let t = CardFaceFactory.shared.badge("+\(fold.count)", size: Self.badgeSize)
            let badge = SKSpriteNode(texture: t, size: t.size())
            badge.position = fold.at
            badge.zPosition = z + 0.1
            row.node.addChild(badge)
            return badge
        }
        for (card, node) in row.cards where !keep.contains(card) {
            node.removeFromParent()
            row.cards[card] = nil
        }
        row.groupFrames = place.frames
    }
}
