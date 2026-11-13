import PounceKit
import SpriteKit
import SwiftUI
import UIKit

/// What VoiceOver says about pieces and sets (tile game spec §3.3): "7, fish", "Yarn, wild,
/// standing for 6 mouse", "Row, fish, 4 to 7", "Match, nines, three toys".
enum TilesWords {
    static func suit(_ suit: TileSuit) -> String {
        switch suit {
        case .fish: String(localized: "fish", comment: "Tile game toy: the fish")
        case .mouse: String(localized: "mouse", comment: "Tile game toy: the mouse")
        case .feather: String(localized: "feather", comment: "Tile game toy: the feather")
        case .bell: String(localized: "bell", comment: "Tile game toy: the bell")
        }
    }

    static func piece(_ tile: TileID) -> String {
        guard case .number(let value, let suit)? = Tile.decode(tile) else {
            return String(localized: "Yarn, wild", comment: "VoiceOver: the wild piece")
        }
        return String(localized: "\(value), \(self.suit(suit))", comment: "VoiceOver: a piece, its number then its toy")
    }

    /// A piece where it sits in a set: a Yarn says what it stands for.
    static func piece(_ tile: TileID, standing: TileStanding?) -> String {
        guard Tile.isYarn(tile), let standing else { return piece(tile) }
        if let suit = standing.suit {
            return String(
                localized: "Yarn, wild, standing for \(standing.value) \(self.suit(suit))",
                comment: "VoiceOver: the wild piece and the piece it stands for")
        }
        return String(localized: "Yarn, wild, standing for \(standing.value)", comment: "VoiceOver: the wild piece and the number it stands for")
    }

    private static let plurals = [
        "ones", "twos", "threes", "fours", "fives", "sixes", "sevens", "eights", "nines", "tens", "elevens", "twelves", "thirteens",
    ]

    static func set(_ tiles: [TileID]) -> String {
        switch TilesRules.readSet(tiles) {
        case .run(let suit, let start, let end, _):
            return String(localized: "Row, \(self.suit(suit)), \(start) to \(end)", comment: "VoiceOver: a run, its toy and its first and last numbers")
        case .group(let value, _):
            let name = plurals.indices.contains(value - 1) ? plurals[value - 1] : String(value)
            return String(localized: "Match, \(name), \(tiles.count) toys", comment: "VoiceOver: a group, its number and how many pieces")
        case nil:
            let pieces = tiles.map(piece).formatted(.list(type: .and))
            return String(localized: "Not a set yet: \(pieces)", comment: "VoiceOver: pieces that aren't a valid set")
        }
    }

    static func problem(_ problem: TilesDraft.Problem) -> String {
        switch problem {
        case .tooShort: String(localized: "needs three toys", comment: "VoiceOver: why a set isn't valid")
        case .mixedSuits: String(localized: "mixes toys and numbers", comment: "VoiceOver: why a set isn't valid")
        case .suitTwice: String(localized: "has a toy twice", comment: "VoiceOver: why a set isn't valid")
        case .gap: String(localized: "has a gap", comment: "VoiceOver: why a set isn't valid")
        }
    }

    static func turnButton(_ button: TilesDraft.TurnButton?, sending: Bool) -> (label: String, hint: String?) {
        switch button {
        case .draw:
            (String(localized: "Draw a toy", comment: "VoiceOver: the turn button"),
             String(localized: "Takes one toy from the toy box and ends your turn", comment: "VoiceOver hint"))
        case .pass:
            (String(localized: "Pass", comment: "VoiceOver: the turn button"),
             String(localized: "The toy box is empty. Ends your turn.", comment: "VoiceOver hint"))
        case .play:
            (String(localized: "Play", comment: "VoiceOver: the turn button"),
             String(localized: "Sends your turn", comment: "VoiceOver hint"))
        case .blocked(.brokenSet):
            (String(localized: "Play, not ready", comment: "VoiceOver: the turn button, disabled"),
             String(localized: "A set on the rug isn't finished. Double tap to go to it.", comment: "VoiceOver hint"))
        case .blocked(.nothingPlaced):
            (String(localized: "Play, not ready", comment: "VoiceOver: the turn button, disabled"),
             String(localized: "Add a toy from your stash first", comment: "VoiceOver hint"))
        case .blocked(.openingTooLow(let points)):
            (String(localized: "Play, not ready", comment: "VoiceOver: the turn button, disabled"),
             String(localized: "Your first sets add up to \(points). They need 30.", comment: "VoiceOver hint"))
        case .blocked:
            (String(localized: "Play, not ready", comment: "VoiceOver: the turn button, disabled"), nil)
        case nil:
            (sending
                ? String(localized: "Turn sent", comment: "VoiceOver: the turn button after sending")
                : String(localized: "Not your turn", comment: "VoiceOver: the turn button off turn"), nil)
        }
    }
}

