import PounceKit
import SpriteKit
import SwiftUI

/// Everything a touch can be doing on the tile game's table.
struct TilesInputState {
    /// Where pieces being dragged (or tapped across) would land.
    enum Target: Equatable {
        case set(Int)
        case newSet
        case rack
    }

    enum Origin { case rack, rug, loupe }

    enum Control: Equatable {
        case undo, reset, sortNumber, sortToy, tidy, turn, menu, recap, loupeClose
    }

    /// What the finger came down on.
    enum What: Equatable {
        case control(Control)
        case rackPiece(TileID)
        case loupePiece(TileID)
        case loupeGap(Int)
        case loupeHandle
        case loupePanel
        case rugSet(Int, piece: TileID?)
        case newSlot
        case rug
        case rackArea
        case opponent(Seat)
        case nothing
    }

    enum Phase: Equatable { case idle, press, drag, scrollRug, scrollRack }

    var phase = Phase.idle
    var what = What.nothing
    var start = CGPoint.zero
    var last = CGPoint.zero
    var dragTiles: [TileID] = []
    var dragNodes: [TilePieceNode] = []
    var origin = Origin.rack
    var target: Target?
    var targetRefused = false
    var rackSlot: Int?
    var side: TilesDraft.Side?
    /// The control held down (drawn pressed in).
    var pressed: Control?
    /// A press and hold in progress (Draw, Pass, Reset) and when it began.
    var hold: Control?
    var holdStart: TimeInterval?
    var lastPill: TilePieceFactory.Pill?
    /// Sets a refusal just pointed at.
    var wiggling: Set<Int> = []
    var follow = DragFollow(duration: 0.1)
    var lastStep: TimeInterval?
    /// The rug piece width a pinch started from.
    var pinchBase: CGFloat = 30

    var isDragging: Bool { phase == .drag }
}

extension TilesScene {
    private static let slop: CGFloat = 9
    /// Draw, Pass and Reset end or throw away a turn, so each takes a short hold (spec §5.5).
    static let holdSeconds = 0.4

    private var composing: Bool { draft != nil && !sending }

    // MARK: hit testing

    private func hit(_ point: CGPoint) -> TilesInputState.What {
        guard let layout, let model else { return .nothing }
        let hitSide = TilesLayout.buttonHit
        func near(_ node: SKNode, _ side: CGFloat = hitSide) -> Bool {
            !node.isHidden && abs(point.x - node.position.x) <= side / 2 && abs(point.y - node.position.y) <= side / 2
        }
        if near(menuButton) { return .control(.menu) }
        if loupe != nil {
            if near(loupeClose) { return .control(.loupeClose) }
            if near(loupeHandle) { return .loupeHandle }
            if let slot = loupeSlots.first(where: { $0.frame.contains(point) }) { return .loupePiece(slot.tile) }
            if let gap = loupeGapFrames.first(where: { $0.frame.contains(point) }) { return .loupeGap(gap.index) }
            if loupeFrame.contains(point) { return .loupePanel }
        }
        if !turnPill.isHidden {
            if layout.turn.insetBy(dx: -4, dy: -6).contains(point) { return .control(.turn) }
            if layout.undo.contains(point) { return .control(.undo) }
            if layout.reset.contains(point) { return .control(.reset) }
            if layout.sortNumber.contains(point) { return .control(.sortNumber) }
            if layout.sortToy.contains(point) { return .control(.sortToy) }
            if layout.tidy.contains(point) { return .control(.tidy) }
        }
        if shownSeat != nil, layout.rack.height > 0, point.y < layout.strip.minY {
            let local = CGPoint(x: point.x + rackScroll, y: point.y)
            // Lifted pieces first, then the nearest piece under the finger.
            var best: (TileID, CGFloat)?
            for tile in rackShown {
                guard let node = pieces[tile] else { continue }
                let dx = abs(local.x - node.position.x), dy = abs(local.y - node.position.y)
                guard dx <= layout.rackPiece.width / 2 + 3, dy <= layout.rackPiece.height / 2 + 6 else { continue }
                let d = dx + dy
                if best == nil || d < best!.1 { best = (tile, d) }
            }
            if let best { return .rackPiece(best.0) }
            return .rackArea
        }
        if near(recapButton) { return .control(.recap) }
        if layout.rugArt.contains(point), let flow {
            let content = rugPoint(point)
            if let index = flow.set(at: content, slop: 5), shown.indices.contains(index) {
                let set = shown[index]
                // The piece nearest the finger, for picking a placed piece straight off the rug.
                let centers = flow.sets[index].pieces
                let nearest = centers.indices.min { abs(centers[$0].x - content.x) < abs(centers[$1].x - content.x) }
                return .rugSet(set.id, piece: nearest.flatMap { set.tiles.indices.contains($0) ? set.tiles[$0] : nil })
            }
            if composing, flow.newSlot.insetBy(dx: -6, dy: -6).contains(content) { return .newSlot }
            return .rug
        }
        for seat in opponents.order {
            if let frame = opponents.frame(of: seat), frame.contains(point), model.room.seats.indices.contains(seat) { return .opponent(seat) }
        }
        return .nothing
    }

