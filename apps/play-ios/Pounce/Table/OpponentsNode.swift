import PounceKit
import SpriteKit

/// The bar across the top: every other seat's cat in turn order after the bottom seat, with
/// its card count, presence pose and badges. The current player's ring glows.
@MainActor
final class OpponentsNode: SKNode {
    private var cats: [Seat: CatNode] = [:]
    /// Seat order left to right, as last laid out.
    private(set) var order: [Seat] = []

    func node(for seat: Seat) -> CatNode? { cats[seat] }

    /// Lays the bar out; returns the seats whose ring just became the current player's.
    @discardableResult
    func update(model: TableModel, bottom: Seat, layout: TableLayout) -> [Seat] {
        guard let game = model.game else {
            removeAllChildren()
            cats.removeAll()
            order = []
            return []
        }
        var turnedOn: [Seat] = []
        let seats = model.opponents(bottom: bottom)
        let slots = layout.opponentSlots
        let spacing = slots.count > 1 ? slots[1].x - slots[0].x : layout.size.width
        let diameter = min(72, spacing - 12, TableLayout.opponentsBarHeight - 18)

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
            node.position = slots[i]
            node.setScale(1)
            node.zPosition = CGFloat(i)
            node.setPresence(view?.kind == .bot ? nil : view?.presence)
            node.setBadges(
                bot: view?.kind == .bot,
                skip: game.pendingSkip[safe: seat] ?? false,
                laid: (game.laid[safe: seat] ?? nil) != nil)
            node.setCount(game.handCounts[safe: seat])
            if node.setActive(game.status == .playing && game.turn == seat) { turnedOn.append(seat) }
        }
        order = Array(seats.prefix(slots.count))
        return turnedOn
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
