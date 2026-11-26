import PounceKit
import SpriteKit
import SwiftUI

/// Birdwatch's table (design §5.2). Top to bottom on a phone: the paw menu, the window with every
/// other seat's cat around it and the sill in its middle (the trick, the trump badge, the bid chip),
/// the score strip, and this seat's hand. The hand's phases (bid, trump, partner) are SwiftUI
/// panels over the sill (`BirdStage`); putting cards back happens on the hand itself.
///
/// `redraw` is idempotent: it lays every node out from the store's room (`model`), the hand from
/// the seat pass-and-play has revealed (read at every redraw, so a reveal never outlives its turn).
/// Events animate through `enqueue`, in server order; the snapshot that follows each action
/// redraws the truth.
///
/// Privacy: hand cards exist as nodes only for the one seat this phone may show. The partner heart
/// is drawn only from `youArePartner` and only on that seat's face-up hand. A TV (`isScreen`) has
/// no hand, no controls and no private marks, whatever the room says.
@MainActor
final class BirdScene: SKScene {
    enum Layer: CGFloat {
        case background = 0, window = 5, seats = 20, sill = 30, trick = 35, chrome = 40, strip = 45, hand = 60, drag = 90, fx = 100
    }

    let store: RoomStore
    /// A TV's table: its store joined the room as a screen. Fixed for the scene's life.
    let isScreen: Bool
    let banner = TVBanner()

    // What the shell hears about.
    var onMenu: () -> Void = {}
    var onSwipeHome: () -> Void = {}
    var onGameOver: ([Seat]) -> Void = { _ in }
    /// The seat whose hand is face up changed (nil: none).
    var onShownSeat: (Seat?) -> Void = { _ in }
    /// The score strip was tapped: the score sheet.
    var onScores: () -> Void = {}
    /// A hand ended: the summary card.
    var onHandOver: (BirdHandResult) -> Void = { _ in }
    /// A tap the table refused, in a few words ("Follow suit").
    var onNope: (String) -> Void = { _ in }
    /// How many cards are marked to put back changed (nest).
    var onPutBack: (Int) -> Void = { _ in }
    /// A tap on the table while this phone can't act: the shell hides a peeked hand.
    var onTableTap: () -> Void = {}
    /// Where UI tips can point, in the view's points from its top-left corner.
    var onTipSpots: ([String: CGRect]) -> Void = { _ in }
    var onAnnounce: (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }
    /// The sill in the view's points (top-left origin): where the stage puts the phase panels.
    var onSill: (CGRect) -> Void = { _ in }
    /// The top of the hand's band, in points from the bottom edge: what the curtain covers.
    var onBand: (CGFloat) -> Void = { _ in }

    /// A TV shows this table: draw just the hand (the stage puts the status line over it).
    var handOnly = false {
        didSet { if handOnly != oldValue { redraw() } }
    }

    var safeInsets: UIEdgeInsets = .zero {
        didSet { if safeInsets != oldValue { redraw() } }
    }

    // Drawn state.
    private(set) var model: BirdTableModel?
    private(set) var layout: BirdLayout?
    private(set) var shownSeat: Seat? {
        didSet { if shownSeat != oldValue { onShownSeat(shownSeat) } }
    }
    /// The hand as drawn, left to right.
    private(set) var handShown: [BirdCardID] = []
    /// The seats around the window, in `layout.seatSpots` order.
    private(set) var barSeats: [Seat] = []
    /// A card lifted by a first tap.
    var lifted: BirdCardID?
    /// Nest: the cards marked to put back.
    private(set) var putBack: Set<BirdCardID> = [] {
        didSet { if putBack != oldValue { onPutBack(putBack.count) } }
    }
    /// A card this phone played, flying to the sill until its snapshot lands.
    private var provisional: BirdCardID?
    var drawnSeq = -1
    private var playChain: Task<Void, Never>?
    private var reportedOver = false
    /// Signs to pop on the next redraw (a bid or pass just landed), and a fresh deal to fan in.
    private var popSigns: Set<Seat> = []
    private var dealIn = false
    private var popTrump = false
    private var lastTipSpots: [String: CGRect] = [:]
    var accessibilityVersion = 0
    var accessibilityCache: (version: Int, elements: [UIAccessibilityElement])?
    /// Interaction (BirdInput.swift).
    var press: Press?

    struct Press {
        var card: BirdCardID?
        var start: CGPoint
        var moved = false
        var onMenu = false
        var onStrip = false
    }

