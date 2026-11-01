import PounceKit
import SpriteKit
import SwiftUI

/// The game table (spec §5.7, §8). Draws a `TableModel` with positions from PounceKit's
/// `TableLayout`, computed for the real view size (`.resizeFill`). `reconcile` is idempotent and
/// never animates; motion comes from intents through the `AnimationDirector`, which also pauses
/// the view whenever nothing moves.
///
/// Privacy: face-up hand nodes exist only for `revealed`, a seat this phone controls. Without a
/// revealed seat the hand is face-down backs. `TableScreen` owns pass-and-play and passes
/// `revealed`; between its calls the scene hides the hand on a multi-seat phone as soon as the
/// turn or round moves, so a reveal never outlives the turn it was made for.
@MainActor
final class TableScene: SKScene {
    /// zPosition bands. Everything inside a layer stays below the next band.
    enum Layer: CGFloat {
        case background = 0, rug = 10, piles = 20, laidZone = 30, tower = 40, opponents = 50
        case trays = 60, hand = 70, drag = 90, fx = 100
    }

    let store: RoomStore
    let director = AnimationDirector(view: nil)
    /// The paw button top-right (`table.menu`).
    var onMenu: () -> Void = {}

    private(set) var model: TableModel?
    /// The seat whose hand may show face up, as last set by `reconcile(_:revealed:)`.
    private(set) var revealed: Seat?
    /// The seat drawn at the bottom (hand, trays); others go in the opponents bar.
    private(set) var bottomSeat: Seat?
    private(set) var layout: TableLayout?
    /// The selected hand card (tap-tap: select, then tap a target); drawn lifted above its
    /// neighbors. Cleared when it leaves the hand.
    var liftedCard: CardID? {
        get { selection }
        set {
            guard newValue != selection else { return }
            selection = newValue
            redraw()
        }
    }
    private var selection: CardID?

    // Interaction state (TableInput.swift).
    var input = TableInputState()
    /// The lay-down trays' contents for the bottom seat (spec §5.8).
    var trayState = TrayState(requirements: [])
    private var trayKey: TrayKey?
    /// Local hand order per seat (sort toggle, drag-to-reorder).
    var handOrders: [Seat: HandOrder] = [:]
    /// The card being dragged: left out of the hand and the trays while it follows the finger.
    var dragCard: CardID? {
        didSet { if dragCard != oldValue { redraw() } }
    }
    /// A played card shown at its target until the server answers (`provisionalMove`).
    private(set) var provisionalCard: CardID?
    private var provisionalNode: CardNode?
    /// What the in-flight action was, so a rejection nopes the right thing.
    var lastAct: LastAct?
    /// The glows drawn by the last redraw.
    private(set) var glows = Glows()

    var safeInsets: UIEdgeInsets = .zero {
        didSet { if safeInsets != oldValue { redraw() } }
    }

    // Turn and round when `revealed` was handed over.
    private var revealedTurn: Seat?
    private var revealedRound: Int?
    /// The seat whose hand is actually shown face up right now.
    private(set) var shownRevealed: Seat?

    // Layers and nodes.
    private let layers: [Layer: SKNode]
    private let background = SKSpriteNode(texture: TableArt.image(ArtName.roomBg))
    private let rug = SKSpriteNode(texture: TableArt.table(ArtName.rug))
    let deck = PileNode(kind: .deck)
    let discard = PileNode(kind: .discard)
    let laidZone = LaidZoneNode()
    let tower = TowerNode()
    let opponents = OpponentsNode()
    let trays = TrayNode()
    let hand = HandNode()
    private let menuButton = SKSpriteNode(texture: TableArt.image(ArtName.iconPawMenu))
    /// Hand sort toggle (number / coat), local only.
    let sortButton = SKSpriteNode(texture: TableArt.image(ArtName.iconSort))
    private var accessibilityCache: (version: Int, elements: [UIAccessibilityElement])?
    private var accessibilityVersion = 0

    private static let menuSize: CGFloat = 32
    private static let sortSize: CGFloat = 36

