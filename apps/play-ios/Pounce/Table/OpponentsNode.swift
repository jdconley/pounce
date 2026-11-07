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
    /// "Weak signal" / "Reconnecting" under a seat's name pill while its phone's link is bad.
    private var linkTags: [Seat: SKSpriteNode] = [:]
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
        // The cat sits high in its slot and its name pill under it, along the bar's bottom.
        let diameter = min(layout.catDiameter, spacing - 12)
        let names = SeatInfo.names(model.room)
        let tagWidth = min(spacing - 6, layout.arrangement == .phone ? 140 : 170)

        for (seat, tag) in tags where !seats.contains(seat) {
            tag.removeFromParent()
            tags[seat] = nil
            tagText[seat] = nil
        }
        for (seat, tag) in linkTags where !seats.contains(seat) {
            tag.removeFromParent()
            linkTags[seat] = nil
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
            node.position = CGPoint(x: slots[i].x, y: slots[i].y + layout.catLift)
            node.setScale(1)
            node.zPosition = CGFloat(i)
            node.setPresence(view?.kind == .bot ? nil : view?.presence)
            let link = view?.kind == .human ? LinkWords.seat(view?.link) : nil
            node.setLink(link?.level)
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
            tag.position = CGPoint(x: slots[i].x, y: slots[i].y - layout.nameDrop)
            tag.zPosition = 20 + CGFloat(i)
            // The current player's "Mia's turn" cue hangs from the bar under their cat: their
            // link goes under that, since theirs is the one everyone is waiting on.
            let below = active ? turnCueBottom(layout: layout, tag: tag) : nil
            setLinkTag(
                seat, link, under: tag, below: below, width: tagWidth, size: layout.arrangement == .phone ? 12 : 15,
                z: 30 + CGFloat(i))
        }
        order = Array(seats.prefix(slots.count))
        return turnedOn
    }

    /// The bottom of the turn cue's pill (`TheirTurnTag`: about 28 pt tall, hung from the bar's
    /// bottom, or under a roomy bar's lower name pill), in this node's parent space.
    private func turnCueBottom(layout: TableLayout, tag: SKSpriteNode) -> CGFloat {
        var top = layout.opponentsBar.minY
        if layout.arrangement != .phone { top = min(top, tag.position.y - tag.size.height / 2 - 4) }
        return top - 30
    }

    private func setLinkTag(
        _ seat: Seat, _ link: (level: SignalGlyph.Level, text: String)?, under tag: SKSpriteNode, below: CGFloat?,
        width: CGFloat, size: CGFloat, z: CGFloat
    ) {
        guard let link else {
            linkTags[seat]?.removeFromParent()
            linkTags[seat] = nil
            return
        }
        let node = linkTags[seat] ?? {
            let n = SKSpriteNode()
            n.name = "link"
            linkTags[seat] = n
            addChild(n)
            return n
        }()
        let texture = SignalGlyph.pillTexture(link.level, text: link.text, maxWidth: width, size: size)
        node.texture = texture
        node.size = texture.size()
        var y = tag.position.y - tag.size.height / 2 - node.size.height / 2 + 1
        if let below { y = min(y, below - node.size.height / 2) }
        node.position = CGPoint(x: tag.position.x, y: y)
        node.zPosition = z
    }

    /// A seat's link pill (tests and screenshots).
    func linkTag(for seat: Seat) -> SKSpriteNode? { linkTags[seat] }

    /// No cats at all (no game on the table).
    func clear() {
        removeAllChildren()
        cats.removeAll()
        tags.removeAll()
        linkTags.removeAll()
        tagText.removeAll()
        order = []
    }

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