    // Nodes.
    private let background = SKSpriteNode(texture: TableArt.image(ArtName.roomBg))
    private let windowNode = SKSpriteNode()
    private let sillNode = SKSpriteNode()
    private let feeder = SKSpriteNode(texture: TableArt.image(ArtName.Bird.feeder))
    let menuButton = SKSpriteNode(texture: TableArt.image(ArtName.iconPawMenu))
    private let trumpBadge = SKSpriteNode()
    private let bidChip = SKSpriteNode()
    private let bidChipText = SKSpriteNode()
    private let calledCard = SKSpriteNode()
    private let partnerBadge = SKSpriteNode()
    private let partnerText = SKSpriteNode()
    private let mySign = SKSpriteNode()
    private let mySignText = SKSpriteNode()
    private let stripLayer = SKNode()
    var seatNodes: [Seat: BirdSeatNode] = [:]
    var handNodes: [BirdCardID: SKSpriteNode] = [:]
    var trickNodes: [Int: SKSpriteNode] = [:]
    private var glows: [BirdCardID: SKSpriteNode] = [:]
    /// Each strip chip's frame (scene space), for VoiceOver and taps.
    private(set) var stripFrames: [CGRect] = []
    private var transients: [SKNode] = []
    #if DEBUG
    var autoplay: BirdAutoplay?
    #endif

    init(store: RoomStore) {
        self.store = store
        isScreen = store.isScreen
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = UIColor(Palette.night)
        TableArt.preload()
        background.zPosition = Layer.background.rawValue
        addChild(background)
        windowNode.texture = BirdArt.window()
        windowNode.centerRect = BirdArt.sliceCenter
        windowNode.zPosition = Layer.window.rawValue
        addChild(windowNode)
        sillNode.texture = BirdArt.sill()
        sillNode.centerRect = BirdArt.sliceCenter
        sillNode.zPosition = Layer.sill.rawValue
        addChild(sillNode)
        feeder.zPosition = Layer.sill.rawValue + 1
        addChild(feeder)
        menuButton.zPosition = Layer.chrome.rawValue
        menuButton.isHidden = isScreen
        addChild(menuButton)
        for n in [trumpBadge, bidChip, calledCard, partnerBadge, mySign] {
            n.zPosition = Layer.chrome.rawValue
            n.isHidden = true
            addChild(n)
        }
        bidChipText.zPosition = 1
        bidChip.addChild(bidChipText)
        partnerText.zPosition = 1
        partnerBadge.addChild(partnerText)
        mySignText.zPosition = 1
        mySign.addChild(mySignText)
        stripLayer.zPosition = Layer.strip.rawValue
        addChild(stripLayer)
        banner.zPosition = Layer.fx.rawValue
        addChild(banner)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        safeInsets = view.safeAreaInsets
        speed = CGFloat(Pace.factor)
        #if DEBUG
        if autoplay == nil { autoplay = BirdAutoplay.start(self) }
        #endif
        redraw()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        redraw()
    }

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    // MARK: reconcile

    /// Redraws from the store's room: the truth after every snapshot.
    func reconcileFromStore() {
        let work = FrameWork("bird.reconcile"); defer { work.end() }
        guard let room = store.room, let model = BirdTableModel(room: room) else {
            self.model = nil
            redraw()
            return
        }
        self.model = model
        drawnSeq = store.settledSeq
        for node in transients { node.removeFromParent() }
        transients.removeAll()
        provisional = nil
        let seat = currentReveal(model)
        let hand = seat.flatMap(model.hand) ?? []
        if let lifted, !hand.contains(lifted) || !model.isMyTurn { self.lifted = nil }
        if model.view.phase == .nest, seat == model.view.turn {
            putBack = putBack.intersection(hand)
        } else {
            putBack = []
        }
        redraw()
        if !reportedOver, room.status == .over || model.view.status == .over {
            reportedOver = true
            onGameOver(model.view.winners)
        }
    }

    /// The store changed outside an animation (the pass-and-play reveal, a presence change).
    func refresh() {
        guard model != nil else { return reconcileFromStore() }
        if let room = store.room, let next = BirdTableModel(room: room), next.view == model?.view {
            model = next
        }
        redraw()
    }

    /// The seat whose hand this phone may show now.
    func currentReveal(_ model: BirdTableModel) -> Seat? {
        guard !isScreen else { return nil }
        let revealed: Seat? = if case .revealed(let s) = store.pass.state { s } else { nil }
        return model.bottomSeat(revealed: revealed)
    }

    // MARK: layout and redraw

    private var textScale: CGFloat {
        let category = UIApplication.shared.preferredContentSizeCategory
        return category.isAccessibilityCategory ? 1.25 : (category > .large ? 1.1 : 1)
    }

