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

    func update(model: TableModel, layout: TableLayout) {
        guard let game = model.game else {
            removeAllChildren()
            rows.removeAll()
            return
        }
        let total = game.laid.count
        for (seat, row) in rows where (game.laid[safe: seat] ?? nil) == nil {
            row.node.removeFromParent()
            rows[seat] = nil
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
            }
        }
    }

    /// Frames of `seat`'s laid groups, in the zone's parent space.
    func groupFrames(seat: Seat) -> [CGRect] { rows[seat]?.groupFrames ?? [] }

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
        for group in row.groups {
            let start = x
            for (j, card) in group.cards.enumerated() {
                let node = CardNode(card: card, size: mini, shadow: false)
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