    /// A scene point in the rug's content space (y down from the rug's top, scroll included).
    func rugPoint(_ point: CGPoint) -> CGPoint {
        guard let layout else { return .zero }
        return CGPoint(x: point.x - layout.rug.minX, y: layout.rug.maxY + scroll - point.y)
    }

    // MARK: touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard input.phase == .idle, let touch = touches.first else { return }
        director.touchBegan()
        let point = touch.location(in: self)
        input.phase = .press
        input.start = point
        input.last = point
        input.what = hit(point)
        if case .control(let control) = input.what {
            input.pressed = control
            let holds = control == .reset ? (composing && draft?.isUntouched == false)
                : control == .turn ? (turnButton == .draw || turnButton == .pass) : false
            if holds {
                input.hold = control
                input.holdStart = nil
            }
            redraw()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        #if DEBUG
        let began = CACurrentMediaTime()
        defer { if input.isDragging { dragPerf.move(CACurrentMediaTime() - began) } }
        #endif
        let moved = hypot(point.x - input.start.x, point.y - input.start.y)
        switch input.phase {
        case .press where moved > Self.slop:
            beginMove(at: point)
        case .drag:
            drag(to: point)
        case .scrollRug:
            scroll = min(max(scroll + (point.y - input.last.y), 0), maxScroll)
            if let layout { rugContent.position = CGPoint(x: layout.rug.minX, y: layout.rug.maxY + scroll) }
            accessibilityVersion += 1
        case .scrollRack:
            guard let layout else { break }
            rackScroll = min(max(rackScroll - (point.x - input.last.x), 0), layout.rackScrollLimit(count: rackShown.count))
            rackLayer.position = CGPoint(x: -rackScroll, y: 0)
        default:
            break
        }
        input.last = point
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let phase = input.phase
        let what = input.what
        let held = input.hold
        input.phase = .idle
        input.pressed = nil
        input.hold = nil
        input.holdStart = nil
        holdFill.isHidden = true
        resetButton.setScale(1)
        director.touchEnded()
        switch phase {
        case .press:
            // A hold let go early does nothing but say how it works.
            if let held, UIAccessibility.isVoiceOverRunning {
                // VoiceOver's activation is deliberate already: no hold on top of it.
                activate(held)
            } else if held != nil {
                holdHint(held == .reset ? resetButton : turnPill)
                redraw()
            } else {
                tap(what, at: point)
            }
        case .drag:
            drop(at: point)
        default:
            redraw()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasDragging = input.isDragging
        input.phase = .idle
        input.pressed = nil
        input.hold = nil
        input.holdStart = nil
        holdFill.isHidden = true
        resetButton.setScale(1)
        director.touchEnded()
        if wasDragging { endDrag() }
        redraw(animated: wasDragging)
    }

    /// The finger has moved far enough to mean something: a drag, or a scroll.
    private func beginMove(at point: CGPoint) {
        input.pressed = nil
        input.hold = nil
        holdFill.isHidden = true
        resetButton.setScale(1)
        guard let layout else { return }
        switch input.what {
        case .rackPiece(let tile):
            let dx = abs(point.x - input.start.x), dy = abs(point.y - input.start.y)
            if layout.rackScrollLimit(count: rackShown.count) > 0, dx > dy * 1.6 {
                input.phase = .scrollRack
            } else if !sending {
                let together = selection.contains(tile) ? rackShown.filter(selection.contains) : [tile]
                beginDrag(together, lead: tile, origin: .rack, at: point)
            }
        case .loupePiece(let tile) where composing:
            let inLoupe = loupeSlots.map(\.tile)
            let together = selection.contains(tile) ? inLoupe.filter(selection.contains) : [tile]
            beginDrag(together, lead: tile, origin: .loupe, at: point)
        case .loupeHandle where composing && tricksAllowed:
            let all = loupeSlots.map(\.tile)
            if let lead = all.first { beginDrag(all, lead: lead, origin: .loupe, at: point) }
        case .rugSet(_, let piece):
            // A piece placed this turn comes straight off the rug; anything else is opened first.
            if composing, let piece, draft?.isPlaced(piece) == true, loupe == nil {
                beginDrag([piece], lead: piece, origin: .rug, at: point)
            } else if maxScroll > 0 {
                input.phase = .scrollRug
            }
        case .rug, .newSlot:
            if maxScroll > 0 { input.phase = .scrollRug }
        case .rackArea:
            if layout.rackScrollLimit(count: rackShown.count) > 0 { input.phase = .scrollRack }
        default:
            break
        }
        redraw()
    }

    // MARK: dragging

    private func beginDrag(_ tiles: [TileID], lead: TileID, origin: TilesInputState.Origin, at point: CGPoint) {
        guard let layout, !tiles.isEmpty else { return }
        #if DEBUG
        dragPerf.begin()
        #endif
        input.phase = .drag
        input.dragTiles = tiles
        input.origin = origin
        input.target = nil
        input.rackSlot = nil
        input.follow = DragFollow(duration: 0.1)
        hint = nil
        let dragLayer = layer(.drag)
        input.dragNodes = tiles.enumerated().map { i, tile in
            let node = piece(tile, in: dragLayer, size: layout.rackPiece, face: .large, at: point)
            director.cancelActions(on: node)
            node.show(size: layout.rackPiece, face: .large, standing: nil)
            node.setRing(nil)
            node.zPosition = CGFloat(i)
            node.setScale(1.12)
            node.alpha = 1
            return node
        }
        // Rack pieces that leave close the gap; the rest keep their places until the drop.
        if origin != .rack { selection = [] }
        selection.removeAll(where: tiles.contains)
        Haptics.shared.tick()
        Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
        drag(to: point)
        redraw(animated: true)
    }

    /// Where the dragged pieces are drawn for a finger at `point`: the lead piece just above the
    /// finger (so the finger never hides it), the others fanned to its right.
    private func dragPosition(_ index: Int, finger: CGPoint) -> CGPoint {
        guard let layout else { return finger }
        return CGPoint(
            x: finger.x + CGFloat(index) * layout.rackPiece.width * 0.62,
            y: finger.y + layout.rackPiece.height * 0.62)
    }

    private func drag(to point: CGPoint) {
        input.last = point
        input.follow.move(to: point, jump: false, at: CACurrentMediaTime())
        for (i, node) in input.dragNodes.enumerated() { node.position = dragPosition(i, finger: point) }
        #if DEBUG
        dragPerf.intended = input.dragNodes.first?.position
        #endif
        aim(at: point)
    }

    /// Works out what the finger is over. The table is only laid out again when that changes.
    private func aim(at point: CGPoint) {
        guard let layout, let flow else { return }
        var target: TilesInputState.Target?
        var refused = false
        var slot: Int?
        var side: TilesDraft.Side?
        if shownSeat != nil, layout.rack.height > 0, point.y < layout.strip.minY + 6 {
            target = .rack
            slot = layout.rackSlot(at: CGPoint(x: point.x + rackScroll, y: point.y), count: rackShown.count)
            // A piece that was on the rug when the turn began can't come to the stash.
            if input.origin != .rack, let draft { refused = input.dragTiles.contains { !draft.isPlaced($0) } }
        } else if composing, layout.rugArt.insetBy(dx: 0, dy: -10).contains(point) {
            let content = rugPoint(point)
            if let index = flow.set(at: content, slop: 12), shown.indices.contains(index) {
                let id = shown[index].id
                target = .set(id)
                refused = draft?.isLocked(id) ?? false
                side = content.x < flow.sets[index].frame.midX ? .start : .end
            } else {
                target = .newSet
            }
        }
        input.side = side
        guard target != input.target || slot != input.rackSlot || refused != input.targetRefused else { return }
        let changedTarget = target != input.target
        input.target = target
        input.rackSlot = slot
        input.targetRefused = refused
        if changedTarget, target != nil { Haptics.shared.tick() }
        redraw(animated: true)
    }

    private func endDrag() {
        input.dragTiles = []
        input.dragNodes = []
        input.target = nil
        input.rackSlot = nil
        input.targetRefused = false
        #if DEBUG
        probe.perf = dragPerf.summary
        print(dragPerf.summary)
        #endif
    }

    private func drop(at point: CGPoint) {
        let tiles = input.dragTiles
        let target = input.target
        let slot = input.rackSlot
        let side = input.side
        let origin = input.origin
        let nodes = input.dragNodes
        endDrag()
        var landed = false
        switch target {
        case .set(let id):
            landed = apply(tiles, to: .set(id, toward: side))
        case .newSet:
            landed = apply(tiles, to: .newSet())
        case .rack:
            guard let seat = shownSeat else { break }
            if origin == .rack {
                orders[seat]?.move(tiles, toSlot: slot ?? rackShown.count, shown: rackShown)
                landed = true
                Haptics.shared.drop()
                saveDraft()
                redraw(animated: true)
            } else if apply(tiles, to: .rack) {
                orders[seat]?.move(tiles, toSlot: slot ?? rackShown.count, shown: rackShown.filter { !tiles.contains($0) })
                landed = true
                redraw(animated: true)
            }
        case nil:
            break
        }
        if !landed {
            redraw(animated: true)
            for node in nodes { nope(node) }
        } else if !Effects.reduceMotion {
            // The drop: a small squash as each piece lands.
            let director = director
            for tile in tiles {
                guard let node = pieces[tile] else { continue }
                let rest = node.xScale
                let squash = SKAction.sequence([
                    .wait(forDuration: 0.16), .scale(to: rest * 1.16, duration: 0.07).eased(.easeOut),
                    .scale(to: rest, duration: 0.12).eased(.easeInEaseOut),
                ])
                Task { await director.run(squash, on: node, decorative: true) }
            }
        }
    }

    // MARK: changing the draft

    /// One move of the draft with its sound, its feel and its words. False when it didn't go.
    @discardableResult
    func apply(_ tiles: [TileID], to destination: TilesDraft.Destination) -> Bool {
        guard var next = draft, !sending, !tiles.isEmpty else { return false }
        // Easy mode: a piece that can't join a set goes back instead of leaving it broken.
        if easy, !tricks, case .set(let id, _) = destination, let set = next.set(id) {
            let staying = set.tiles.filter { !tiles.contains($0) }
            if !staying.isEmpty, !TilesHints.fits(tiles, in: staying) {
                selection = []
                redraw(animated: true)
                if let node = setNodes[id] { nope(node) }
                return false
            }
        }
        switch next.move(tiles, to: destination) {
        case .success:
            commit(next)
            Sound.shared.play(ArtName.Sound.sfxThud, volume: 0.45)
            Haptics.shared.drop()
            announceMove(tiles, destination)
            return true
        case .failure(.notOpened):
            shakeMeter()
        case .failure(.tablePiece):
            Sound.shared.play(ArtName.Sound.sfxNope, volume: 0.6)
            Haptics.shared.thump()
        case .failure:
            break
        }
        return false
    }

    /// Takes a changed draft as the table's, keeps it on the device and draws it.
    func commit(_ next: TilesDraft) {
        let was = draft?.turnButton
        draft = next
        selection = []
        hint = nil
        input.wiggling = []
        if let open = loupe, next.set(open) == nil { loupe = nil }
        saveDraft()
        redraw(animated: true)
        if next.turnButton == .play, was != .play {
            Sound.shared.play(ArtName.Sound.sfxSparkle, volume: 0.5)
            Haptics.shared.success()
        }
    }

    private func announceMove(_ tiles: [TileID], _ destination: TilesDraft.Destination) {
        guard UIAccessibility.isVoiceOverRunning, let draft else { return }
        let what = tiles.map(TilesWords.piece).formatted(.list(type: .and))
        switch destination {
        case .rack:
            onAnnounce(String(localized: "\(what) back in your stash", comment: "VoiceOver: pieces returned to the rack"))
        case .set(let id, _):
            let set = draft.set(id).map { TilesWords.set($0.tiles) } ?? ""
            onAnnounce(String(localized: "\(what) added. \(set)", comment: "VoiceOver: pieces added to a set, then the set"))
        case .newSet:
            let set = tiles.first.flatMap(draft.setID(holding:)).flatMap(draft.set).map { TilesWords.set($0.tiles) } ?? ""
            onAnnounce(String(localized: "New set. \(set)", comment: "VoiceOver: pieces made a new set, then the set"))
        }
    }

    // MARK: taps

    private func tap(_ what: TilesInputState.What, at point: CGPoint) {
        switch what {
        case .control(let control):
            activate(control)
        case .rackPiece(let tile):
            guard composing else {
                redraw()
                return
            }
            // A piece picked up from the rug or the loupe is put down first.
            selection.removeAll { !rackShown.contains($0) }
            if let i = selection.firstIndex(of: tile) { selection.remove(at: i) } else { selection.append(tile) }
            hint = nil
            Haptics.shared.tick()
            redraw(animated: true)
        case .loupePiece(let tile):
            guard composing else { return }
            if selection == [tile], draft?.isPlaced(tile) == true {
                // Tapped twice: a piece placed this turn goes back to the stash.
                apply([tile], to: .rack)
                return
            }
            let inLoupe = loupeSlots.map(\.tile)
            selection.removeAll { !inLoupe.contains($0) }
            if let i = selection.firstIndex(of: tile) { selection.remove(at: i) } else { selection.append(tile) }
            Haptics.shared.tick()
            redraw(animated: true)
        case .loupeGap(let index):
            splitLoupe(before: index)
        case .loupeHandle:
            guard composing, tricksAllowed else { return }
            let all = loupeSlots.map(\.tile)
            selection = Set(selection) == Set(all) ? [] : all
            Haptics.shared.tick()
            redraw(animated: true)
        case .loupePanel:
            selection = []
            redraw(animated: true)
        case .rugSet(let id, let piece):
            tapSet(id, piece: piece)
        case .newSlot, .rug:
            if composing, !selection.isEmpty {
                apply(selection, to: .newSet())
            } else if loupe != nil {
                closeLoupe()
            } else {
                onTableTap()
            }
        case .rackArea:
            guard !selection.isEmpty else { return }
            // Pieces picked up off the rug go back to the stash; stash pieces are put down.
            if selection.contains(where: { !rackShown.contains($0) }) {
                apply(selection, to: .rack)
            } else {
                selection = []
                redraw(animated: true)
            }
        case .opponent, .nothing:
            if loupe != nil { closeLoupe() } else { onTableTap() }
        }
    }

    private func tapSet(_ id: Int, piece: TileID?) {
        guard composing, let draft else {
            onTableTap()
            return
        }
        if !selection.isEmpty {
            // The whole set is the target: the pieces go where they belong.
            if selection == piece.map({ [$0] }), draft.isPlaced(selection[0]) {
                apply(selection, to: .rack)  // tapped twice
            } else if !apply(selection, to: .set(id)), let node = setNodes[id] {
                nope(node)
            }
            return
        }
        if draft.isLocked(id) {
            // Before opening the rug's sets don't open. The meter says why.
            if let node = setNodes[id] { nope(node) }
            shakeMeter()
            return
        }
        if loupe != nil, loupe != id {
            loupe = nil
        }
        if tricksAllowed {
            openLoupe(id)
        } else if let piece, draft.isPlaced(piece) {
            // Easy mode without tricks: a placed piece is picked up where it sits.
            selection = [piece]
            Haptics.shared.tick()
            redraw(animated: true)
        } else if let node = setNodes[id] {
            nope(node)
        }
    }

    private func splitLoupe(before index: Int) {
        guard composing, tricksAllowed, let id = loupe, var next = draft else { return }
        guard case .success = next.split(id, before: index) else { return }
        Sound.shared.play(ArtName.Sound.sfxBat, volume: 0.5)
        Haptics.shared.drop()
        commit(next)
        onAnnounce(String(localized: "Split in two", comment: "VoiceOver: a set was split"))
    }

    // MARK: controls

    func activate(_ control: TilesInputState.Control) {
        switch control {
        case .menu:
            Haptics.shared.tick()
            onMenu()
        case .loupeClose:
            closeLoupe()
        case .undo:
            guard composing, var next = draft, next.undo() else { return nope(undoButton) }
            Sound.shared.play(ArtName.Sound.sfxFlip, volume: 0.5)
            Haptics.shared.tick()
            commit(next)
        case .reset:
            // Reached by its hold, or by VoiceOver.
            guard composing, var next = draft, !next.isUntouched else { return nope(resetButton) }
            next.reset()
            Sound.shared.play(ArtName.Sound.sfxWhoosh, volume: 0.5)
            Haptics.shared.thump()
            loupe = nil
            commit(next)
        case .sortNumber, .sortToy:
            guard let seat = shownSeat else { return }
            orders[seat]?.toggle(control == .sortNumber ? .number : .toy)
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxFlip, volume: 0.4)
            saveDraft()
            redraw(animated: true)
        case .tidy:
            if easy {
                showHint()
            } else {
                let on = !(draft?.tidy ?? tidyPreference)
                tidyPreference = on
                draft?.tidy = on
                Haptics.shared.tick()
                Sound.shared.play(ArtName.Sound.sfxFlip, volume: 0.4)
                saveDraft()
                redraw(animated: true)
            }
        case .recap:
            showRecap()
        case .turn:
            pressTurn(held: false)
        }
    }