    func redraw() {
        guard size.width > 1, size.height > 1 else { return }
        background.size = size
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        guard let model else {
            clearTable()
            return
        }
        let bottom = currentReveal(model)
        shownSeat = bottom
        let seats = isScreen ? Array(0..<model.seatCount) : model.barSeats(bottom: bottom)
        barSeats = seats
        let hand = bottom.flatMap(model.hand) ?? []
        let mode: BirdLayout.Mode = isScreen ? .tv : (handOnly ? .handOnly : .table)
        let layout = BirdLayout(
            size: size, safeTop: safeInsets.top, safeBottom: max(safeInsets.bottom, 6), others: mode == .handOnly ? 0 : seats.count,
            handCount: hand.count, mode: mode)
        self.layout = layout
        drawWindow(layout, model: model)
        drawSeats(layout, model: model, seats: mode == .handOnly ? [] : seats)
        drawSill(layout, model: model, bottom: bottom)
        drawStrip(layout, model: model)
        drawHand(layout, model: model, seat: bottom, cards: hand)
        drawBanner(layout, model: model)
        menuButton.isHidden = isScreen
        let menuSide: CGFloat = layout.roomy ? 40 : 30
        menuButton.size = CGSize(width: menuSide, height: menuSide)
        menuButton.position = layout.menuButton
        accessibilityVersion += 1
        onSill(CGRect(x: layout.sill.minX, y: size.height - layout.sill.maxY, width: layout.sill.width, height: layout.sill.height))
        onBand(layout.hand.maxY + 6)
        publishTipSpots(layout, model: model)
        popSigns.removeAll()
        popTrump = false
    }

    private func clearTable() {
        for node in seatNodes.values { node.removeFromParent() }
        seatNodes.removeAll()
        for node in handNodes.values { node.removeFromParent() }
        handNodes.removeAll()
        for node in trickNodes.values { node.removeFromParent() }
        trickNodes.removeAll()
        stripLayer.removeAllChildren()
        windowNode.isHidden = true
        sillNode.isHidden = true
        feeder.isHidden = true
        handShown = []
    }

    private func drawWindow(_ layout: BirdLayout, model: BirdTableModel) {
        let shows = layout.mode != .handOnly
        windowNode.isHidden = !shows
        windowNode.size = layout.window.insetBy(dx: 6, dy: 0).size
        windowNode.position = CGPoint(x: layout.window.midX, y: layout.window.midY)
        sillNode.isHidden = !shows
        sillNode.size = layout.sill.size
        sillNode.position = CGPoint(x: layout.sill.midX, y: layout.sill.midY)
        // The feeder waits on the sill while the table bids; it goes to the bid winner.
        let feederUp = shows && model.view.phase == .bidding && model.isLive
        feeder.isHidden = !feederUp
        let side = min(layout.sill.height * 0.36, layout.roomy ? 120 : 64)
        feeder.size = CGSize(width: side, height: side)
        feeder.position = CGPoint(x: layout.sill.midX, y: layout.sill.maxY - side * 0.62)
    }

    private func drawSeats(_ layout: BirdLayout, model: BirdTableModel, seats: [Seat]) {
        let keep = Set(seats)
        for (seat, node) in seatNodes where !keep.contains(seat) {
            node.removeFromParent()
            seatNodes[seat] = nil
        }
        let names = SeatInfo.names(model.room)
        let maxTag = layout.mode == .tv ? 360 : min(layout.catSide * 1.6, layout.size.width / CGFloat(max(min(seats.count, 3), 1)) - 8)
        for (i, seat) in seats.enumerated() {
            let view = model.room.seats[safe: seat]
            let catIndex = SeatInfo.catIndex(view)
            var node = seatNodes[seat]
            if node == nil || node?.side != layout.catSide || node?.catIndex != catIndex {
                node?.removeFromParent()
                let made = BirdSeatNode(seat: seat, catIndex: catIndex, side: layout.catSide)
                made.zPosition = Layer.seats.rawValue
                addChild(made)
                seatNodes[seat] = made
                node = made
            }
            guard let node else { continue }
            node.position = layout.seatSpots[safe: i] ?? .zero
            // A tag never runs off the screen's edge.
            let room = 2 * min(node.position.x, size.width - node.position.x) - 16
            let partner = !isScreen && model.partnerMark(for: seat, revealed: shownSeat)
            node.update(
                name: names[safe: seat] ?? "", active: model.currentSeat == seat, count: model.handCount(seat),
                ribbon: model.ribbon(of: seat), dealer: model.view.dealer == seat && model.isLive, sign: model.sign(seat),
                partner: partner, bot: view?.kind == .bot, left: view?.isTakenOver ?? false, presence: view?.presence,
                maxTagWidth: min(maxTag, max(room, layout.catSide * 1.2)), textScale: layout.mode == .tv ? 2.4 : textScale)
            if popSigns.contains(seat) { node.popSign(reduceMotion: reduceMotion) }
        }
    }

    /// The seat's spot on the table: its cat, or nil for the bottom seat (this phone's hand).
    func spot(of seat: Seat) -> CGPoint? {
        guard let i = barSeats.firstIndex(of: seat), let layout else { return nil }
        return layout.seatSpots[safe: i]
    }

