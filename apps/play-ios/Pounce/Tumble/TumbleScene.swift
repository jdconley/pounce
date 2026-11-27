import PounceKit
import SpriteKit
import SwiftUI

/// Toy Tumble's table on a phone or iPad (spec §5.2), and every box on the TV (§5.6).
///
/// The frame clock drives it: each `update` steps this device's own box (`TumbleTable.step`, well
/// under half a millisecond), then shows every box from memory. Settled cells are one rasterized
/// layer per box, re-made only when a set-down or a hit changed them; the falling toys, the meters
/// and effects are the only live nodes. Input is applied in the touch handlers, at once
/// (`TumbleInput.swift`). Nothing here waits on the socket: messages are decoded off the main
/// thread and handed to the table model before the frame reads it.
@MainActor
final class TumbleScene: SKScene {
    enum Layer: CGFloat { case background = 0, boxes = 10, chrome = 40, tray = 50, drag = 90, fx = 100 }

    let store: RoomStore
    let table: TumbleTable
    /// A TV's table: every box, no controls.
    let isScreen: Bool

    var onMenu: () -> Void = {}
    /// Where tips can point, in the view's points from its top-left corner.
    var onTipSpots: ([String: CGRect]) -> Void = { _ in }
    var onTipUsed: (String) -> Void = { _ in }
    var onTipEvent: (TipEvent) -> Void = { _ in }
    /// The game is over (the TV's game over screen follows).
    var onGameOver: ([Seat]) -> Void = { _ in }
    private var reportedOver = false
    private var seenSeq = -2

    var safeInsets: UIEdgeInsets = .zero {
        didSet { if safeInsets != oldValue { needsLayout = true } }
    }

    private(set) var layout: TumbleLayout?
    private var needsLayout = true
    /// Boxes by seat.
    private(set) var boxNodes: [Int: TumbleBoxNode] = [:]
    /// The seats drawn as minis (or every box when watching, or on the TV), in layout order.
    private(set) var shown: [Int] = []
    private(set) var chipNodes: [Int: TumbleChipNode] = [:]
    let menuButton = SKSpriteNode(texture: TableArt.image(ArtName.iconPawMenu))
    private let background = SKSpriteNode(texture: TableArt.image(ArtName.roomBg))
    private let roundLabel = SKSpriteNode()
    private let countdown = SKSpriteNode()
    private var meterNodes: [SKSpriteNode] = []
    private(set) var slotNodes: [SKSpriteNode] = []
    private var slotBadges: [SKSpriteNode] = []
    private let trickName = SKSpriteNode()
    /// The lifted trick's slot, waiting for a box to be tapped.
    var lifted: Int? {
        didSet { if lifted != oldValue { drawTray(force: true) } }
    }
    /// A trick being dragged onto a box.
    let dragBadge = SKSpriteNode()
    var press: Press?
    private var lastRound: Int?
    private var lastLayoutKey = ""
    private var lastTipSpots: [String: CGRect] = [:]
    private var lastCount: Int?
    private var heldShown: [TumbleTrick] = []
    var accessibilityVersion = 0
    let accessibilityPool = TumbleAccessibilityPool()
    #if DEBUG
    var autoplay: TumbleAutoplay?
    #endif

    /// One finger on the table (`TumbleInput.swift`).
    struct Press {
        var start: CGPoint
        var last: CGPoint
        var startTime: TimeInterval
        var samples: [(t: TimeInterval, p: CGPoint)] = []
        /// Horizontal travel not yet turned into a move.
        var carried: CGFloat = 0
        var moved = false
        var soft = false
        /// A trick slot it started on.
        var slot: Int?
        var dragging = false
        var onMenu = false
    }