    /// The turn button, tapped (or held to the end, for Draw and Pass).
    func pressTurn(held: Bool) {
        guard let seat = shownSeat, let draft, !sending else { return nope(turnPill) }
        switch draft.turnButton {
        case .play:
            if let action = draft.action { send(action, seat: seat) }
        case .draw, .pass:
            guard held || UIAccessibility.isVoiceOverRunning, let action = draft.action else { return holdHint(turnPill) }
            send(action, seat: seat)
        case .blocked(.brokenSet(let id)):
            reveal(set: id)
        case .blocked(.openingTooLow):
            shakeMeter()
        case .blocked:
            nope(turnPill)
        }
    }

    private func send(_ action: TilesAction, seat: Seat) {
        guard store.actTiles(seat: seat, action) else { return nope(turnPill) }
        #if DEBUG
        probe.sent = "\(action)"
        #endif
        sending = true
        selection = []
        hint = nil
        loupe = nil
        recap.clear()
        rings = [:]
        memory?.update(code: store.code) { $0.draft = nil }
        if case .play = action {
            Sound.shared.play(ArtName.Sound.sfxSparkle)
            Haptics.shared.success()
        } else {
            Sound.shared.play(ArtName.Sound.sfxPop)
            Haptics.shared.drop()
        }
        redraw(animated: true)
    }