    private func drawSill(_ layout: BirdLayout, model: BirdTableModel, bottom: Seat?) {
        // The trick, each card toward the cat that played it.
        let trick = model.view.trick
        var keep: Set<Int> = []
        for (i, played) in trick.enumerated() {
            keep.insert(i)
            let node = trickNodes[i] ?? {
                let n = SKSpriteNode()
                addChild(n)
                trickNodes[i] = n
                return n
            }()
            node.texture = BirdCardFactory.shared.face(played.card)
            node.size = layout.sillCard
            node.zRotation = 0
            node.setScale(1)
            node.zPosition = Layer.trick.rawValue + CGFloat(i)
            node.position = layout.sillSpot(toward: played.seat == bottom ? nil : spot(of: played.seat))
        }
        for (i, node) in trickNodes where !keep.contains(i) {
            node.removeFromParent()
            trickNodes[i] = nil
        }
        // A TV shows the trick: the phone at its table shows just the hand.
        for node in trickNodes.values { node.isHidden = layout.mode == .handOnly }
        // Trump: a glowing badge in the sill's corner.
        if let trump = model.view.trump {
            trumpBadge.isHidden = false
            trumpBadge.texture = BirdCardFactory.shared.trumpBadge(trump)
            let side: CGFloat = layout.mode == .tv ? 120 : (layout.roomy ? 64 : 44)
            trumpBadge.size = CGSize(width: side, height: side)
            // At a TV's table the phone keeps trump in view, at the top right.
            trumpBadge.position = layout.mode == .handOnly
                ? CGPoint(x: size.width - side / 2 - 14, y: layout.topBand.midY)
                : layout.trumpBadge
            if popTrump, !reduceMotion {
                trumpBadge.setScale(0.2)
                trumpBadge.run(.sequence([.scale(to: 1.25, duration: 0.18).eased(.easeOut), .scale(to: 1, duration: 0.12)]))
            }
        } else {
            trumpBadge.isHidden = true
        }
        // The hand's bid on a chip in the other corner, with the called card in five.
        if let high = model.view.high, model.view.phase != .bidding, model.isLive || model.view.phase == .between,
           layout.mode != .handOnly {
            let size: CGFloat = layout.mode == .tv ? 40 : (layout.roomy ? 22 : 16)
            let words = CardFaceFactory.shared.numeral(
                String(localized: "Bid \(high.amount)", comment: "Birdwatch: the hand's bid on the sill"), size: size, outline: 3)
            bidChipText.texture = words
            bidChipText.size = words.size()
            bidChip.texture = BirdArt.sign(UIColor(Palette.orange))
            bidChip.centerRect = BirdArt.sliceCenter
            bidChip.size = CGSize(width: words.size().width + size, height: words.size().height + size * 0.6)
            bidChip.position = layout.mode == .tv
                ? CGPoint(x: layout.sill.minX + bidChip.size.width / 2, y: layout.bidChip.y)
                : CGPoint(x: layout.sill.minX + bidChip.size.width / 2 + 8, y: layout.trumpBadge.y)
            bidChip.isHidden = false
        } else {
            bidChip.isHidden = true
        }
        if let called = model.view.called, model.view.partner == nil, model.isLive, layout.mode != .handOnly {
            calledCard.isHidden = false
            calledCard.texture = BirdCardFactory.shared.face(called)
            // The called card, small, beside the trump badge: public, so everyone sees it.
            let w = layout.sillCard.width * 0.7
            calledCard.size = CGSize(width: w, height: w * BirdLayout.cardAspect)
            calledCard.position = layout.mode == .tv
                ? CGPoint(x: layout.trumpBadge.x - trumpBadge.size.width / 2 - w * 0.7, y: layout.sill.maxY + calledCard.size.height / 2 + 8)
                : CGPoint(x: layout.trumpBadge.x - trumpBadge.size.width / 2 - w * 0.7, y: layout.sill.maxY - calledCard.size.height / 2 - 6)
        } else {
            calledCard.isHidden = true
        }
        // This seat's own sign, where its card goes, while the table bids.
        if let bottom, let sign = model.sign(bottom), model.view.phase == .bidding, layout.mode == .table {
            let text: String = switch sign {
            case .bid(let n): String(localized: "You bid \(n)", comment: "Birdwatch: this seat's bid, on the sill")
            case .pass: String(localized: "You passed", comment: "Birdwatch: this seat passed, on the sill")
            default: ""
            }
            let words = CardFaceFactory.shared.numeral(text, size: layout.roomy ? 22 : 16, outline: 3)
            mySignText.texture = words
            mySignText.size = words.size()
            mySign.texture = BirdArt.sign(UIColor(sign == .pass ? Palette.violet : Palette.orange))
            mySign.centerRect = BirdArt.sliceCenter
            mySign.size = CGSize(width: words.size().width + 20, height: words.size().height + 12)
            mySign.position = CGPoint(x: layout.sill.midX, y: layout.sill.minY + mySign.size.height / 2 + 10)
            mySign.isHidden = false
            if popSigns.contains(bottom) { BirdScene.pop(mySign, reduceMotion: reduceMotion) }
        } else {
            mySign.isHidden = true
        }
    }

