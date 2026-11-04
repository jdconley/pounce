import PounceKit
import SpriteKit

/// The bar across the top: every other seat's cat in turn order after the bottom seat (every
/// seat on a phone holding none), with its card count, presence pose and badges, and its name on
/// a pill under it. The current player's ring glows and its name pill turns orange.
@MainActor
final class OpponentsNode: SKNode {
    private var cats: [Seat: CatNode] = [:]
    private var tags: [Seat: SKSpriteNode] = [:]
    /// What each name pill shows, to redraw it when the turn moves between snapshots.
    private var tagText: [Seat: (name: String, width: CGFloat)] = [:]
    /// Seat order left to right, as last laid out.
    private(set) var order: [Seat] = []

    func node(for seat: Seat) -> CatNode? { cats[seat] }

    /// Lays the bar out for `seats` (`TableModel.barSeats`); returns the seats whose ring just
    /// became the current player's.
    @discardableResult
    func update(model: TableModel, seats: [Seat], layout: TableLayout) -> [Seat] {
        guard let game = model.game else {
            clear()
            return []
        }
        var turnedOn: [Seat] = []
        let slots = layout.opponentSlots
        let spacing = slots.count > 1 ? slots[1].x - slots[0].x : layout.size.width
        // The cat sits high in the bar and its name pill along the bottom.
        let diameter = min(Self.maxDiameter, spacing - 12)
        let names = SeatInfo.names(model.room)
        let tagWidth = min(spacing - 6, 140)
        let tagY = layout.opponentsBar.minY + Self.tagCenterFromBottom

        for (seat, tag) in tags where !seats.contains(seat) {
            tag.removeFromParent()
            tags[seat] = nil
            tagText[seat] = nil
        }
        for (seat, node) in cats where !seats.contains(seat) || node.diameter != diameter
            || node.cat != SeatInfo.catIndex(model.room.seats[safe: seat]) {
            node.removeFromParent()
            cats[seat] = nil
        }
        for (i, seat) in seats.enumerated() where i < slots.count {
            let view = model.room.seats[safe: seat]
            let node: CatNode
            if let existing = cats[seat] {
                node = existing
            } else {
                node = CatNode(cat: SeatInfo.catIndex(view), ringColor: SeatInfo.ringColor(seat), diameter: diameter)
                cats[seat] = node
                addChild(node)
            }
            node.position = CGPoint(x: slots[i].x, y: slots[i].y + Self.catLift)
            node.setScale(1)
            node.zPosition = CGFloat(i)
            node.setPresence(view?.kind == .bot ? nil : view?.presence)
            node.setBadges(
                bot: view?.kind == .bot,
                skip: game.pendingSkip[safe: seat] ?? false,
                laid: (game.laid[safe: seat] ?? nil) != nil)
            node.setCount(game.handCounts[safe: seat])
            let active = game.status == .playing && game.turn == seat
            if node.setActive(active) { turnedOn.append(seat) }

            let tag = tags[seat] ?? {
                let t = SKSpriteNode()
                t.name = "name"
                tags[seat] = t
                addChild(t)
                return t
            }()
            tagText[seat] = (names[safe: seat] ?? "", tagWidth)
            setTag(seat, active: active)
            tag.position = CGPoint(x: slots[i].x, y: tagY)
            tag.zPosition = 20 + CGFloat(i)
        }
        order = Array(seats.prefix(slots.count))
        return turnedOn
    }

    /// No cats at all (no game on the table).
    func clear() {
        removeAllChildren()
        cats.removeAll()
        tags.removeAll()
        tagText.removeAll()
        order = []
    }

    /// The cat's diameter at most (a 96 pt bar with its name pill under the cat).
    static let maxDiameter: CGFloat = 62
    /// How far above the bar's middle the cats sit, leaving the bottom for the names.
    static let catLift: CGFloat = 8
    /// The name pill's center, above the bar's bottom edge.
    static let tagCenterFromBottom: CGFloat = 12

    /// A seat's name pill (tests and screenshots).
    func tag(for seat: Seat) -> SKSpriteNode? { tags[seat] }

    /// Lights the name pill of whoever's turn it is (orange), and only theirs.
    func setTurn(_ turn: Seat?) {
        for seat in tags.keys { setTag(seat, active: seat == turn) }
    }

    private func setTag(_ seat: Seat, active: Bool) {
        guard let tag = tags[seat], let text = tagText[seat] else { return }
        let texture = CardFaceFactory.shared.nameTag(text.name, maxWidth: text.width, active: active)
        tag.texture = texture
        tag.size = texture.size()
    }

    /// Touch / accessibility frame of a seat's cat, in this node's parent space.
    func frame(of seat: Seat) -> CGRect? {
        guard let node = cats[seat] else { return nil }
        let d = max(node.diameter, 44)
        return CGRect(x: node.position.x - d / 2, y: node.position.y - d / 2, width: d, height: d)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