    init(store: RoomStore) {
        self.store = store
        var made: [Layer: SKNode] = [:]
        for layer in [Layer.background, .rug, .piles, .laidZone, .tower, .opponents, .trays, .hand, .drag, .fx] {
            let node = SKNode()
            node.zPosition = layer.rawValue
            made[layer] = node
        }
        layers = made
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = UIColor(Palette.night)
        TableArt.preload()

        for layer in made.values { addChild(layer) }
        made[.background]?.addChild(background)
        made[.rug]?.addChild(rug)
        made[.piles]?.addChild(deck)
        made[.piles]?.addChild(discard)
        made[.laidZone]?.addChild(laidZone)
        made[.tower]?.addChild(tower)
        made[.opponents]?.addChild(opponents)
        made[.opponents]?.addChild(menuButton)
        made[.trays]?.addChild(trays)
        made[.hand]?.addChild(hand)
        menuButton.size = CGSize(width: Self.menuSize, height: Self.menuSize)
        menuButton.zPosition = 9
        made[.trays]?.addChild(sortButton)
        sortButton.size = CGSize(width: Self.sortSize, height: Self.sortSize)
        sortButton.zPosition = 4
        sortButton.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The node for a layer (drag and fx layers are empty until something animates).
    func layer(_ layer: Layer) -> SKNode { layers[layer]! }

    // MARK: lifecycle

    override func didMove(to view: SKView) {
        director.view = view
        safeInsets = view.safeAreaInsets
        redraw()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        redraw()
    }

    override func update(_ currentTime: TimeInterval) {
        director.frame(currentTime)
    }

    // MARK: reconcile

    /// Draws `model` exactly, without animation. `revealed` is the only seat whose hand may
    /// show face up (ignored unless this phone controls it).
    func reconcile(_ model: TableModel, revealed: Seat?) {
        self.model = model
        self.revealed = revealed.flatMap { model.mySeats.contains($0) ? $0 : nil }
        revealedTurn = model.currentSeat
        revealedRound = model.game?.round
        shownRevealed = self.revealed
        redraw()
    }

    /// Plays one store intent. Tasks 17–18 add motion.
    func play(_ intent: TableIntent) async {
        switch intent {
        case .reconcile:
            // A snapshot is the truth: a provisional card is either gone from the hand or back.
            clearProvisional()
            lastAct = nil
            reconcileFromStore()
        case .rejected:
            reconcileFromStore()
            rejected()
        case .game, .presence, .versusIntro:
            reconcileFromStore()
        case .lobbyNope:
            break
        }
    }

    // MARK: provisional moves

    /// Shows `card` at `point` (scene space) right away while its action is in flight; the
    /// next snapshot replaces it with the truth. Task 17 animates the move.
    func provisionalMove(card: CardID, to point: CGPoint) {
        provisionalMove(card: card, to: point, scale: 1)
    }

    func provisionalMove(card: CardID, to point: CGPoint, scale: CGFloat) {
        provisionalNode?.removeFromParent()
        let node = CardNode(card: card, size: layout?.cardSize ?? CardFaceFactory.cardSize)
        node.position = point
        node.setScale(scale)
        layer(.drag).addChild(node)
        provisionalNode = node
        provisionalCard = card
        redraw()
    }

    /// The in-flight action was refused: the provisional card returns to the hand (Task 17
    /// animates it back) and nopes.
    func rollbackProvisional() {
        guard let card = provisionalCard else { return }
        clearProvisional()
        redraw()
        nope(card: card)
    }

    private func clearProvisional() {
        provisionalNode?.removeFromParent()
        provisionalNode = nil
        provisionalCard = nil
    }

    /// Redraws from the store's room, keeping the last reveal only while it still belongs to
    /// the same turn and round (on a multi-seat phone).
    private func reconcileFromStore() {
        guard let room = store.room else { return }
        let next = TableModel(room: room)
        model = next
        var shown = revealed.flatMap { next.mySeats.contains($0) ? $0 : nil }
        if next.isMultiSeat, next.currentSeat != revealedTurn || next.game?.round != revealedRound {
            shown = nil
        }
        shownRevealed = shown
        redraw()
    }

    /// Lays every node out for the current model, size and insets.
    private func redraw() {
        defer {
            accessibilityVersion += 1
            director.wake()
        }
        // The snap wins: stop director actions on every node this redraw positions.
        for layer in [Layer.background, .rug, .piles, .laidZone, .tower, .opponents, .trays, .hand] {
            director.cancelActions(under: self.layer(layer))
        }
        guard let model, let game = model.game, size.width > 0, size.height > 0 else {
            clearTable()
            return
        }
        let bottom = Self.bottomSeat(model, revealed: shownRevealed)
        bottomSeat = bottom
        let opponentCount = bottom.map { model.opponents(bottom: $0).count } ?? max(game.handCounts.count - 1, 1)
        let layout = TableLayout(
            size: size, safeTop: safeInsets.top, safeBottom: safeInsets.bottom, opponents: max(opponentCount, 1))
        self.layout = layout

        // Room and rug.
        background.isHidden = false
        let bgScale = max(size.width / 390, size.height / 844)
        background.size = CGSize(width: 390 * bgScale, height: 844 * bgScale)
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        let zone = layout.laidZone
        let rugSide = min(zone.width + 36, zone.height * 0.92)
        rug.isHidden = false
        rug.size = CGSize(width: rugSide, height: rugSide)
        rug.position = CGPoint(x: zone.midX, y: (layout.deck.y + zone.midY) / 2)

        // Piles.
        deck.position = layout.deck
        deck.update(count: game.deckCount, top: nil, cardSize: layout.cardSize)
        discard.position = layout.discard
        discard.update(count: game.discardCount, top: game.discardTop, cardSize: layout.cardSize)

        laidZone.update(model: model, layout: layout)
        tower.update(model: model, layout: layout)
        if let bottom {
            let turnedOn = opponents.update(model: model, bottom: bottom, layout: layout)
            for seat in turnedOn { pulseTurn(seat) }
        }

        // Hand: faces only for the revealed seat; backs for a seat of mine that isn't revealed.
        // Cards in trays, in flight or under the finger are left out of the fan.
        let content: HandNode.Content
        var faceUp = false
        if let bottom, bottom == shownRevealed, let cards = game.hands[bottom] {
            faceUp = true
            var order = handOrders[bottom] ?? HandOrder()
            order.sync(cards)
            handOrders[bottom] = order
            syncTrays(model: model, bottom: bottom, hand: cards)
            if let card = provisionalCard, !cards.contains(card) { clearProvisional() }
            var hidden = trayState.cardsInTrays
            for card in [dragCard, provisionalCard].compactMap({ $0 }) { hidden.insert(card) }
            let shown = order.cards.filter { !hidden.contains($0) }
            if let s = selection, !shown.contains(s) { selection = nil }
            content = .faces(shown)
        } else if let bottom, model.mySeats.contains(bottom) {
            content = .backs(game.handCounts[safe: bottom] ?? 0)
        } else {
            content = .none
        }
        if !faceUp {
            selection = nil
            clearProvisional()
            trayState = TrayState(requirements: [])
            trayKey = nil
        }
        let dimmed = !(model.isMyTurn && model.currentSeat == bottom)
        hand.update(content, layout: layout, lifted: selection, dimmed: dimmed)

        // Legal-target glows for the current step and held card.
        let glows = computeGlows()
        self.glows = glows
        deck.setHighlighted(glows.piles.contains(.deck))
        discard.setHighlighted(glows.piles.contains(.discard) || glows.discard)
        for seat in opponents.order { opponents.node(for: seat)?.setTarget(glows.cats.contains(seat)) }
        laidZone.setTargets(glows.groups, enlarged: glows.enlarge, about: CGPoint(x: zone.midX, y: layout.deck.y))

        // Phase goal trays above a revealed hand; before laying down they take cards.
        if faceUp {
            trays.isHidden = false
            trays.update(requirements: trayState.requirements, layout: layout)
            var hidden: Set<CardID> = []
            if let dragCard { hidden.insert(dragCard) }
            trays.show(trayState, hidden: hidden, targets: glows.trays)
            if !glows.layDown { trays.layDownButton.isHidden = true }
        } else {
            trays.isHidden = true
            trays.update(requirements: [], layout: layout)
            trays.layDownButton.isHidden = true
        }
        sortButton.isHidden = !faceUp || hand.cards.count < 2
        sortButton.position = CGPoint(x: size.width - Self.sortSize / 2 - 8, y: layout.traysFrame.maxY + Self.sortSize / 2 + 6)

        menuButton.isHidden = false
        // Top-right: in the status bar's right ear when the safe top is tall enough (notch /
        // island phones), else tucked into the bar's corner.
        let menuY = safeInsets.top >= 44
            ? layout.opponentsBar.maxY + Self.menuSize / 2 - 6
            : layout.opponentsBar.maxY - Self.menuSize / 2
        menuButton.position = CGPoint(x: size.width - Self.menuSize / 2 - 10, y: menuY)
    }

    /// The finite ring pulse + paw pop for the seat whose turn just came (Task 17 adds the full
    /// turn handoff). Runs through the director so the view pauses again afterwards.
    private func pulseTurn(_ seat: Seat) {
        guard let cat = opponents.node(for: seat) else { return }
        let director = director
        for (action, node) in cat.turnPulse(reduceMotion: UIAccessibility.isReduceMotionEnabled) {
            Task { await director.run(action, on: node, decorative: true) }
        }
    }

    /// Keeps the trays in step with the bottom seat's phase, round and hand. Cards in trays
    /// go back to the hand when the play step ends without a lay-down (spec §5.8).
    private func syncTrays(model: TableModel, bottom: Seat, hand cards: [CardID]) {
        let reqs = model.trays(for: bottom)
        let key = TrayKey(seat: bottom, round: model.game?.round ?? 0)
        if reqs != trayState.requirements || key != trayKey {
            trayState = TrayState(requirements: reqs)
            trayKey = key
        } else if !model.canPlay(bottom), !trayState.cardsInTrays.isEmpty {
            trayState = TrayState(requirements: reqs)
        }
        trayState.keep(only: Set(cards))
    }

    private func clearTable() {
        layout = nil
        bottomSeat = nil
        selection = nil
        clearProvisional()
        sortButton.isHidden = true
        hand.update(.none, layout: TableLayout(size: size, safeTop: 0, safeBottom: 0, opponents: 1), lifted: nil, dimmed: false)
    }

    /// The revealed seat, else my seat whose turn it is, else my first seat.
    static func bottomSeat(_ model: TableModel, revealed: Seat?) -> Seat? {
        if let revealed, model.mySeats.contains(revealed) { return revealed }
        if let turn = model.currentSeat, model.mySeats.contains(turn) { return turn }
        return model.mySeats.first
    }

    // MARK: touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            director.touchBegan()
            inputBegan(touch.location(in: self))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { inputMoved(touch.location(in: self)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            director.touchEnded()
            inputEnded(touch.location(in: self))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for _ in touches {
            director.touchEnded()
            inputCancelled()
        }
    }

    /// Asks for a redraw after an input change (selection, trays, order).
    func refresh() { redraw() }

    var menuHidden: Bool { menuButton.isHidden }

    var menuFrame: CGRect {
        let d = max(Self.menuSize, 44)
        return CGRect(x: menuButton.position.x - d / 2, y: menuButton.position.y - d / 2, width: d, height: d)
    }

    var sortFrame: CGRect {
        let d = max(Self.sortSize, 44)
        return CGRect(x: sortButton.position.x - d / 2, y: sortButton.position.y - d / 2, width: d, height: d)
    }

    var layDownFrame: CGRect {
        let b = trays.layDownButton
        let d = max(b.size.width, 44)
        return CGRect(x: b.position.x - d / 2, y: b.position.y - d / 2, width: d, height: d)
    }

    // MARK: accessibility

    /// The table's accessibility elements for `view`, rebuilt after each redraw.
    func accessibilityElements(in view: SKView) -> [UIAccessibilityElement] {
        if let cache = accessibilityCache, cache.version == accessibilityVersion { return cache.elements }
        let elements = TableAccessibility.elements(accessibilityItems(), scene: self, view: view)
        accessibilityCache = (accessibilityVersion, elements)
        return elements
    }

    private func accessibilityItems() -> [TableAccessibility.Item] {
        typealias Item = TableAccessibility.Item
        var items: [Item] = []
        guard let model, let game = model.game, let layout else { return debugItems() }

        for seat in opponents.order {
            guard let frame = opponents.frame(of: seat) else { continue }
            let label = SeatInfo.label(model.room.seats[safe: seat], cards: game.handCounts[safe: seat], phase: game.phase[safe: seat])
            items.append(Item(
                id: "table.opponent.\(seat)", label: label, value: glows.cats.contains(seat) ? Self.targetValue : nil,
                frame: frame))
        }
        items.append(Item(
            id: "table.deck", label: String(localized: "Draw pile", comment: "VoiceOver: the deck"),
            value: String(game.deckCount), frame: deck.hitFrame, actions: drawActions(.deck)))
        let discardLabel = game.discardTop.map { CardNode.label($0) }
            ?? String(localized: "empty", comment: "VoiceOver: an empty pile")
        items.append(Item(
            id: "table.discard",
            label: String(localized: "Discard pile, \(discardLabel)", comment: "VoiceOver: the discard pile and its top card"),
            value: discard.highlighted ? Self.targetValue : nil,
            frame: discard.hitFrame, actions: drawActions(.discard)))
        for seat in laidZone.laidSeats {
            let name = SeatInfo.name(model.room.seats[safe: seat])
            let groups = (game.laid[safe: seat] ?? nil) ?? []
            for (g, frame) in laidZone.groupFrames(seat: seat).enumerated() {
                let cards = groups[safe: g]?.cards.map { CardNode.label($0) }.joined(separator: "; ") ?? ""
                items.append(Item(
                    id: "table.group.\(seat).\(g)",
                    label: String(localized: "\(name), group \(g + 1): \(cards)", comment: "VoiceOver: a laid-down group"),
                    value: glows.groups.contains(HitTarget(seat: seat, group: g)) ? Self.targetValue : nil,
                    frame: frame))
            }
        }
        if !trays.isHidden {
            for (i, req) in trays.requirements.enumerated() where i < trays.frames.count {
                let valid = trays.valid[safe: i] ?? false
                items.append(Item(
                    id: "table.tray.\(i)", label: TrayNode.label(req, index: i),
                    value: valid ? Self.goldValue : (glows.trays ? Self.targetValue : nil), frame: trays.frames[i]))
                for (j, card) in (trays.shownCards[safe: i] ?? []).enumerated() {
                    guard let frame = trays.frame(of: card) else { continue }
                    items.append(Item(
                        id: "table.traycard.\(i).\(j)", label: CardNode.label(card), frame: frame,
                        actions: trayCardActions(card, tray: i, index: j)))
                }
            }
            if !trays.layDownButton.isHidden {
                items.append(Item(
                    id: "table.laydown", label: String(localized: "Lay down", comment: "VoiceOver: lay down the trays"),
                    frame: layDownFrame))
            }
        }
        for (i, node) in hand.cards.enumerated() {
            guard let frame = hand.frame(at: i) else { continue }
            let selected = node.card != nil && node.card == liftedCard
            items.append(Item(
                id: "table.hand.\(i)", label: CardNode.label(node.card),
                value: selected ? String(localized: "selected", comment: "VoiceOver: the picked-up hand card") : nil,
                frame: frame, traits: selected ? [.button, .selected] : .button,
                actions: node.card.map(handCardActions) ?? []))
        }
        if !sortButton.isHidden {
            items.append(Item(
                id: "table.sort", label: String(localized: "Sort hand", comment: "VoiceOver: sort the hand by number or coat"),
                frame: sortFrame))
        }
        items.append(Item(
            id: "table.menu", label: String(localized: "Table menu", comment: "VoiceOver: the paw menu button"),
            frame: menuFrame))
        let mine = model.isMyTurn
        let whose = mine
            ? String(localized: "Your turn", comment: "VoiceOver: it is this phone's turn")
            : String(localized: "\(SeatInfo.name(model.room.seats[safe: game.turn]))'s turn", comment: "VoiceOver: whose turn it is")
        let bar = layout.opponentsBar
        items.append(Item(
            id: "table.turn", label: whose, value: mine ? "mine" : "other",
            frame: CGRect(x: bar.midX - 22, y: bar.maxY, width: 44, height: min(44, max(safeInsets.top, 20))),
            traits: [.staticText, .updatesFrequently]))
        return items + debugItems()
    }

    /// Spoken value on a glowing drop target (and read by UI tests).
    static let targetValue = String(localized: "glowing", comment: "VoiceOver: a legal target for the held card")
    static let goldValue = String(localized: "ready", comment: "VoiceOver: a lay-down tray that is valid")

    private func debugItems() -> [TableAccessibility.Item] {
        #if DEBUG
        let director = director
        let store = store
        return [
            TableAccessibility.Item(
                id: "table.frames", label: "frames", frame: CGRect(x: 0, y: 0, width: 24, height: 24),
                traits: .staticText, live: { String(director.framesRendered) }),
            // step|inFlight|hand size|laid (UI tests only).
            TableAccessibility.Item(
                id: "table.debug", label: "debug", frame: CGRect(x: 24, y: 0, width: 24, height: 24),
                traits: .staticText, live: { [weak self] in
                    guard let self, let game = store.room?.game else { return "-" }
                    let seat = self.bottomSeat ?? -1
                    let laid = (game.laid[safe: seat] ?? nil) != nil
                    return "\(game.step.rawValue)|\(store.actionInFlight ? 1 : 0)|\(game.hands[seat]?.count ?? -1)|\(laid ? 1 : 0)|\(game.turn)"
                }),
        ]
        #else
        return []
        #endif
    }
}