    static func pop(_ node: SKNode, reduceMotion: Bool) {
        guard !reduceMotion else { return }
        node.setScale(0.3)
        node.run(.sequence([.scale(to: 1.15, duration: 0.12).eased(.easeOut), .scale(to: 1, duration: 0.1)]))
    }

    private func drawStrip(_ layout: BirdLayout, model: BirdTableModel) {
        stripLayer.removeAllChildren()
        stripFrames = []
        guard layout.strip.width > 0 else { return }
        let sides = model.sides
        let n = CGFloat(max(sides.count, 1))
        let gap: CGFloat = layout.mode == .tv ? 24 : (sides.count > 3 ? 4 : 6)
        let width = (layout.strip.width - gap * (n - 1)) / n
        let tv = layout.mode == .tv
        for (i, side) in sides.enumerated() {
            let frame = CGRect(
                x: layout.strip.minX + CGFloat(i) * (width + gap), y: layout.strip.minY, width: width, height: layout.strip.height)
            stripFrames.append(frame)
            let fill = side.ribbon.map(BirdArt.ribbon) ?? UIColor(Palette.violet)
            let chip = SKSpriteNode(texture: BirdArt.chip(fill, lit: side.bidding && model.view.phase != .bidding))
            chip.centerRect = BirdArt.sliceCenter
            chip.size = frame.size
            chip.position = CGPoint(x: frame.midX, y: frame.midY)
            stripLayer.addChild(chip)
            // The side's cats, small, at the left.
            let head = min(frame.height * 0.7, tv ? 64 : (sides.count > 3 ? 20 : 26))
            var x = frame.minX + 6 + head / 2
            for seat in side.seats.prefix(2) {
                let cat = SKSpriteNode(texture: TableArt.cat(SeatInfo.catIndex(model.room.seats[safe: seat]), .idle))
                cat.size = CGSize(width: head, height: head)
                cat.position = CGPoint(x: x, y: frame.midY)
                cat.zPosition = 1
                stripLayer.addChild(cat)
                x += head * 0.7
            }
            let numberSize: CGFloat = tv ? 46 : (layout.roomy ? 24 : 17) * min(textScale, 1.15)
            let score = CardFaceFactory.shared.numeral(String(side.score), size: numberSize.rounded(), outline: 3)
            let scoreNode = SKSpriteNode(texture: score)
            var scoreSize = score.size()
            let room = frame.maxX - (x + head * 0.1) - 6
            if scoreSize.width > room { scoreSize = CGSize(width: room, height: scoreSize.height * room / scoreSize.width) }
            scoreNode.size = scoreSize
            let showTaken = model.view.phase == .play || model.view.phase == .between
            let takenText = side.taken > 0 ? "+\(side.taken)" : ""
            scoreNode.position = CGPoint(
                x: frame.maxX - 6 - scoreSize.width / 2, y: frame.midY + (showTaken && !takenText.isEmpty ? scoreSize.height * 0.18 : 0))
            scoreNode.zPosition = 2
            stripLayer.addChild(scoreNode)
            if showTaken, !takenText.isEmpty {
                let taken = CardFaceFactory.shared.numeral(takenText, size: (numberSize * 0.62).rounded(), fill: UIColor(Palette.yellow), outline: 2)
                let takenNode = SKSpriteNode(texture: taken)
                takenNode.size = taken.size()
                takenNode.position = CGPoint(x: frame.maxX - 6 - taken.size().width / 2, y: scoreNode.position.y - scoreSize.height * 0.62)
                takenNode.zPosition = 2
                stripLayer.addChild(takenNode)
            }
        }
    }

