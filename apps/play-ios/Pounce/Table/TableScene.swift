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
    /// The selected hand card (Task 16 sets it); drawn lifted above its neighbors.
    var liftedCard: CardID? {
        didSet { if liftedCard != oldValue { redraw() } }
    }

    var safeInsets: UIEdgeInsets = .zero {
        didSet { if safeInsets != oldValue { redraw() } }
    }

    // Turn and round when `revealed` was handed over.
    private var revealedTurn: Seat?
    private var revealedRound: Int?
    private var shownRevealed: Seat?

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
    private var accessibilityCache: (version: Int, elements: [UIAccessibilityElement])?
    private var accessibilityVersion = 0

    private static let menuSize: CGFloat = 32

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

    /// Plays one store intent. This task reconciles for every intent; Tasks 16–18 add motion.
    func play(_ intent: TableIntent) async {
        switch intent {
        case .reconcile, .game, .presence, .versusIntro, .rejected:
            reconcileFromStore()
        case .lobbyNope:
            break
        }
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
            opponents.update(model: model, bottom: bottom, layout: layout)
        }

        // Hand: faces only for the revealed seat; backs for a seat of mine that isn't revealed.
        let content: HandNode.Content
        if let bottom, bottom == shownRevealed, let cards = game.hands[bottom] {
            content = .faces(cards)
        } else if let bottom, model.mySeats.contains(bottom) {
            content = .backs(game.handCounts[safe: bottom] ?? 0)
        } else {
            content = .none
        }
        let dimmed = !(model.isMyTurn && model.currentSeat == bottom)
        hand.update(content, layout: layout, lifted: liftedCard, dimmed: dimmed)

        // Phase goal trays above a revealed hand.
        if case .faces = content, let bottom {
            trays.isHidden = false
            trays.update(requirements: model.trays(for: bottom), layout: layout)
        } else {
            trays.isHidden = true
            trays.update(requirements: [], layout: layout)
        }

        menuButton.isHidden = false
        // Top-right: in the status bar's right ear when the safe top is tall enough (notch /
        // island phones), else tucked into the bar's corner.
        let menuY = safeInsets.top >= 44
            ? layout.opponentsBar.maxY + Self.menuSize / 2 - 6
            : layout.opponentsBar.maxY - Self.menuSize / 2
        menuButton.position = CGPoint(x: size.width - Self.menuSize / 2 - 10, y: menuY)
    }

    private func clearTable() {
        layout = nil
        bottomSeat = nil
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
        for _ in touches { director.touchBegan() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            director.touchEnded()
            if !menuButton.isHidden, menuFrame.contains(touch.location(in: self)) { onMenu() }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for _ in touches { director.touchEnded() }
    }

    private var menuFrame: CGRect {
        let d = max(Self.menuSize, 44)
        return CGRect(x: menuButton.position.x - d / 2, y: menuButton.position.y - d / 2, width: d, height: d)
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
            items.append(Item(id: "table.opponent.\(seat)", label: label, frame: frame))
        }
        items.append(Item(
            id: "table.deck", label: String(localized: "Draw pile", comment: "VoiceOver: the deck"),
            value: String(game.deckCount), frame: deck.hitFrame))
        let discardLabel = game.discardTop.map { CardNode.label($0) }
            ?? String(localized: "empty", comment: "VoiceOver: an empty pile")
        items.append(Item(
            id: "table.discard",
            label: String(localized: "Discard pile, \(discardLabel)", comment: "VoiceOver: the discard pile and its top card"),
            frame: discard.hitFrame))
        for seat in laidZone.laidSeats {
            let name = SeatInfo.name(model.room.seats[safe: seat])
            let groups = (game.laid[safe: seat] ?? nil) ?? []
            for (g, frame) in laidZone.groupFrames(seat: seat).enumerated() {
                let cards = groups[safe: g]?.cards.map { CardNode.label($0) }.joined(separator: "; ") ?? ""
                items.append(Item(
                    id: "table.group.\(seat).\(g)",
                    label: String(localized: "\(name), group \(g + 1): \(cards)", comment: "VoiceOver: a laid-down group"),
                    frame: frame))
            }
        }
        if !trays.isHidden {
            for (i, req) in trays.requirements.enumerated() where i < trays.frames.count {
                items.append(Item(id: "table.tray.\(i)", label: TrayNode.label(req, index: i), frame: trays.frames[i]))
            }
            if !trays.layDownButton.isHidden {
                items.append(Item(
                    id: "table.laydown", label: String(localized: "Lay down", comment: "VoiceOver: lay down the trays"),
                    frame: trays.layDownButton.frame))
            }
        }
        for (i, node) in hand.cards.enumerated() {
            guard let frame = hand.frame(at: i) else { continue }
            items.append(Item(id: "table.hand.\(i)", label: CardNode.label(node.card), frame: frame))
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

    private func debugItems() -> [TableAccessibility.Item] {
        #if DEBUG
        let director = director
        return [TableAccessibility.Item(
            id: "table.frames", label: "frames", frame: CGRect(x: 0, y: 0, width: 24, height: 24),
            traits: .staticText, live: { String(director.framesRendered) })]
        #else
        return []
        #endif
    }
}
