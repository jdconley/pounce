import PounceKit
import SpriteKit
import SwiftUI

/// The tile game's timeline: the store's intents in order. Events animate over the table as it
/// was; the `.reconcile` after them (the snapshot that follows every action) snaps to the truth.
extension TilesScene {
    /// Queues one intent behind the ones before it.
    func enqueue(_ intent: TableIntent) {
        let previous = playChain
        playChain = Task { @MainActor [weak self] in
            await previous?.value
            await self?.playNow(intent)
        }
    }

    private func playNow(_ intent: TableIntent) async {
        switch intent {
        case .reconcile, .versusIntro:
            reconcileFromStore()
        case .rejected(let code):
            rejected(code)
        case .tiles(let event, let seq):
            guard seq > drawnSeq, model != nil, layout != nil else { return }
            // Privacy doesn't wait for the snapshot: a shared phone's stash hides with its turn.
            hideIfStale()
            await animate(event)
        case .presence, .link:
            // Folded into the room whole: only the seats are taken, the rug waits for its snapshot.
            guard let room = store.room, let model else { return }
            var next = model.room
            next.seats = room.seats
            self.model = TilesTableModel(room: next)
            redraw()
        case .game, .lobbyNope:
            break
        }
    }

    /// The server refused the turn (a bug, or a stale draft): the draft stays, and the refusal
    /// shows as the same pictures a bad draft does, never as a code (tile game spec §5.5).
    private func rejected(_ code: ErrorCode) {
        sending = false
        #if DEBUG
        probe.refused = code.rawValue
        #endif
        guard let draft else {
            reconcileFromStore()
            return
        }
        let error = TilesPlayError(rawValue: code.rawValue)
        input.wiggling = Set(error.map(draft.sets(refusedBy:)) ?? [])
        redraw()
        Sound.shared.play(ArtName.Sound.sfxNope)
        Haptics.shared.thump()
        if error == .openingTooLow {
            shakeMeter()
        } else if let first = shown.first(where: { input.wiggling.contains($0.id) }) {
            reveal(set: first.id)
        } else {
            nope(turnPill)
        }
        onAnnounce(String(localized: "That didn't go. Check the rug.", comment: "VoiceOver: the server refused the turn"))
    }

    /// Where a seat is on screen: its cat in the top bar, or the stash for the seat at the bottom.
    private func seatPoint(_ seat: Seat) -> CGPoint {
        if let cat = opponents.node(for: seat) { return cat.position }
        guard let layout else { return CGPoint(x: size.width / 2, y: 0) }
        return CGPoint(x: size.width / 2, y: layout.rack.midY)
    }

    private func wait(_ seconds: TimeInterval) async {
        await director.run(.wait(forDuration: seconds), on: layer(.fx))
    }