    private func drawHand(_ layout: BirdLayout, model: BirdTableModel, seat: Seat?, cards: [BirdCardID]) {
        handShown = cards
        let keep = Set(cards)
        for (card, node) in handNodes where !keep.contains(card) {
            node.removeFromParent()
            handNodes[card] = nil
        }
        for (card, node) in glows where !keep.contains(card) {
            node.removeFromParent()
            glows[card] = nil
        }
        // The partner's own mark, over the hand.
        if let seat, !isScreen, model.partnerMark(for: seat, revealed: shownSeat) {
            let words = CardFaceFactory.shared.numeral(
                String(localized: "You're the partner", comment: "Birdwatch: over the partner's own hand (five players)"),
                size: layout.roomy ? 20 : 15, fill: UIColor(Palette.ink), outline: 0.01)
            partnerText.texture = words
            partnerText.size = words.size()
            partnerBadge.texture = BirdArt.sign(UIColor(Palette.yellow))
            partnerBadge.centerRect = BirdArt.sliceCenter
            partnerBadge.size = CGSize(width: words.size().width + 22, height: words.size().height + 10)
            // On the sill's top edge, between the bid chip and the trump badge (in the room over
            // the hand at a TV).
            partnerBadge.position = layout.mode == .handOnly
                ? CGPoint(x: layout.hand.midX, y: layout.hand.maxY + partnerBadge.size.height / 2 + 4)
                : CGPoint(x: layout.sill.midX, y: layout.sill.maxY - partnerBadge.size.height / 2 - 4)
            partnerBadge.zPosition = Layer.hand.rawValue + 40
            partnerBadge.isHidden = false
        } else {
            partnerBadge.isHidden = true
        }
        guard let seat, !cards.isEmpty else { return }
        let slots = layout.handSlots(count: cards.count)
        let playable = model.playable(seat)
        let myPlay = model.view.phase == .play && model.currentSeat == seat
        let nest = model.view.phase == .nest && model.currentSeat == seat
        let fromNest = Set(nest ? (model.view.fromNest ?? []) : [])
        let fresh = dealIn
        dealIn = false
        for (i, card) in cards.enumerated() {
            let node = handNodes[card] ?? {
                let n = SKSpriteNode(texture: BirdCardFactory.shared.face(card))
                addChild(n)
                handNodes[card] = n
                return n
            }()
            if card == provisional { continue }
            node.texture = BirdCardFactory.shared.face(card)
            node.size = layout.cardSize
            node.zRotation = 0
            node.setScale(1)
            node.zPosition = Layer.hand.rawValue + CGFloat(i)
            var target = slots[safe: i] ?? .zero
            if card == lifted { target.y += layout.cardSize.height * 0.2 }
            let marked = putBack.contains(card)
            if marked { target.y -= layout.cardSize.height * 0.12 }
            // Dimmed by colour, never by alpha: overlapping cards must not show through.
            let dim = (myPlay && !playable.contains(card)) || marked
            node.color = UIColor(Palette.ink)
            node.colorBlendFactor = dim ? 0.55 : 0
            if fresh, !reduceMotion, let layout = self.layout {
                node.position = CGPoint(x: layout.sill.midX, y: layout.sill.midY)
                node.setScale(0.4)
                node.run(.sequence([
                    .wait(forDuration: 0.04 * Double(i)),
                    .group([.move(to: target, duration: 0.28).eased(.easeOut), .scale(to: 1, duration: 0.28)]),
                ]))
            } else {
                node.removeAction(forKey: "slide")
                if node.position == .zero || press?.card == card {
                    node.position = target
                } else {
                    node.run(.move(to: target, duration: 0.12).eased(.easeOut), withKey: "slide")
                }
            }
            if fromNest.contains(card) {
                let glow = glows[card] ?? {
                    let g = SKSpriteNode(texture: BirdArt.cardGlow())
                    g.centerRect = BirdArt.sliceCenter
                    g.blendMode = .add
                    addChild(g)
                    glows[card] = g
                    return g
                }()
                glow.size = CGSize(width: layout.cardSize.width + 10, height: layout.cardSize.height + 10)
                glow.position = target
                glow.zPosition = node.zPosition - 0.5
            } else if let glow = glows[card] {
                glow.removeFromParent()
                glows[card] = nil
            }
        }
    }

    private func drawBanner(_ layout: BirdLayout, model: BirdTableModel) {
        guard isScreen else { return }
        if let turn = model.currentSeat, let view = model.room.seats[safe: turn] {
            let rect = CGRect(x: layout.banner.x - 300, y: layout.banner.y - 44, width: 600, height: 88)
            _ = banner.show(
                .turn(seat: turn, name: SeatInfo.name(model.room, turn), cat: SeatInfo.catIndex(view)), banner: rect,
                room: CGRect(x: 0, y: 0, width: size.width - 240, height: 88), unit: 1, pop: false, reduceMotion: reduceMotion)
        } else {
            _ = banner.show(nil, banner: .zero, room: .zero, unit: 1, pop: false, reduceMotion: true)
        }
    }