    init(store: RoomStore, table: TumbleTable) {
        self.store = store
        self.table = table
        isScreen = store.isScreen
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = UIColor(Palette.night)
        TableArt.preload()
        background.zPosition = Layer.background.rawValue
        addChild(background)
        menuButton.zPosition = Layer.chrome.rawValue
        menuButton.isHidden = isScreen
        addChild(menuButton)
        roundLabel.zPosition = Layer.chrome.rawValue
        addChild(roundLabel)
        countdown.zPosition = Layer.fx.rawValue
        countdown.isHidden = true
        addChild(countdown)
        trickName.zPosition = Layer.tray.rawValue + 2
        trickName.isHidden = true
        addChild(trickName)
        dragBadge.zPosition = Layer.drag.rawValue
        dragBadge.isHidden = true
        addChild(dragBadge)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        safeInsets = view.safeAreaInsets
        speed = CGFloat(Pace.factor)
        #if DEBUG
        if autoplay == nil { autoplay = TumbleAutoplay.start(self) }
        #endif
        needsLayout = true
        // The textures are drawn off the main thread; until they come the boxes wait, then are made again.
        if !TumbleArt.shared.ready {
            Task { [weak self] in
                await TumbleArt.shared.prewarm()
                guard let self else { return }
                for node in self.boxNodes.values { node.removeFromParent() }
                self.boxNodes.removeAll()
                self.needsLayout = true
            }
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        needsLayout = true
    }

    func redraw() { needsLayout = true }

    private var textScale: CGFloat {
        let category = UIApplication.shared.preferredContentSizeCategory
        return category.isAccessibilityCategory ? 1.4 : (category > .large ? 1.15 : 1)
    }

    /// This device's own seat while its box plays; nil for a screen, a watcher, or once out.
    var mySeat: Int? { table.mySeat }
    private var watching: Bool { isScreen || mySeat == nil || table.local == nil || table.local?.isOut == true }

    // MARK: the frame

    override func update(_ currentTime: TimeInterval) {
        let work = FrameWork("tumble.frame"); defer { work.end() }
        let now = TumbleTable.now()
        // A snapshot the table hasn't seen (its owner may also hand it over; updating twice is a no-op).
        if store.lastSeq != seenSeq, let room = store.room {
            seenSeq = store.lastSeq
            table.update(room: room, now: now)
            if !reportedOver, room.tumble?.status == .over || room.status == .over {
                reportedOver = true
                onGameOver(room.tumble?.winner.map { [$0] } ?? [])
            }
        }
        table.step(now: now)
        #if DEBUG
        autoplay?.tick(now)
        #endif
        relayoutIfNeeded()
        playEffects(now)
        drawBoxes(now)
        drawMeter(now)
        drawTray(force: false)
        drawChrome(now)
    }

    private func relayoutIfNeeded() {
        guard size.width > 1, size.height > 1, let view = table.view else { return }
        let seats = view.seats
        let others: [Int] = watching ? Array(0..<seats) : (0..<seats).filter { $0 != mySeat }
        let mode: TumbleLayout.Mode = isScreen ? .tv : (watching ? .watching : .play)
        let chips = store.room?.screen == true && !isScreen
        let key = "\(size)|\(safeInsets)|\(others)|\(mode)|\(chips)|\(textScale)"
        if !needsLayout, key == lastLayoutKey { return }
        needsLayout = false
        lastLayoutKey = key
        background.size = size
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        let l = TumbleLayout(
            size: size, safeTop: safeInsets.top, safeBottom: max(safeInsets.bottom, 4), safeLeft: safeInsets.left,
            safeRight: safeInsets.right, others: others.count, mode: mode, chips: chips, textScale: textScale)
        layout = l
        shown = others
        let keep = Set(chips ? (mySeat.map { [$0] } ?? []) : others + (watching ? [] : mySeat.map { [$0] } ?? []))
        for (seat, node) in boxNodes where !keep.contains(seat) {
            node.removeFromParent()
            boxNodes[seat] = nil
        }
        for (seat, node) in chipNodes where !chips || !others.contains(seat) {
            node.removeFromParent()
            chipNodes[seat] = nil
        }
        if !watching, let mine = mySeat {
            let own = boxNode(mine)
            own.showsNext = true
            own.place(l.box, mini: false)
        }
        for (i, seat) in others.enumerated() where i < l.minis.count {
            if chips {
                let chip = chipNodes[seat] ?? {
                    let c = TumbleChipNode(seat: seat)
                    c.zPosition = Layer.boxes.rawValue
                    addChild(c)
                    chipNodes[seat] = c
                    return c
                }()
                chip.place(l.minis[i], labelSize: l.labelHeight * 0.78)
            } else {
                let node = boxNode(seat)
                node.showsNext = false
                node.place(l.miniBoxes[i], label: l.labelHeight, mini: mode == .play)
            }
        }
        menuButton.isHidden = isScreen
        let side: CGFloat = l.roomy ? 40 : 32
        menuButton.size = CGSize(width: side, height: side)
        menuButton.position = l.menuButton
        meterNodes.forEach { $0.removeFromParent() }
        meterNodes.removeAll()
        slotNodes.forEach { $0.removeFromParent() }
        slotNodes.removeAll()
        slotBadges.removeAll()
        if mode == .play {
            for r in l.slots {
                let slot = SKSpriteNode(color: UIColor(Palette.ink).withAlphaComponent(0.45), size: r.size)
                slot.position = CGPoint(x: r.midX, y: r.midY)
                slot.zPosition = Layer.tray.rawValue
                addChild(slot)
                slotNodes.append(slot)
                let badge = SKSpriteNode()
                badge.size = CGSize(width: r.width * 0.9, height: r.height * 0.9)
                badge.zPosition = 1
                badge.isHidden = true
                slot.addChild(badge)
                slotBadges.append(badge)
            }
        }
        heldShown = []
        accessibilityVersion += 1
        drawTray(force: true)
        publishTipSpots()
    }

    private func boxNode(_ seat: Int) -> TumbleBoxNode {
        if let node = boxNodes[seat] { return node }
        let node = TumbleBoxNode(seat: seat)
        node.zPosition = Layer.boxes.rawValue
        addChild(node)
        boxNodes[seat] = node
        return node
    }

    // MARK: drawing every box

    private func drawBoxes(_ now: Double) {
        guard let view = table.view, let room = store.room, let layout else { return }
        let roundMs = (table.startsAt.map { now - $0 }) ?? 0
        let newRound = lastRound != view.r
        if newRound {
            lastRound = view.r
            for node in boxNodes.values { node.reset() }
            lifted = nil
        }
        for (seat, node) in boxNodes {
            guard let box = table.box(seat) else { continue }
            node.show(box)
            let out = table.isOut(seat)
            let lag = table.lagging(seat)
            let catIndex = SeatInfo.catIndex(room.seats[safe: seat])
            if seat == mySeat, let local = table.local {
                let toy = local.toy
                node.showToy(toy, y: Double(toy?.spot.y ?? 0), landing: local.landing)
                var next = local.queue
                node.showNext(local.toy != nil ? next.toy(local.box.next + 1) : nil)
                node.setNap(local.napping)
                node.setCatnip(local.catnip)
            } else if let replay = table.replay, let glide = replay.glide(seat, now: now, roundMs: roundMs) {
                node.showToy(glide.toy, y: glide.y, landing: nil)
                node.showNext(nil)
                node.setNap((replay.seats[seat]?.napUntil ?? 0) > now)
                node.setCatnip((replay.seats[seat]?.catnipUntil ?? 0) > now)
            } else {
                node.showToy(nil, y: 0, landing: nil)
            }
            let danger = Tumble.highest(box) >= Tumble.dangerRow
            let pose: CatPose = out ? .terrified : (lag ? .away : (node.cat.action(forKey: "cheer") != nil ? .celebrate : (danger ? .terrified : .awake)))
            node.setCat(catIndex, pose)
            if out {
                node.tip()
                node.setWords(TumbleWords.out)
            } else if lag {
                node.setWords(TumbleWords.reconnecting)
            } else {
                node.setWords(nil)
            }
            if node.mini || isScreen || watching {
                let wins = view.wins[safe: seat] ?? 0
                // A phone's minis show the cat's face and wins; names show on the big boxes.
                node.setName(node.mini ? "" : SeatInfo.name(room, seat), wins: wins, size: layout.labelHeight * 0.8)
            }
        }
        for (seat, chip) in chipNodes {
            guard let box = table.box(seat) else { continue }
            chip.show(name: SeatInfo.name(room, seat), cat: SeatInfo.catIndex(room.seats[safe: seat]), height: Tumble.highest(box),
                      wins: view.wins[safe: seat] ?? 0, out: table.isOut(seat))
        }
    }

    /// Your junk meter: a hairball per waiting attack, each shrinking as its 2 seconds run out.
    private func drawMeter(_ now: Double) {
        guard let layout, !watching, let local = table.local, layout.meter.width > 0 else {
            meterNodes.forEach { $0.isHidden = true }
            return
        }
        let waiting = local.waiting(at: now)
        while meterNodes.count < waiting.count {
            let n = SKSpriteNode(texture: TumbleArt.shared.furTexture())
            n.zPosition = Layer.chrome.rawValue
            addChild(n)
            meterNodes.append(n)
        }
        let side = layout.meter.width
        var y = layout.meter.minY + side / 2
        for (i, n) in meterNodes.enumerated() {
            guard i < waiting.count else {
                n.isHidden = true
                continue
            }
            let w = waiting[i]
            let k = CGFloat(0.45 + 0.55 * (w.leftMs / TumbleClock.junkWait))
            let h = side * CGFloat(min(w.rows, 4)) * 0.8
            n.isHidden = false
            n.size = CGSize(width: side * 1.3 * k, height: h * k)
            n.position = CGPoint(x: layout.meter.midX, y: y + h / 2 - side / 2)
            y += h + 3
        }
    }

    func drawTray(force: Bool) {
        guard let layout, layout.mode == .play else {
            trickName.isHidden = true
            return
        }
        let held = table.local?.box.held ?? []
        guard force || held != heldShown else { return }
        heldShown = held
        for (i, badge) in slotBadges.enumerated() {
            if i < held.count {
                badge.texture = TumbleArt.shared.badge(held[i])
                badge.isHidden = false
                let up = lifted == i
                badge.setScale(up ? 1.18 : 1)
                slotNodes[i].color = up ? UIColor(Palette.yellow).withAlphaComponent(0.7) : UIColor(Palette.ink).withAlphaComponent(0.45)
            } else {
                badge.isHidden = true
                slotNodes[i].color = UIColor(Palette.ink).withAlphaComponent(0.3)
            }
        }
        if let lifted, lifted < held.count {
            let t = CardFaceFactory.shared.numeral(TumbleWords.trick(held[lifted]), size: layout.roomy ? 22 : 15, outline: 3)
            trickName.texture = t
            trickName.size = t.size()
            let slot = layout.slots[lifted]
            trickName.position = CGPoint(x: min(max(slot.midX, t.size().width / 2 + 6), size.width - t.size().width / 2 - 6), y: slot.maxY + t.size().height / 2 + 4)
            trickName.isHidden = false
        } else {
            trickName.isHidden = true
        }
        glowTargets()
        accessibilityVersion += 1
    }

    /// A lifted trick's default targets glow: opponents for the harmful ones, your own box for the rest.
    private func glowTargets() {
        let held = table.local?.box.held ?? []
        let trick = lifted.flatMap { $0 < held.count ? held[$0] : nil }
        let mine = trick.map(Self.selfTarget) ?? false
        for (seat, node) in boxNodes {
            let on = trick != nil && (seat == mySeat ? mine : !mine) && !table.isOut(seat)
            if on, node.action(forKey: "glow") == nil {
                node.run(.repeatForever(.sequence([.fadeAlpha(to: 0.7, duration: 0.35), .fadeAlpha(to: 1, duration: 0.35)])), withKey: "glow")
            } else if !on, node.action(forKey: "glow") != nil {
                node.removeAction(forKey: "glow")
                node.alpha = 1
            }
        }
    }

    /// The tricks whose default target is your own box (§4.6).
    static func selfTarget(_ t: TumbleTrick) -> Bool { [.scoop, .settle, .nap, .bath].contains(t) }

    private func drawChrome(_ now: Double) {
        guard let layout, let view = table.view else {
            roundLabel.isHidden = true
            countdown.isHidden = true
            return
        }
        let size: CGFloat = layout.mode == .tv ? 44 : (layout.roomy ? 26 : 18)
        let t = CardFaceFactory.shared.numeral(TumbleWords.round(view.r), size: size * min(textScale, 1.2), outline: 3)
        roundLabel.texture = t
        roundLabel.size = t.size()
        roundLabel.isHidden = false
        // The round on the rim, right of your cat and its next toy (or in the middle when watching).
        roundLabel.position = layout.mode == .play
            ? CGPoint(x: layout.box.maxX - t.size().width / 2, y: layout.rim.midY)
            : CGPoint(x: layout.rim.midX, y: layout.rim.midY)
        // 3, 2, 1 to the start.
        if let start = table.startsAt, now < start, view.status == .countdown || view.status == .playing {
            let n = Int(((start - now) / 1000).rounded(.up))
            if n != lastCount {
                lastCount = n
                let big = CardFaceFactory.shared.numeral(String(max(n, 1)), size: layout.mode == .tv ? 220 : 120, fill: UIColor(Palette.yellow), outline: 8)
                countdown.texture = big
                countdown.size = big.size()
                countdown.setScale(1.4)
                countdown.run(.scale(to: 1, duration: 0.25))
            }
            let r = watching ? CGRect(origin: .zero, size: self.size) : layout.box
            countdown.position = CGPoint(x: r.midX, y: r.midY)
            countdown.isHidden = false
        } else {
            countdown.isHidden = true
            lastCount = nil
        }
    }

    // MARK: effects

    private func playEffects(_ now: Double) {
        if let local = table.local {
            for e in local.drainEffects() { play(e, seat: local.seat) }
        }
        if let replay = table.replay {
            for e in replay.drainEffects() {
                switch e {
                case .setDown(let seat, let rows): boxNodes[seat]?.pop(rows: rows)
                case .hit(let seat, let kind, let from): hit(seat, kind: kind, from: from, mine: false)
                case .out(let seat): boxNodes[seat]?.tip()
                }
            }
        }
    }

    private func play(_ e: TumbleEffect, seat: Int) {
        let node = boxNodes[seat]
        switch e {
        case .setDown(let rows, let sent, let blocked):
            if rows.isEmpty {
                Haptics.shared.tick()
                Sound.shared.play(ArtName.Sound.sfxTick, volume: 0.4, kind: .game)
            } else {
                node?.pop(rows: rows)
                node?.cat.run(.wait(forDuration: 0.8), withKey: "cheer")
                Haptics.shared.success()
                Sound.shared.play(ArtName.Sound.sfxPop, volume: min(0.5 + 0.15 * Float(rows.count), 1), kind: .game)
                if blocked > 0 { onTipUsed("tumble.block") }
                if sent > 0 { Sound.shared.play(ArtName.Sound.sfxWhoosh, volume: 0.6, kind: .game) }
            }
        case .pocketed:
            Sound.shared.play(ArtName.Sound.sfxSparkle, volume: 0.6, kind: .game)
            onTipEvent(.tumbleTrick)
        case .junkWaiting:
            onTipEvent(.tumbleJunk)
        case .junkLanded:
            node?.shake()
            Sound.shared.play(ArtName.Sound.sfxThud, volume: 0.6, kind: .game)
        case .hit(let kind, let from):
            hit(seat, kind: kind, from: from, mine: true)
        case .out:
            node?.tip()
            Haptics.shared.thump()
            Sound.shared.play(ArtName.Sound.sfxScream, volume: 0.6, kind: .game)
        }
    }

    /// Something flies from the thrower's box to the target's, which shakes.
    private func hit(_ seat: Int, kind: TumbleHitKind, from: Int, mine: Bool) {
        guard let target = boxNodes[seat] else { return }
        if mine {
            Haptics.shared.thump()
            Sound.shared.play(ArtName.Sound.sfxBat, volume: 0.7, kind: .game)
        }
        let to = CGPoint(x: target.rect.midX, y: target.rect.midY)
        if let thrower = boxNodes[from], from != seat, let trick = TumbleTrick(rawValue: kind.rawValue) {
            let fly = SKSpriteNode(texture: TumbleArt.shared.badge(trick))
            let side = max(min(target.cell * 2.4, 64), 24)
            fly.size = CGSize(width: side, height: side)
            fly.position = CGPoint(x: thrower.rect.midX, y: thrower.rect.maxY)
            fly.zPosition = Layer.fx.rawValue
            addChild(fly)
            fly.run(.sequence([.group([.move(to: to, duration: 0.32), .rotate(byAngle: .pi * 2, duration: 0.32)]), .removeFromParent()]))
            thrower.cat.run(.sequence([.scale(to: 1.25, duration: 0.1), .scale(to: 1, duration: 0.12)]))
            target.run(.sequence([.wait(forDuration: 0.3), .run { [weak target] in target?.shake() }]))
        } else if kind == .napped {
            target.setNap(true)
        } else {
            target.shake()
        }
    }

    // MARK: tips

    private func publishTipSpots() {
        guard let layout, layout.mode == .play else {
            if !lastTipSpots.isEmpty { lastTipSpots = [:]; onTipSpots([:]) }
            return
        }
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height) }
        var spots = ["tumble.box": flip(layout.box), "tumble.meter": flip(layout.meter.insetBy(dx: -8, dy: 0))]
        if let first = layout.slots.first, let last = layout.slots.last { spots["tumble.tray"] = flip(first.union(last)) }
        if spots != lastTipSpots {
            lastTipSpots = spots
            onTipSpots(spots)
        }
    }
}