    /// A hold let go early: the button bumps, so it is clear it wants holding.
    private func holdHint(_ node: SKNode) {
        Haptics.shared.tick()
        onAnnounce(String(localized: "Press and hold", comment: "VoiceOver: the button needs a press and hold"))
        guard !Effects.reduceMotion else { return }
        let bump = SKAction.sequence([.scale(to: 1.08, duration: 0.08).eased(.easeOut), .scale(to: 1, duration: 0.14).eased(.easeInEaseOut)])
        let director = director
        Task { await director.run(bump, on: node, decorative: true) }
    }

    /// Easy mode's "show me": lights the next thing to do, or says it is time to draw.
    func showHint() {
        guard composing, let draft else { return }
        hint = TilesHints.next(draft)
        Haptics.shared.tick()
        switch hint {
        case .newSet(let tiles):
            Sound.shared.play(ArtName.Sound.sfxSparkle, volume: 0.5)
            onAnnounce(String(localized: "These make a set: \(tiles.map(TilesWords.piece).formatted(.list(type: .and)))", comment: "VoiceOver: a hint"))
        case .fits(let tile, let set):
            Sound.shared.play(ArtName.Sound.sfxSparkle, volume: 0.5)
            reveal(set: set)
            onAnnounce(String(localized: "\(TilesWords.piece(tile)) fits", comment: "VoiceOver: a hint"))
        case nil:
            // Nothing fits: the turn button says so with a gentle pulse.
            holdHint(turnPill)
            onAnnounce(String(localized: "Nothing fits. Draw a toy.", comment: "VoiceOver: a hint found nothing"))
        }
        redraw(animated: true)
    }

