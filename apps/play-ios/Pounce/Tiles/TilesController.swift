import PounceKit
import SpriteKit

/// The tile game while a TV shows the table (spec §3): the phone is a controller.
///
/// - On Cards, off turn, the stash is all there is (`TilesLayout.Controller.rackOnly`): large and
///   centred, its sort toggles over it, under the switch and the status line. It can still be
///   sorted and rearranged, as on the table.
/// - On this phone's turn, and on Table, the whole table under the switch (`.fullTable`): moving
///   what is already down needs it, so there is one way to play.
/// - Between the two the stash slides and grows or shrinks to its new place (`redraw`'s morph).
/// - On Cards, the draft goes to the TV as the player builds it (`store.aim`, throttled there):
///   the table only, never what is still in the stash.
extension TilesScene {
    /// How the layout shows the table at a TV (`tv`). A drag in progress keeps the layout it
    /// started on; the drop brings the new one.
    func controllerMode(_ model: TilesTableModel) -> TilesLayout.Controller? {
        let next: TilesLayout.Controller? = switch tv {
        case nil: nil
        case .table(let band): .fullTable(ControllerChrome(switchBand: band))
        case .cards(let chrome): Self.stashOnly(model) ? .rackOnly(chrome) : .fullTable(chrome)
        }
        if input.isDragging, let drawn = layout?.controller, let next, drawn.stashOnly != next.stashOnly { return drawn }
        return next
    }

    /// Cards shows just the stash while the game is on and none of this phone's seats is up (a
    /// phone whose seats are all out shows the table).
    static func stashOnly(_ model: TilesTableModel) -> Bool {
        model.isLive && !model.isMyTurn && !model.myActiveSeats.isEmpty
    }

    /// The table around the stash is up (always, but while the stash is alone on Cards).
    var tableUp: Bool { layout?.arrangement != .controller }

    /// The table as it will show on this phone's turn (Cards' full table), for drawing it hidden
    /// while the stash is alone: the same flow, nodes and textures, ready to show.
    func tableLayout(_ model: TilesTableModel, seat: Seat?, stash: TilesLayout) -> TilesLayout {
        TilesLayout(
            size: size, safeTop: safeInsets.top, safeBottom: safeInsets.bottom, opponents: model.barSeats(bottom: seat).count,
            rackCount: max(bandSeat(model).map(model.rackCount) ?? 0, rackShown.count + input.dragTiles.count),
            // The opening meter shows on the turn of a seat that hasn't opened.
            meter: seat.map { model.view.opened[safe: $0] == false } ?? false, controls: true,
            controller: .fullTable(stash.controller?.chrome ?? .standard))
    }

    /// Shows or hides the table around the stash (`tableGroup`). `animated` fades it in or out
    /// as one layer over the stash's slide, so the change reads as one move: the room's floor
    /// (`tableVeil`, one opaque sprite) fades off the table or onto it. Nothing shows through
    /// anything, and nothing is drawn offscreen (a flattened full-screen `FadeGroup` cost a long
    /// main-thread frame to set up on the turn's first frame).
    func setTable(up: Bool, animated: Bool) {
        guard up != tableUpTarget else { return }
        tableUpTarget = up
        director.cancelActions(on: tableVeil)
        let veil = tableVeil
        guard animated, !Effects.reduceMotion else {
            tableGroup.isHidden = !up
            veil.isHidden = true
            return
        }
        // From where a fade under way left it.
        if veil.isHidden { veil.alpha = tableGroup.isHidden ? 1 : 0 }
        veil.isHidden = false
        tableGroup.isHidden = false
        let fade = SKAction.fadeAlpha(to: up ? 0 : 1, duration: flight)  // fade-ok: the veil, one opaque sprite over the table
        Task { [weak self] in
            await self?.director.run(fade, on: veil)
            guard let self, self.tableUpTarget == up else { return }
            veil.isHidden = true
            self.tableGroup.isHidden = !up
        }
    }

    /// Where the stash's band starts: under the strip on a table, under the status line when the
    /// stash is all there is.
    var rackTop: CGFloat {
        guard let layout else { return 0 }
        return layout.arrangement == .controller ? layout.statusLine.minY : layout.strip.minY
    }

    /// Sends the TV this phone's draft while it builds its turn on Cards, and takes it back when
    /// there is none to show: the draft is back as it began (Reset, Undo), the turn went or was
    /// sent, the phone moved to Table, the TV left, or the table is going.
    func publishAim() {
        var next: (seat: Seat, table: [[TileID]])?
        if case .cards = tv, let seat = shownSeat, let draft, !sending, !draft.isUntouched, model?.canCompose(seat) == true {
            next = (seat, draft.submission)
        }
        if let next {
            if let aimed, aimed.seat == next.seat, aimed.table == next.table { return }
            if let aimed, aimed.seat != next.seat { store.aim(seat: aimed.seat, nil) }
            aimed = next
            store.aim(seat: next.seat, .table(next.table))
        } else {
            clearAim()
        }
    }

    /// Takes the draft back off the TV, if this phone sent one.
    func clearAim() {
        guard let seat = aimed?.seat else { return }
        aimed = nil
        store.aim(seat: seat, nil)
    }
}

extension TilesLayout.Controller {
    /// Just the stash (off turn on Cards).
    var stashOnly: Bool {
        if case .rackOnly = self { return true }
        return false
    }
}