    private func animate(_ event: TilesEvent) async {
        guard let model, let layout else { return }
        let reduce = Effects.reduceMotion
        switch event {
        case .played(let seat, let table, let placed, let opened):
            recap.note(event, mine: model.mySeats)
            if model.mySeats.contains(seat), draft != nil {
                // This phone's own play: the rug already shows it. A sparkle where it landed.
                if let first = placed.first, let node = pieces[first], let parent = node.parent {
                    Effects.burst(.sparkle, at: layer(.fx).convert(node.position, from: parent), in: layer(.fx), director: director)
                }
                return
            }
            // Another seat's play: its pieces fly from its cat to their sets, and the rest of
            // the rug slides to its new shape.
            draft = nil
            pendingTable = table
            let from = rugContent.convert(seatPoint(seat), from: self)
            let color = UIColor(SeatInfo.ringColor(seat))
            ringSerial += 1
            let serial = ringSerial
            rings = [:]
            for tile in placed where pieces[tile] == nil {
                let size = flow?.pieceSize ?? CGSize(width: layout.rugPieceMax, height: layout.rugPieceMax * TilesLayout.pieceAspect)
                let node = piece(tile, in: rugContent, size: size, face: .small, at: from)
                node.setScale(reduce ? 1 : 0.5)
                node.alpha = reduce ? 0 : 1
                node.zPosition = 60
                rings[tile] = color
            }
            flight = reduce ? 0.01 : 0.42
            redraw(animated: true)
            flight = 0.2
            if reduce {
                for tile in placed { pieces[tile]?.run(.fadeIn(withDuration: 0.2), withKey: "fade") }
            }
            Sound.shared.play(ArtName.Sound.sfxThud, volume: 0.5)
            let name = SeatInfo.name(model.room, seat)
            onAnnounce(opened
                ? String(localized: "\(name) opened with \(placed.count) toys", comment: "VoiceOver: another player made their opening play")
                : String(localized: "\(name) placed \(placed.count) toys", comment: "VoiceOver: another player played pieces"))
            await wait(0.6)
            // The placing cat's colour stays on its pieces for a few seconds.
            Task { [weak self] in
                try? await Task.sleep(for: Pace.duration(.seconds(3.5)))
                guard let self, self.ringSerial == serial else { return }
                self.rings = [:]
                self.redraw()
            }
        case .drew(let seat, let tile, _):
            let box = CGPoint(x: layout.pool.midX, y: layout.pool.midY)
            let fx = layer(.fx)
            if let tile, seat == shownSeat {
                // My draw: the piece comes out of the toy box, turns over and lands at the
                // right end of the stash. It stays there until the snapshot brings the real one.
                let slots = layout.rackSlots(count: rackShown.count + 1).centers
                let end = slots.last.map { CGPoint(x: $0.x - rackScroll, y: $0.y) } ?? seatPoint(seat)
                let node = SKSpriteNode(texture: TilePieceFactory.shared.back(size: .large), size: layout.rackPiece)
                node.position = box
                node.setScale(0.6)
                fx.addChild(node)
                transients.append(node)
                Sound.shared.play(ArtName.Sound.sfxFlip)
                let face = TilePieceFactory.shared.face(tile, size: .large)
                if reduce {
                    node.texture = face
                    node.position = end
                    node.setScale(1)
                    node.alpha = 0
                    await director.run(.fadeIn(withDuration: 0.2), on: node)
                } else {
                    let fly = SKAction.group([.move(to: end, duration: 0.45).eased(.easeOut), .scale(to: 1, duration: 0.45)])
                    let flip = SKAction.sequence([
                        .wait(forDuration: 0.12), .scaleX(to: 0, duration: 0.1), .setTexture(face), .scaleX(to: 1, duration: 0.12),
                    ])
                    await director.runAll([(fly, node)])
                    await director.run(flip, on: node)
                }
                Haptics.shared.drop()
                onAnnounce(String(localized: "You drew \(TilesWords.piece(tile))", comment: "VoiceOver: this player drew a piece"))
            } else {
                // Someone else's draw: a piece goes from the toy box to that cat, face down.
                if let tile, model.mySeats.contains(seat) { onDrew(seat, tile) }
                let size = CGSize(width: layout.rugPieceMax, height: layout.rugPieceMax * TilesLayout.pieceAspect)
                let node = SKSpriteNode(texture: TilePieceFactory.shared.back(), size: size)
                node.position = box
                fx.addChild(node)
                Sound.shared.play(ArtName.Sound.sfxFlip, volume: 0.5)
                let to = seatPoint(seat)
                let action = reduce
                    ? SKAction.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()])
                    : SKAction.sequence([
                        .group([.move(to: to, duration: 0.4).eased(.easeIn), .scale(to: 0.6, duration: 0.4)]),
                        .fadeOut(withDuration: 0.08), .removeFromParent(),
                    ])
                await director.run(action, on: node)
                node.removeFromParent()
            }
        case .passed(let seat):
            // A sleepy Zzz over the cat that passed.
            let nap = SKSpriteNode(texture: TableArt.image(ArtName.iconZzz), size: CGSize(width: 34, height: 34))
            let at = seatPoint(seat)
            nap.position = CGPoint(x: at.x, y: at.y + (opponents.node(for: seat) == nil ? 60 : 0))
            nap.zPosition = 5
            layer(.fx).addChild(nap)
            let action = reduce
                ? SKAction.sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.2), .removeFromParent()])
                : SKAction.sequence([
                    .group([.moveBy(x: 10, y: 26, duration: 0.7).eased(.easeOut), .sequence([.scale(to: 1.3, duration: 0.2), .scale(to: 1, duration: 0.5)])]),
                    .fadeOut(withDuration: 0.2), .removeFromParent(),
                ])
            await director.run(action, on: nap)
            nap.removeFromParent()
            onAnnounce(String(localized: "\(SeatInfo.name(model.room, seat)) passed", comment: "VoiceOver: a player passed"))
        case .turn(let seat):
            guard model.mySeats.contains(seat) else { return }
            Haptics.shared.turn()
            if !model.isMultiSeat {
                onAnnounce(String(localized: "Your turn", comment: "VoiceOver announcement: this phone's turn came"))
            }
        case .forfeited(let seat):
            onAnnounce(String(localized: "\(SeatInfo.name(model.room, seat)) forfeited", comment: "VoiceOver announcement: a player forfeited"))
        case .gameOver:
            // The snapshot that follows ends the game on this table (`onGameOver`).
            await wait(0.4)
        }
    }

    /// Plays back what changed since this phone's last turn (tile game spec §5.7): each play's
    /// pieces ring in the placing cat's colour, in turn order, then the rings fade.
    func showRecap() {
        let steps = recap.steps
        guard !steps.isEmpty else { return }
        ringSerial += 1
        let serial = ringSerial
        rings = [:]
        Task { [weak self] in
            for step in steps {
                guard let self, self.ringSerial == serial else { return }
                let color = step.seat.map { UIColor(SeatInfo.ringColor($0)) } ?? UIColor.white
                for tile in step.placed { self.rings[tile] = color }
                self.redraw()
                if !Effects.reduceMotion {
                    let director = self.director
                    for tile in step.placed {
                        guard let node = self.pieces[tile] else { continue }
                        let pop = SKAction.sequence([.scale(to: 1.25, duration: 0.1).eased(.easeOut), .scale(to: 1, duration: 0.16).eased(.easeInEaseOut)])
                        Task { await director.run(pop, on: node, decorative: true) }
                    }
                }
                Sound.shared.play(ArtName.Sound.sfxTick, volume: 0.4)
                try? await Task.sleep(for: Pace.duration(.milliseconds(550)))
            }
            try? await Task.sleep(for: Pace.duration(.seconds(TableText.lingering(3.5))))
            guard let self, self.ringSerial == serial else { return }
            self.rings = [:]
            self.redraw()
        }
    }
}