    // MARK: per frame

    /// Holds fill, and a drag near the rug's top or bottom edge scrolls it.
    func stepInput(_ now: TimeInterval) {
        let dt = min(now - (input.lastStep ?? now), 0.05)
        input.lastStep = now
        if let hold = input.hold, input.phase == .press {
            let start = input.holdStart ?? now
            input.holdStart = start
            let progress = min((now - start) / Pace.seconds(Self.holdSeconds), 1)
            if hold == .turn {
                holdFill.isHidden = false
                holdFill.xScale = CGFloat(progress)
            } else {
                resetButton.setScale(1 + 0.25 * CGFloat(progress))
            }
            if progress >= 1 {
                input.hold = nil
                input.holdStart = nil
                input.phase = .idle
                input.pressed = nil
                holdFill.isHidden = true
                resetButton.setScale(1)
                director.touchEnded()
                if hold == .turn { pressTurn(held: true) } else { activate(.reset) }
            }
        }
        guard input.isDragging, let layout, maxScroll > 0 else { return }
        let y = input.last.y
        let edge: CGFloat = 40
        var speed: CGFloat = 0
        if y > layout.rug.maxY - edge, y < layout.rugArt.maxY + 30 {
            speed = -(1 - max(layout.rug.maxY - y, 0) / edge) * 420
        } else if y < layout.rug.minY + edge, y > layout.rug.minY - 10 {
            speed = (1 - max(y - layout.rug.minY, 0) / edge) * 420
        }
        guard speed != 0 else { return }
        let next = min(max(scroll + speed * CGFloat(dt), 0), maxScroll)
        guard next != scroll else { return }
        scroll = next
        rugContent.position = CGPoint(x: layout.rug.minX, y: layout.rug.maxY + scroll)
        aim(at: input.last)
    }

