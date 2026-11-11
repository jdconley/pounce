import PounceKit
import SpriteKit
import UIKit

/// Whose turn and which round the open tower was looked at in: either changing folds it.
struct TowerFoldKey: Equatable {
    let turn: Seat
    let round: Int
}

/// The cat tower is folded down to a tab by default (`TowerNode`) so the table stays clean.
/// A tap on the tab opens the whole tower over the table's left edge; a tap on the open tower
/// brings up the scoreboard (the paw menu's Scores does too) and folds it. Any other touch, a
/// new turn or a new round folds it again. Celebrations open it for their climbs and the
/// finale (Celebrations.swift); a fold never interrupts one.
extension TableScene {
    /// The tower's tap area: the tab, or the open tower with its panel.
    var towerFrame: CGRect {
        guard let layout else { return .zero }
        return tower.isOpen ? TowerNode.openFrame(layout) : layout.towerTab
    }

    /// A tap on the tower (`table.tower`): opens it, or, open, shows the scoreboard.
    func towerTapped() {
        Haptics.shared.tick()
        if tower.isOpen {
            showScoreboard()
            foldTower()
        } else {
            openTower()
        }
    }

    func openTower() {
        guard !tower.isOpen else { return }
        tower.setOpen(true, animated: true)
        invalidateAccessibility()
        publishOverlays()  // the coach's "tap again for scores" goes with the open tower
    }

    /// Folds the open tower, unless a celebration has it in the spotlight.
    func foldTower(animated: Bool = true) {
        guard tower.isOpen, !celebration.focused else { return }
        tower.setOpen(false, animated: animated)
        invalidateAccessibility()
        publishOverlays()
    }

    /// The scoreboard for the table as drawn.
    func showScoreboard() {
        guard let model else { return }
        onTower(model)
    }

    /// Folds the tower when the turn or the round moved on since it was opened.
    func foldOnTurnChange(_ game: GameView) {
        let key = TowerFoldKey(turn: game.turn, round: game.round)
        guard key != towerFoldKey else { return }
        if towerFoldKey != nil { foldTower() }
        #if DEBUG
        // `-show-tower` (screenshots): the table opens with the tower open.
        if towerFoldKey == nil, CommandLine.arguments.contains("-show-tower") { openTower() }
        #endif
        towerFoldKey = key
    }

    /// The tower's VoiceOver element. Folded: "Cat tower", activating opens it. Open: every
    /// seat's phase as its value, activating opens the scoreboard. "Scoreboard" either way.
    func towerAccessibilityItem(_ model: TableModel, _ game: GameView) -> TableAccessibility.Item {
        var value: String?
        if tower.isOpen {
            value = game.phase.indices.map { seat in
                String(
                    localized: "\(SeatInfo.name(model.room, seat)), phase \(min(game.phase[seat] + 1, 10))",
                    comment: "VoiceOver: one seat on the open cat tower, e.g. 'Mia, phase 3'")
            }.joined(separator: "; ")
        }
        let scores = UIAccessibilityCustomAction(
            name: String(localized: "Scoreboard", comment: "VoiceOver action on the cat tower: open the scores")
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.showScoreboard()
                self?.foldTower()
            }
            return true
        }
        return TableAccessibility.Item(
            id: "table.tower",
            label: String(localized: "Cat tower", comment: "VoiceOver: the cat tower; opens to show every player's phase"),
            value: value,
            hint: tower.isOpen
                ? String(localized: "Opens the scoreboard", comment: "VoiceOver hint: the open cat tower")
                : String(localized: "Shows every player's phase", comment: "VoiceOver hint: the folded cat tower"),
            frame: towerFrame, actions: [scores])
    }
}