    /// Tips point at the bid sign, a dimmed card, the trump badge and the partner mark.
    private func publishTipSpots(_ layout: BirdLayout, model: BirdTableModel) {
        guard !isScreen else { return }
        var spots: [String: CGRect] = [:]
        func viewRect(_ node: SKNode, _ size: CGSize) -> CGRect {
            let p = node.convert(CGPoint.zero, to: self)
            return CGRect(x: p.x - size.width / 2, y: self.size.height - p.y - size.height / 2, width: size.width, height: size.height)
        }
        if let (_, node) = seatNodes.first(where: { !$0.value.sign.isHidden }) {
            spots["bird.sign"] = viewRect(node.sign, node.sign.size)
        } else if !mySign.isHidden {
            spots["bird.sign"] = viewRect(mySign, mySign.size)
        }
        if let seat = shownSeat, model.currentSeat == seat, model.view.phase == .play {
            let playable = model.playable(seat)
            if let dim = handShown.first(where: { !playable.contains($0) }), let node = handNodes[dim] {
                spots["bird.dimmed"] = viewRect(node, node.size)
            }
        }
        if !trumpBadge.isHidden { spots["bird.trump"] = viewRect(trumpBadge, trumpBadge.size) }
        if !partnerBadge.isHidden { spots["bird.partner"] = viewRect(partnerBadge, partnerBadge.size) }
        guard spots != lastTipSpots else { return }
        lastTipSpots = spots
        onTipSpots(spots)
    }

    // MARK: moves

    /// Plays `card` from the shown hand: it flies to the sill at once and goes to the server.
    func play(_ card: BirdCardID) {
        guard let model, let seat = shownSeat, model.playable(seat).contains(card), let layout,
              let node = handNodes[card], provisional == nil else { return }
        guard store.actBirdwatch(seat: seat, .play(card)) else { return }
        provisional = card
        lifted = nil
        Haptics.shared.drop()
        Sound.shared.play(ArtName.Sound.sfxFlip, volume: 0.6, kind: .game)
        node.removeAllActions()
        node.zPosition = Layer.trick.rawValue + CGFloat(model.view.trick.count)
        node.colorBlendFactor = 0
        let target = layout.sillSpot(toward: nil)
        let scale = layout.sillCard.width / max(layout.cardSize.width, 1)
        node.run(.group([.move(to: target, duration: 0.2).eased(.easeOut), .scale(to: scale, duration: 0.2)]))
        accessibilityVersion += 1
    }

    /// Marks or unmarks a card to put back (nest).
    func togglePutBack(_ card: BirdCardID) {
        guard let model, let seat = shownSeat, model.view.phase == .nest, model.currentSeat == seat else { return }
        if putBack.contains(card) {
            putBack.remove(card)
        } else if putBack.count < model.view.nestSize {
            putBack.insert(card)
        } else {
            nope(card, words: String(localized: "Put back \(model.view.nestSize)", comment: "Birdwatch: the put-back count is full"))
            return
        }
        Haptics.shared.tick()
        redraw()
    }

    /// Sends the marked cards back: the nest's put-back.
    @discardableResult func sendPutBack() -> Bool {
        guard let model, let seat = shownSeat, putBack.count == model.view.nestSize else { return false }
        return store.actBirdwatch(seat: seat, .nest(BirdTableModel.sorted(Array(putBack), trump: nil)))
    }

    func nope(_ card: BirdCardID?, words: String) {
        Haptics.shared.thump()
        Sound.shared.play(ArtName.Sound.sfxNope, volume: 0.5)
        if let card, let node = handNodes[card] { node.run(Effects.nope()) }
        onNope(words)
    }