/// A seat at a table a TV shows, on a phone: cat face, name, how high its stack is, and wins.
@MainActor
final class TumbleChipNode: SKNode {
    let seat: Int
    private let back = SKSpriteNode()
    private let cat = SKSpriteNode()
    private let label = SKSpriteNode()
    private let bar = SKSpriteNode(color: UIColor(Palette.lime), size: .zero)
    private let wins = SKSpriteNode()
    private(set) var rect: CGRect = .zero
    private var labelSize: CGFloat = 12
    private var last: (String, Int, Int, Int, Bool)?

    init(seat: Int) {
        self.seat = seat
        super.init()
        back.color = UIColor(Palette.ink).withAlphaComponent(0.6)
        back.anchorPoint = .zero
        addChild(back)
        for n in [cat, label, wins] {
            n.zPosition = 1
            addChild(n)
        }
        bar.anchorPoint = .zero
        bar.zPosition = 1
        addChild(bar)
        label.anchorPoint = CGPoint(x: 0, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func place(_ rect: CGRect, labelSize: CGFloat) {
        self.rect = rect
        self.labelSize = labelSize
        position = rect.origin
        back.size = rect.size
        let side = rect.height * 0.8
        cat.size = CGSize(width: side, height: side)
        cat.position = CGPoint(x: side / 2 + 2, y: rect.height / 2)
        last = nil
    }

    func show(name text: String, cat index: Int, height: Int, wins count: Int, out: Bool) {
        let key = (text, index, height, count, out)
        if let last, last == key { return }
        last = key
        cat.texture = TableArt.cat(index, out ? .terrified : .awake)
        let side = rect.height * 0.8
        let n = CardFaceFactory.shared.numeral(text, size: labelSize, outline: 2)
        let room = rect.width - side - 8 - labelSize * 1.4
        let k = min(1, room / max(n.size().width, 1))
        label.texture = n
        label.size = CGSize(width: n.size().width * k, height: n.size().height * k)
        label.position = CGPoint(x: side + 6, y: rect.height * 0.64)
        let w = CardFaceFactory.shared.numeral(String(count), size: labelSize, fill: UIColor(Palette.yellow), outline: 2)
        wins.texture = w
        wins.size = w.size()
        wins.position = CGPoint(x: rect.width - w.size().width / 2 - 4, y: rect.height * 0.64)
        let full = rect.width - side - 10
        let f = CGFloat(max(height + 1, 0)) / CGFloat(Tumble.height)
        bar.color = f > 0.66 ? UIColor(Palette.refuse) : UIColor(Palette.lime)
        bar.size = CGSize(width: max(full * min(f, 1), 2), height: max(rect.height * 0.14, 3))
        bar.position = CGPoint(x: side + 6, y: rect.height * 0.18)
        alpha = out ? 0.55 : 1
    }
}
