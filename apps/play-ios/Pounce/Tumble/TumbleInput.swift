import PounceKit
import SpriteKit

/// Toy Tumble's touch controls (spec §5.3), built for zero lag and no aiming. Every one is applied
/// in the touch handler, the moment the event arrives, and shows on the next frame:
/// - drag left or right anywhere on the table: one column per cell-width the finger travels;
/// - tap: turn clockwise;
/// - drag down and hold: soft drop;
/// - flick down: drop;
/// - tap a trick in the tray to lift it (the default targets glow), then tap a box to use it, or
///   drag the trick onto a box. Tap the lifted trick again to put it down.
/// The table turns off the system's edge gestures while playing (`TumbleTableView`), so a drag
/// from the very edge moves the toy.
extension TumbleScene {
    /// A flick: at least this fast downward, in points a second, over the last few touch samples.
    static let flickSpeed: CGFloat = 900
    /// A press that travels less than this, and ends this soon, is a tap.
    static let tapSlop: CGFloat = 10
    static let tapTime: TimeInterval = 0.3

    private var cellWidth: CGFloat { max(layout?.cell ?? 20, 8) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isScreen, let touch = touches.first, press == nil else { return }
        let p = touch.location(in: self)
        let now = touch.timestamp
        var next = Press(start: p, last: p, startTime: now)
        next.samples = [(now, p)]
        if menuButton.frame.insetBy(dx: -8, dy: -8).contains(p), !menuButton.isHidden {
            next.onMenu = true
        } else if let slot = slot(at: p) {
            next.slot = slot
        }
        press = next
        Haptics.shared.prepare()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var press, let touch = touches.first else { return }
        let p = touch.location(in: self)
        press.samples.append((touch.timestamp, p))
        if press.samples.count > 6 { press.samples.removeFirst(press.samples.count - 6) }
        let total = CGPoint(x: p.x - press.start.x, y: p.y - press.start.y)
        if hypot(total.x, total.y) > Self.tapSlop { press.moved = true }
        if press.onMenu {
            self.press = press
            return
        }
        if let slot = press.slot {
            if press.moved {
                press.dragging = true
                showDrag(slot, at: p)
            }
            press.last = p
            self.press = press
            return
        }
        guard let local = table.local, local.toy != nil else {
            press.last = p
            self.press = press
            return
        }
        // Sideways: one column per cell-width travelled, applied now.
        press.carried += p.x - press.last.x
        let c = cellWidth
        var moved = false
        while press.carried >= c {
            if local.move(1) { moved = true }
            press.carried -= c
        }
        while press.carried <= -c {
            if local.move(-1) { moved = true }
            press.carried += c
        }
        if moved { onTipUsed("tumble.move") }
        // Down and mostly down: soft drop while held.
        let down = press.start.y - p.y
        let soft = down > c * 1.2 && down > abs(total.x) * 1.2
        if soft != press.soft {
            press.soft = soft
            local.setSoft(soft)
        }
        press.last = p
        self.press = press
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let press, let touch = touches.first else { return }
        self.press = nil
        let p = touch.location(in: self)
        let held = touch.timestamp - press.startTime
        let tap = !press.moved && held < Self.tapTime
        if press.onMenu {
            if menuButton.frame.insetBy(dx: -12, dy: -12).contains(p) {
                Haptics.shared.tick()
                onMenu()
            }
            return
        }
        if let slot = press.slot {
            hideDrag()
            if press.dragging {
                if let seat = seat(at: p) { use(slot, on: seat) }
            } else if tap {
                lifted = lifted == slot ? nil : (slot < (table.local?.box.held.count ?? 0) ? slot : nil)
                Haptics.shared.tick()
            }
            return
        }
        guard let local = table.local else { return }
        if press.soft { local.setSoft(false) }
        if tap {
            if let lifted, let seat = seat(at: p) {
                use(lifted, on: seat)
                return
            }
            if lifted != nil {
                lifted = nil
                return
            }
            if local.turn(1) {
                Haptics.shared.tick()
                onTipUsed("tumble.turn")
            }
            return
        }
        if Self.isFlick(press.samples, end: (touch.timestamp, p)), press.start.y - p.y > cellWidth * 1.5 {
            local.drop(TumbleTable.now())
            onTipUsed("tumble.drop")
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if press?.soft == true { table.local?.setSoft(false) }
        hideDrag()
        press = nil
    }

    /// A fast swipe down over the last samples.
    static func isFlick(_ samples: [(t: TimeInterval, p: CGPoint)], end: (t: TimeInterval, p: CGPoint)) -> Bool {
        guard let first = samples.first(where: { end.t - $0.t <= 0.1 }) ?? samples.last else { return false }
        let dt = max(end.t - first.t, 1.0 / 240)
        let vy = (first.p.y - end.p.y) / CGFloat(dt)
        let vx = abs(end.p.x - first.p.x) / CGFloat(dt)
        return vy >= flickSpeed && vy > vx
    }

    // MARK: tricks

    func use(_ slot: Int, on seat: Int) {
        guard let local = table.local, !table.isOut(seat) else { return }
        if local.use(slot: slot, on: seat, now: TumbleTable.now()) != nil {
            Haptics.shared.success()
            Sound.shared.play(ArtName.Sound.sfxWhoosh, volume: 0.7, kind: .game)
            onTipUsed("tumble.use")
        }
        lifted = nil
    }

    private func showDrag(_ slot: Int, at p: CGPoint) {
        guard let held = table.local?.box.held, slot < held.count, let layout else { return }
        dragBadge.texture = TumbleArt.shared.badge(held[slot])
        let side = layout.slots[slot].width * 1.2
        dragBadge.size = CGSize(width: side, height: side)
        dragBadge.position = CGPoint(x: p.x, y: p.y + side * 0.6)
        dragBadge.isHidden = false
    }

    private func hideDrag() { dragBadge.isHidden = true }

    /// The trick slot under a point, holding a trick.
    func slot(at p: CGPoint) -> Int? {
        guard let layout, let held = table.local?.box.held else { return nil }
        for (i, r) in layout.slots.enumerated() where i < held.count && r.insetBy(dx: -4, dy: -6).contains(p) { return i }
        return nil
    }

    /// The seat whose box (or chip) is under a point.
    func seat(at p: CGPoint) -> Int? {
        for (seat, node) in boxNodes where node.rect.insetBy(dx: -6, dy: -6).contains(p) { return seat }
        for (seat, chip) in chipNodes where chip.rect.contains(p) { return seat }
        return nil
    }
}