extension TilesScene {
    /// The table's elements for VoiceOver and the UI tests: the top bar, the toy box, every set,
    /// the action strip and the stash, with custom actions for every move a drag can make
    /// (tile game spec §5.11).
    func accessibilityElements(in view: SKView) -> [UIAccessibilityElement] {
        if let cached = accessibilityCache, cached.version == accessibilityVersion { return cached.elements }
        let elements = TableAccessibility.elements(accessibilityItems(), scene: self, view: view)
        accessibilityCache = (accessibilityVersion, elements)
        return elements
    }

    private func action(_ name: String, _ run: @escaping @MainActor () -> Bool) -> UIAccessibilityCustomAction {
        UIAccessibilityCustomAction(name: name) { _ in MainActor.assumeIsolated { run() } }
    }

    private func accessibilityItems() -> [TableAccessibility.Item] {
        guard let model, let layout, let flow else { return [] }
        typealias Item = TableAccessibility.Item
        var items: [Item] = []
        let composing = draft != nil && !sending
        func square(_ center: CGPoint, _ side: CGFloat = TilesLayout.buttonHit) -> CGRect {
            CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }

        items.append(Item(id: "table.menu", label: String(localized: "Menu", comment: "VoiceOver: the table's paw menu"), frame: square(layout.menuButton)))
        for seat in opponents.order {
            guard let frame = opponents.frame(of: seat) else { continue }
            let marks = model.marks(seat)
            var parts = [SeatInfo.name(model.room, seat), String(localized: "\(marks.count) toys", comment: "VoiceOver: pieces left on a player's rack")]
            if marks.forfeited {
                parts.append(String(localized: "forfeited", comment: "VoiceOver: a player who left the game"))
            } else {
                if marks.notOpened { parts.append(String(localized: "hasn't opened", comment: "VoiceOver: a player yet to make an opening play")) }
                if marks.passed { parts.append(String(localized: "passed", comment: "VoiceOver: a player who passed")) }
                if marks.onTheMove { parts.append(String(localized: "their turn", comment: "VoiceOver: the player to move")) }
                if marks.bot { parts.append(String(localized: "bot", comment: "VoiceOver: a bot player")) }
            }
            items.append(Item(id: "tiles.seat.\(seat)", label: parts.joined(separator: ", "), frame: frame, traits: .staticText))
        }
        items.append(Item(
            id: "tiles.pool",
            label: String(localized: "Toy box, \(model.view.poolCount) toys", comment: "VoiceOver: the pool and its count"),
            frame: layout.pool, traits: .staticText))
        if !recap.isEmpty, !recapButton.isHidden {
            items.append(Item(
                id: "tiles.recap", label: String(localized: "What changed", comment: "VoiceOver: replay what others placed since my turn"),
                frame: square(recapButton.position)))
        }

        // The rug's sets, top to bottom. Off screen ones (scrolled away) keep their place in the
        // order, clipped to the rug.
        for (index, set) in shown.enumerated() where flow.sets.indices.contains(index) {
            let box = flow.sets[index].frame
            let origin = rugContent.convert(CGPoint(x: box.minX, y: -box.maxY), to: self)
            let frame = CGRect(origin: origin, size: box.size).intersection(layout.rugArt)
            guard !frame.isNull, frame.height > 4 else { continue }
            var label = TilesWords.set(set.tiles)
            var hint: String?
            var actions: [UIAccessibilityCustomAction] = []
            if let draft {
                switch draft.state(of: set.id) {
                case .unchanged:
                    if draft.isLocked(set.id) { label += ", " + String(localized: "locked until you open", comment: "VoiceOver: a set that can't be changed before the opening play") }
                case .changed:
                    label += ", " + String(localized: "changed this turn", comment: "VoiceOver: a valid set changed this turn")
                case .broken(let problem):
                    label += ", " + TilesWords.problem(problem)
                }
                if composing {
                    let id = set.id
                    if !selection.isEmpty {
                        hint = String(localized: "Double tap to add the toys you picked up", comment: "VoiceOver hint on a set")
                    } else if !draft.isLocked(id), tricksAllowed {
                        hint = String(localized: "Double tap to open it", comment: "VoiceOver hint on a set")
                    }
                    for tile in set.tiles where draft.isPlaced(tile) {
                        actions.append(action(String(localized: "Take back \(TilesWords.piece(tile))", comment: "VoiceOver action: return a piece placed this turn")) { [weak self] in
                            self?.apply([tile], to: .rack) ?? false
                        })
                    }
                }
            }
            items.append(Item(id: "tiles.set.\(index)", label: label, hint: hint, frame: frame, actions: actions))
        }
        if composing {
            let box = flow.newSlot
            let origin = rugContent.convert(CGPoint(x: box.minX, y: -box.maxY), to: self)
            let frame = CGRect(origin: origin, size: box.size).intersection(layout.rugArt)
            if !frame.isNull, frame.height > 4 {
                items.append(Item(
                    id: "tiles.newset", label: String(localized: "Start a new set", comment: "VoiceOver: the empty slot for a new set"),
                    hint: selection.isEmpty ? String(localized: "Pick up toys from your stash first", comment: "VoiceOver hint") : nil,
                    frame: frame.insetBy(dx: -6, dy: -4)))
            }
        }

        // The loupe, when a set is open.
        if loupe != nil {
            for slot in loupeSlots {
                let standing = shown.first { $0.id == loupe }.flatMap { set in
                    set.tiles.firstIndex(of: slot.tile).flatMap { TilesRules.standings(set.tiles)?[$0] }
                }
                let tile = slot.tile
                var actions: [UIAccessibilityCustomAction] = []
                if draft?.isPlaced(tile) == true {
                    actions.append(action(String(localized: "Take back", comment: "VoiceOver action: return a piece placed this turn")) { [weak self] in
                        self?.apply([tile], to: .rack) ?? false
                    })
                }
                actions.append(action(String(localized: "Start a new set", comment: "VoiceOver action: a piece starts a set of its own")) { [weak self] in
                    self?.apply([tile], to: .newSet()) ?? false
                })
                items.append(Item(
                    id: "tiles.loupe.\(tile)", label: TilesWords.piece(tile, standing: standing),
                    value: selection.contains(tile) ? String(localized: "picked up", comment: "VoiceOver: a selected piece") : nil,
                    frame: slot.frame, actions: actions))
            }
            for gap in loupeGapFrames {
                items.append(Item(id: "tiles.loupe.gap.\(gap.index)", label: String(localized: "Split here", comment: "VoiceOver: break a set in two"), frame: gap.frame))
            }
            items.append(Item(id: "tiles.loupe.handle", label: String(localized: "Pick up the whole set", comment: "VoiceOver: the loupe's handle"), frame: square(loupeHandle.position)))
            items.append(Item(id: "tiles.loupe.close", label: String(localized: "Close", comment: "VoiceOver: close the opened set"), frame: square(loupeClose.position)))
        }

        // The action strip.
        if !turnPill.isHidden {
            if let meter = draft?.openingMeter, layout.meter != .zero {
                items.append(Item(
                    id: "tiles.meter",
                    label: String(localized: "Opening: \(meter.points) of \(meter.goal)", comment: "VoiceOver: the opening meter"),
                    frame: layout.meter.insetBy(dx: -20, dy: -4), traits: .staticText))
            }
            items.append(Item(id: "tiles.undo", label: String(localized: "Undo", comment: "VoiceOver: undo the last move"), frame: layout.undo,
                              traits: composing && draft?.canUndo == true ? .button : [.button, .notEnabled]))
            items.append(Item(id: "tiles.reset", label: String(localized: "Reset the turn", comment: "VoiceOver: put everything back"), frame: layout.reset,
                              traits: composing && draft?.isUntouched == false ? .button : [.button, .notEnabled]))
            let words = TilesWords.turnButton(turnButton, sending: sending)
            items.append(Item(id: "tiles.turn", label: words.label, hint: words.hint, frame: layout.turn))
            let sort = shownSeat.flatMap { orders[$0]?.sort }
            items.append(Item(id: "tiles.sort.number", label: String(localized: "Sort by number", comment: "VoiceOver: a rack sort toggle"), frame: layout.sortNumber,
                              traits: sort == .number ? [.button, .selected] : .button))
            items.append(Item(id: "tiles.sort.toy", label: String(localized: "Sort by toy", comment: "VoiceOver: a rack sort toggle"), frame: layout.sortToy,
                              traits: sort == .toy ? [.button, .selected] : .button))
            if easy {
                items.append(Item(id: "tiles.hint", label: String(localized: "Show me", comment: "VoiceOver: the hint button"), frame: layout.tidy))
            }
        }

        // The stash.
        for (i, tile) in rackShown.enumerated() {
            guard let node = pieces[tile], node.parent === rackLayer else { continue }
            let frame = CGRect(
                x: node.home.x - rackScroll - layout.rackPiece.width / 2, y: node.home.y - layout.rackPiece.height / 2,
                width: layout.rackPiece.width, height: layout.rackPiece.height)
            var actions: [UIAccessibilityCustomAction] = []
            if composing, let draft {
                actions.append(action(String(localized: "Start a new set", comment: "VoiceOver action: a piece starts a set of its own")) { [weak self] in
                    self?.apply([tile], to: .newSet()) ?? false
                })
                // Every set this piece would fit, nearest first; then any set at all.
                let fitting = draft.shownSets.filter { !draft.isLocked($0.id) && TilesHints.fits([tile], in: $0.tiles) }
                for set in fitting.prefix(6) {
                    let id = set.id
                    actions.append(action(String(localized: "Add to \(TilesWords.set(set.tiles))", comment: "VoiceOver action: add a piece to a set")) { [weak self] in
                        self?.apply([tile], to: .set(id)) ?? false
                    })
                }
            }
            items.append(Item(
                id: "tiles.rack.\(i)", label: TilesWords.piece(tile),
                value: selection.contains(tile) ? String(localized: "picked up", comment: "VoiceOver: a selected piece") : nil,
                hint: composing ? String(localized: "Double tap to pick it up, then double tap a set", comment: "VoiceOver hint on a rack piece") : nil,
                frame: frame, actions: actions))
        }

        #if DEBUG
        items.append(Item(
            id: "tiles.debug", label: "tiles debug", frame: CGRect(x: 0, y: size.height - 2, width: 2, height: 2), traits: .staticText,
            live: { [weak self] in self?.debugSummary }))
        // The last drag's timings (`DragPerf`), for the performance check.
        items.append(Item(
            id: "tiles.perf", label: "tiles perf", frame: CGRect(x: 2, y: size.height - 2, width: 2, height: 2), traits: .staticText,
            live: { [weak self] in self?.probe.perf }))
        #endif
        return items
    }

    #if DEBUG
    /// What the UI tests read back (`tiles.debug`).
    var debugSummary: String {
        let button: String
        switch turnButton {
        case .draw: button = "draw"
        case .pass: button = "pass"
        case .play: button = "play"
        case .blocked(.brokenSet): button = "blocked-set"
        case .blocked(.nothingPlaced): button = "blocked-nothing"
        case .blocked(.openingTooLow): button = "blocked-opening"
        case .blocked: button = "blocked"
        case nil: button = sending ? "sent" : "none"
        }
        let piece = flow.map { Int($0.pieceSize.width) } ?? 0
        return [
            "turn=\(button)", "sets=\(shown.count)", "rack=\(rackShown.count)", "placed=\(draft?.placed.count ?? 0)",
            "selected=\(selection.count)", "loupe=\(loupe.map(String.init) ?? "-")", "piece=\(piece)",
            "scrolls=\(maxScroll > 0)", "points=\(draft?.newPoints ?? 0)", "sent=\(probe.sent)", "refused=\(probe.refused)",
            "sort=\(shownSeat.flatMap { orders[$0]?.sort?.rawValue } ?? "free")", "shown=\(shownSeat.map(String.init) ?? "-")",
        ].joined(separator: " ")
    }
    #endif
}
