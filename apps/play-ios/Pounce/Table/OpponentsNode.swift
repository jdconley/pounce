import PounceKit
import SpriteKit

/// The bar across the top: every other seat's cat in turn order after the bottom seat (every
/// seat on a phone holding none), with its phase chip, card count, presence pose and badges, and
/// its name on a plain pill under it. The current player's ring glows; nothing else says whose
/// turn it is. A tap on a cat opens that player's card (`TableScene.onPlayer`).
@MainActor
final class OpponentsNode: SKNode {
    private var cats: [Seat: CatNode] = [:]
    private var tags: [Seat: SKSpriteNode] = [:]
    /// What each name pill shows (redrawn only when it changes).
    private var tagText: [Seat: (name: String, width: CGFloat, size: CGFloat)] = [:]
    /// "Weak signal" / "Reconnecting" under a seat's name pill while its phone's link is bad.
    private var linkTags: [Seat: SKSpriteNode] = [:]
    /// Seat order left to right, as last laid out.
    private(set) var order: [Seat] = []

    func node(for seat: Seat) -> CatNode? { cats[seat] }

    /// What a layout pass changed that the scene pops.
    struct Changes {
        /// Seats whose ring just became the current player's.
        var turnedOn: [Seat] = []
        /// Seats whose phase chip just moved on to a later phase.
        var movedOn: [Seat] = []
    }

    /// Lays the bar out for `seats` (`TableModel.barSeats`).
    @discardableResult
    func update(model: TableModel, seats: [Seat], layout: TableLayout) -> Changes {
        guard let game = model.game else {
            clear()
            return Changes()
        }
        var changes = Changes()
        let slots = layout.opponentSlots
        let spacing = layout.opponentSpacing
        // The cat sits high in its slot and its name pill under it, along the bar's bottom.
        let diameter = layout.opponentDiameter
        let names = SeatInfo.names(model.room)
        // The words grow with the person's text size setting, as far as the bar has room: a
        // name pill may nearly touch its neighbors, and with larger text it gets wider.
        let textScale = TableText.scale
        let tagWidth = min(spacing - 2, (layout.arrangement == .phone ? 140 : 170) * textScale)
        let nameSize = TableTextScale.nameSize(scale: textScale)
        let chipScale = TableTextScale.chips(scale: textScale, spacing: spacing, diameter: diameter)

        for (seat, tag) in tags where !seats.contains(seat) {
            tag.removeFromParent()
            tags[seat] = nil
            tagText[seat] = nil
        }
        for (seat, tag) in linkTags where !seats.contains(seat) {
            tag.removeFromParent()
            linkTags[seat] = nil
        }
        for (seat, node) in cats where !seats.contains(seat) || node.diameter != diameter || node.textScale != chipScale
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
                node = CatNode(cat: SeatInfo.catIndex(view), ringColor: SeatInfo.ringColor(seat), diameter: diameter, textScale: chipScale)
                cats[seat] = node
                addChild(node)
            }
            node.position = CGPoint(x: slots[i].x, y: slots[i].y + layout.catLift)
            node.setScale(1)
            node.zPosition = CGFloat(i)
            node.setPresence(view?.kind == .bot ? nil : view?.presence)
            // A seat that forfeited (§5.13): dimmed, with "Forfeited" where a bad link would show.
            let out = game.isOut(seat)
            node.alpha = out ? 0.45 : 1  // fade-ok: CatNode is a FadeGroup
            let link = out
                ? (level: SignalGlyph.Level.lost, text: String(localized: "Forfeited", comment: "Under a player's name: they left the game"))
                : view?.kind == .human ? LinkWords.seat(view?.link) : nil
            node.setLink(out ? nil : link?.level)
            node.setBadges(bot: view?.kind == .bot, skip: game.pendingSkip[safe: seat] ?? false)
            node.slotWidth = spacing
            node.setCount(game.handCounts[safe: seat])
            if node.setPhase(PhaseMark.seat(seat, in: game)) { changes.movedOn.append(seat) }
            let active = game.status == .playing && game.turn == seat
            if node.setActive(active) { changes.turnedOn.append(seat) }

            let tag = tags[seat] ?? {
                let t = SKSpriteNode()
                t.name = "name"
                tags[seat] = t
                addChild(t)
                return t
            }()
            let text = (name: names[safe: seat] ?? "", width: tagWidth, size: nameSize)
            if tagText[seat]?.name != text.name || tagText[seat]?.width != text.width || tagText[seat]?.size != text.size
                || tag.texture == nil {
                tagText[seat] = text
                let texture = CardFaceFactory.shared.nameTag(text.name, maxWidth: text.width, active: false, size: text.size)
                tag.texture = texture
                tag.size = texture.size()
            }
            tag.position = CGPoint(x: slots[i].x, y: slots[i].y - layout.nameDrop)
            tag.zPosition = 20 + CGFloat(i)
            setLinkTag(
                seat, link, under: tag, width: tagWidth, size: ((layout.arrangement == .phone ? 13 : 15) * min(textScale, 1.25)).rounded(),
                z: 30 + CGFloat(i))
        }
        order = Array(seats.prefix(slots.count))
        return changes
    }

    private func setLinkTag(
        _ seat: Seat, _ link: (level: SignalGlyph.Level, text: String)?, under tag: SKSpriteNode,
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
        node.position = CGPoint(x: tag.position.x, y: tag.position.y - tag.size.height / 2 - node.size.height / 2 + 1)
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

    /// Touch / accessibility frame of a seat's cat, in this node's parent space.
    func frame(of seat: Seat) -> CGRect? {
        guard let node = cats[seat] else { return nil }
        let d = max(node.diameter, TableLayout.buttonHit)
        return CGRect(x: node.position.x - d / 2, y: node.position.y - d / 2, width: d, height: d)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