    // MARK: zoom (the view's pinch and double tap)

    /// Pinch: from the fit size up to stash size (tile game spec §5.7).
    func pinch(scale: CGFloat, began: Bool) {
        guard let layout, let flow, loupe == nil, !input.isDragging else { return }
        if began { input.pinchBase = zoom ?? flow.pieceSize.width }
        let fit = RugFlow.fit(
            lengths: shown.map(\.tiles.count), width: layout.rug.width, height: layout.rug.height,
            maxPiece: layout.rugPieceMax, minPiece: layout.rugPieceMin).pieceSize.width
        let wanted = min(max(input.pinchBase * scale, fit), layout.rackPiece.width)
        zoom = wanted <= fit + 0.5 ? nil : wanted
        redraw()
    }

    /// Double tap: between fit and stash size, around the tap.
    func doubleTap(at point: CGPoint) {
        guard let layout, let flow, layout.rugArt.contains(point), loupe == nil else { return }
        let content = rugPoint(point)
        let fraction = flow.contentHeight > 0 ? content.y / flow.contentHeight : 0
        zoom = zoom == nil ? layout.rackPiece.width : nil
        redraw()
        if let after = self.flow {
            scroll = min(max(fraction * after.contentHeight - layout.rug.height / 2, 0), maxScroll)
            redraw()
        }
    }

    /// True while a touch on the left edge can't be on a piece: the swipe home may start.
    var allowsSwipeHome: Bool { input.phase == .idle && loupe == nil }
}