    // MARK: intents

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
            provisional = nil
            reconcileFromStore()
            let words: String = switch code {
            case .mustFollow: String(localized: "Follow suit", comment: "Birdwatch: a card refused because the hand holds the suit led")
            case .notYourTurn: String(localized: "Not your turn", comment: "Birdwatch: a move refused, someone else is on the move")
            default: String(localized: "Didn't go", comment: "Birdwatch: a move the table refused")
            }
            nope(nil, words: words)
        case .birdwatch(let event, let seq):
            guard seq > drawnSeq, model != nil else { return }
            hideIfStale()
            await animate(event)
        case .presence, .link:
            guard let room = store.room, let model else { return }
            var next = model.room
            next.seats = room.seats
            self.model = BirdTableModel(room: next)
            redraw()
        case .game, .tiles, .lobbyNope:
            break
        }
    }

    /// Privacy never waits for a snapshot: a shared phone's hand goes face down with its turn.
    private func hideIfStale() {
        guard let model, let seat = shownSeat, model.isMultiSeat else { return }
        if case .revealed(seat) = store.pass.state { return }
        redraw()
    }

    private func animate(_ event: BirdEvent) async {
        guard let layout else { return }
        switch event {
        case .dealt:
            dealIn = true
            Sound.shared.play(ArtName.Sound.sfxWhoosh, volume: 0.5, kind: .game)
        case .bid(let seat, _), .passed(let seat):
            popSigns.insert(seat)
            Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5, kind: .game)
        case .bidWon(let seat, let amount):
            onAnnounce(String(localized: "\(SeatInfo.name(store.room ?? model!.room, seat)) won the bid at \(amount)", comment: "Birdwatch VoiceOver: bidding ended"))
        case .nest(let seat, _):
            guard !feeder.isHidden else { return }
            let to = spot(of: seat) ?? CGPoint(x: layout.hand.midX, y: layout.hand.maxY)
            await run(.group([.move(to: to, duration: 0.35).eased(.easeInEaseOut), .scale(to: 0.3, duration: 0.35)]), on: feeder)
            feeder.isHidden = true
            feeder.setScale(1)
        case .trump(let seat, let suit):
            popTrump = true
            Sound.shared.play(ArtName.Sound.sfxSparkle, volume: 0.5, kind: .game)
            onAnnounce(String(localized: "\(SeatInfo.name(store.room ?? model!.room, seat)) named \(BirdTableModel.suitName(suit)) trump", comment: "Birdwatch VoiceOver: trump named"))
        case .called:
            break
        case .putBack:
            break
        case .turn(let seat):
            // The glow moves on now; the snapshot that follows brings the rest.
            if let room = store.room, let next = BirdTableModel(room: room), var view = model?.view {
                view.turn = seat
                var r = next.room
                r.birdwatch = view
                model = BirdTableModel(room: r)
                redraw()
            }
        case .played(let seat, let card):
            if seat == shownSeat, provisional == card { return }
            let from: CGPoint = spot(of: seat) ?? CGPoint(x: layout.hand.midX, y: layout.hand.midY)
            let index = trickNodes.count + transients.count
            let node = SKSpriteNode(texture: BirdCardFactory.shared.face(card))
            node.size = layout.sillCard
            node.zPosition = Layer.trick.rawValue + CGFloat(index)
            node.position = from
            node.setScale(0.45)
            addChild(node)
            transients.append(node)
            if seat == shownSeat, let hand = handNodes[card] { hand.isHidden = true }
            Sound.shared.play(ArtName.Sound.sfxFlip, volume: 0.5, kind: .game)
            let to = layout.sillSpot(toward: seat == shownSeat ? nil : spot(of: seat))
            await run(.group([.move(to: to, duration: 0.26).eased(.easeOut), .scale(to: 1, duration: 0.26)]), on: node)
        case .partner(let seat):
            if let node = seatNodes[seat], !reduceMotion {
                Sound.shared.play(ArtName.Sound.sfxSparkle, volume: 0.6, kind: .game)
                await run(.sequence([.scale(to: 1.2, duration: 0.15), .scale(to: 1, duration: 0.15)]), on: node)
            }
            onAnnounce(String(localized: "\(SeatInfo.name(store.room ?? model!.room, seat)) is the partner", comment: "Birdwatch VoiceOver: the partner is known"))
        case .trick(let winner, _, let points):
            await wait(reduceMotion ? 0.3 : 0.6)
            let cards = Array(trickNodes.values) + transients.compactMap { $0 as? SKSpriteNode }
            let mine = provisional.flatMap { handNodes[$0] }
            let to = spot(of: winner) ?? CGPoint(x: layout.hand.midX, y: layout.hand.maxY)
            let sweep = SKAction.group([.move(to: to, duration: 0.3).eased(.easeIn), .scale(to: 0.25, duration: 0.3)])
            for node in cards + [mine].compactMap({ $0 }) { node.run(sweep, withKey: "sweep") }
            if points > 0 { floatPoints(points, at: to) }
            await wait(0.32)
            for node in cards + [mine].compactMap({ $0 }) { node.isHidden = true }
        case .handOver(let result, _):
            onHandOver(result)
        case .gameOver(let winners, _, _):
            await wait(0.6)
            if !reportedOver {
                reportedOver = true
                onGameOver(winners)
            }
        }
    }

    /// "+25" rising from where a trick went.
    private func floatPoints(_ points: Int, at point: CGPoint) {
        let t = CardFaceFactory.shared.numeral("+\(points)", size: isScreen ? 44 : 20, fill: UIColor(Palette.yellow), outline: 3)
        let label = SKSpriteNode(texture: t)
        label.size = t.size()
        label.position = point
        label.zPosition = Layer.fx.rawValue
        addChild(label)
        label.run(.sequence([.moveBy(x: 0, y: 40, duration: 0.7).eased(.easeOut), .fadeOut(withDuration: 0.2), .removeFromParent()]))
    }

    private func run(_ action: SKAction, on node: SKNode) async {
        await withCheckedContinuation { continuation in
            node.run(action) { continuation.resume() }
        }
    }

    private func wait(_ seconds: TimeInterval) async {
        await run(.wait(forDuration: seconds), on: self)
    }
}
