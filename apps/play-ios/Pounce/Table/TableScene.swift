import PounceKit
import SpriteKit
import SwiftUI

/// The game table (spec §5.7, §8). Draws a `TableModel` with positions from PounceKit's
/// `TableLayout`, computed for the real view size (`.resizeFill`). `reconcile` is idempotent and
/// never animates; motion comes from intents through the `AnimationDirector`, which also pauses
/// the view whenever nothing moves.
///
/// One timeline (spec §6.2): game intents animate in order over the table as it was, and the
/// `.reconcile` after them (the snapshot that follows every action) snaps to the truth. A
/// `reconcile(_:revealed:epoch:)` from the shell that arrives while the store holds events this
/// scene hasn't played yet only records `revealed`; the coming `.reconcile` intent applies it.
///
/// Privacy: face-up hand nodes exist only for `revealed`, a seat this phone controls. Without a
/// revealed seat the hand is face-down backs. The store decides pass-and-play (`RoomStore.pass`)
/// and `TableScreen` passes its `revealed` with the store turn epoch it was granted in. On a
/// multi-seat phone a reveal counts only while the store is still in that epoch: one that
/// arrives late is dropped, and between the shell's calls the scene hides the hand by itself as
/// soon as the store's epoch moves (a turn, round or status change), so a reveal never outlives
/// the turn it was made for, however late SwiftUI delivers the shell's update.
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
    /// The tower was tapped (`table.tower`): the shell shows the scoreboard for the table as
    /// drawn (never the store's newer truth, which would spoil a celebration still playing).
    var onTower: (TableModel) -> Void = { _ in }
    /// The game is over and its celebration has played (or the table opened finished).
    var onGameOver: ([Seat]) -> Void = { _ in }
    /// The face-up hand changed (a reveal landed or the hand turned face down). The shell
    /// keeps the pass-and-play curtain up until the seat it revealed is actually shown.
    var onShownRevealed: (Seat?) -> Void = { _ in }
    /// A tap on the table itself (rug, piles, empty space) while this phone can't act and
    /// holds no card: the shell hides a peeked hand.
    var onTableTap: () -> Void = {}
    /// The first-game coach's view of the table changed (TableCoach.swift); nil while no hand of
    /// this phone is face up.
    var onCoach: (TableCoach?) -> Void = { _ in }
    /// Spotlight and game-over bookkeeping (Celebrations.swift).
    var celebration = CelebrationState()
    #if DEBUG
    /// What the shell last synced (`TableStage.sync`), read by `table.debug` (UI tests).
    var stageProbe = StageProbe()
    #endif

    private(set) var model: TableModel?
    /// The seat whose hand may show face up, as last set by `reconcile(_:revealed:epoch:)`.
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
    /// A Yarn picked up in a valid run tray (tap path for moving it, spec §13): the next tap on
    /// another slot of that tray moves it there. Callers `refresh()` after changing it.
    var trayYarn: (card: CardID, tray: Int)?

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
    private(set) var provisionalNode: CardNode?
    /// What the in-flight action was, so a rejection nopes the right thing.
    var lastAct: LastAct?
    /// The glows drawn by the last redraw.
    private(set) var glows = Glows()

    var safeInsets: UIEdgeInsets = .zero {
        didSet { if safeInsets != oldValue { redraw() } }
    }

    /// The store turn epoch `revealed` was granted in.
    private var revealedEpoch = -1
    /// The seat whose hand is actually shown face up right now.
    private(set) var shownRevealed: Seat? {
        didSet {
            guard shownRevealed != oldValue else { return }
            #if DEBUG
            timelineLog("shownRevealed \(String(describing: oldValue)) -> \(String(describing: shownRevealed))")
            #endif
            onShownRevealed(shownRevealed)
        }
    }

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
    // Timeline state (IntentAnimations.swift).
    /// Landed flyers that stand in for the truth until the next reconcile snaps it in.
    var transients: [SKNode] = []
    /// A game intent is animating.
    private(set) var animating = false {
        didSet { if animating != oldValue { publishCoach() } }
    }
    /// The store seq this scene has played or drawn up to.
    private var seenSeq = -1
    /// The store seq the drawn table reflects (`RoomStore.settledSeq` when it was drawn): game
    /// events at or below it are already shown (a lagging queue catches up instead of
    /// replaying them). Never `lastSeq`: events past the last snapshot are in `room` only as
    /// turn, step and status, so a redraw between them and their snapshot must not skip them.
    private var drawnSeq = -1
    /// A shell reconcile that arrived mid-timeline: its `revealed` and epoch, applied by the next
    /// `.reconcile` intent (or after `deferLimit` if none comes).
    private var pendingReveal: Reveal?
    private var deferGeneration = 0
    /// The last intent handed to `play`, which the next one waits for.
    private var playChain: Task<Void, Never>?
    private static let deferLimit: Duration = .seconds(3)
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
        director.flourish = { [weak self] in self?.idleFlourish() }
        tower.director = director
        tower.fx = made[.fx]
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    #if DEBUG
    deinit { print("[scene] deinit") }
    #endif

    /// The node for a layer (drag and fx layers are empty until something animates).
    func layer(_ layer: Layer) -> SKNode { layers[layer]! }

    // MARK: lifecycle

    override func didMove(to view: SKView) {
        director.view = view
        safeInsets = view.safeAreaInsets
        redraw()
        #if DEBUG
        if [.replay, .celebrate].contains(DemoMode.from()) { startFrameLog() }
        #endif
        speed = CGFloat(Pace.factor)
    }

    /// Leaving the view (`presentScene(nil)`, the table screen swapped out mid-animation):
    /// nothing will render the rest, so the director gives everything up now and every awaited
    /// intent returns, instead of the intent pipeline waiting forever. Decorative offsets go
    /// back to rest in case the scene is shown again.
    override func willMove(from view: SKView) {
        director.cancelAll()
        for l in [Layer.background, .rug, .piles, .laidZone, .tower, .opponents, .trays, .hand] {
            layer(l).position = .zero
        }
        hand.position = .zero
        for seat in opponents.order { opponents.node(for: seat)?.resetMotion() }
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
    /// show face up (ignored unless this phone controls it and, on a multi-seat phone, unless
    /// `epoch` is still the store's `turnEpoch`).
    ///
    /// Mid-timeline (events still to play, or one animating) the model itself waits for the
    /// coming `.reconcile` intent, but privacy never waits: a reveal that is withdrawn or moves
    /// to another seat hides the shown hand at once (backs, on the table as drawn). Only a new
    /// face-up reveal waits for the timeline.
    func reconcile(_ model: TableModel, revealed: Seat?, epoch: Int) {
        #if DEBUG
        timelineLog("reconcile turn \(model.currentSeat ?? -1) revealed \(String(describing: revealed)) epoch \(epoch)/\(store.turnEpoch) animating \(animating) lastSeq \(store.lastSeq) seen \(seenSeq) pending \(String(describing: pendingReveal))")
        #endif
        let reveal = Reveal(seat: revealed, epoch: epoch)
        if self.model != nil, animating || store.lastSeq > seenSeq {
            if shownRevealed != nil, valid(reveal, in: model) != shownRevealed || hideIfStale() { hideHand() }
            deferReveal(reveal)
            return
        }
        apply(model, reveal)
    }

    /// A shell reveal and the store turn epoch it was granted in.
    private struct Reveal: Equatable {
        let seat: Seat?
        let epoch: Int
    }

    /// The seat `reveal` may show on `model`: one of this phone's, and on a multi-seat phone
    /// only while the store is still in the reveal's epoch.
    private func valid(_ reveal: Reveal, in model: TableModel) -> Seat? {
        guard let seat = reveal.seat, model.mySeats.contains(seat) else { return nil }
        if model.isMultiSeat, reveal.epoch != store.turnEpoch { return nil }
        return seat
    }

    /// A shown hand on a multi-seat phone whose epoch the store has left.
    private func hideIfStale() -> Bool {
        guard let model, model.isMultiSeat, shownRevealed != nil else { return false }
        return revealedEpoch != store.turnEpoch
    }

    /// Turns the shown hand face down now: faces, trays and their accessibility elements go.
    private func hideHand() {
        #if DEBUG
        timelineLog("hide hand \(shownRevealed.map(String.init) ?? "-") now (animating \(animating), lastSeq \(store.lastSeq), seen \(seenSeq))")
        #endif
        revealed = nil
        shownRevealed = nil
        for layer in [layer(.fx), layer(.drag)] {
            for case let card as CardNode in layer.children where card.isPrivate { card.setCard(nil) }
        }
        redraw()
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    private func apply(_ model: TableModel, _ reveal: Reveal) {
        markDrawn()
        pendingReveal = nil
        self.model = model
        revealed = valid(reveal, in: model)
        revealedEpoch = reveal.epoch
        shownRevealed = revealed
        settle()
        redraw()
        settleCelebration()
    }

    /// Holds a shell reveal until the timeline catches up; a fallback applies it if no
    /// `.reconcile` intent comes (a table detached mid-action, say).
    private func deferReveal(_ reveal: Reveal) {
        pendingReveal = reveal
        deferGeneration += 1
        let generation = deferGeneration
        Task { [weak self] in
            try? await Task.sleep(for: Pace.duration(Self.deferLimit))
            guard let self, self.deferGeneration == generation, let reveal = self.pendingReveal,
                  !self.animating, let room = self.store.room else { return }
            self.apply(TableModel(room: room), reveal)
        }
    }

    /// Queues one store intent: game events animate (Task 17), then `.reconcile` snaps. Intents
    /// play one at a time in the order they were queued; queuing is synchronous, so the
    /// session's replay of intents buffered before the table attached lands ahead of its live
    /// feed.
    func enqueue(_ intent: TableIntent) {
        _ = chain(intent)
    }

    /// `enqueue`, then waits until that intent has played.
    func play(_ intent: TableIntent) async {
        await chain(intent).value
    }

    private func chain(_ intent: TableIntent) -> Task<Void, Never> {
        let previous = playChain
        let next = Task { @MainActor [weak self] in
            await previous?.value
            await self?.playNow(intent)
        }
        playChain = next
        return next
    }

    private func playNow(_ intent: TableIntent) async {
        switch intent {
        case .reconcile:
            // A snapshot is the truth: a provisional card is either gone from the hand or back.
            clearProvisional()
            lastAct = nil
            reconcileFromStore()
            #if DEBUG
            timelineLog("reconcile seq \(store.lastSeq) hand \(hand.cards.count) transients \(transients.count)")
            #endif
        case .rejected:
            reconcileFromStore()
            rejected()
        case .game(let event, let seq):
            seenSeq = max(seenSeq, seq)
            guard seq > drawnSeq else {
                #if DEBUG
                timelineLog("skip seq \(seq) (drawn \(drawnSeq)) \(event)")
                #endif
                return  // the table already shows it
            }
            guard model?.game != nil, layout != nil else { return reconcileFromStore() }
            // The store has moved past the shown hand's turn (this event or a later one):
            // privacy doesn't wait for the snapshot or for the shell.
            if hideIfStale() { hideHand() }
            if let model, let said = TableAnnouncement.announcement(for: event, model: model) { announce(said) }
            animating = true
            #if DEBUG
            let started = ContinuousClock.now
            #endif
            await animate(event)
            animating = false
            #if DEBUG
            timelineLog("seq \(seq) \(ContinuousClock.now - started) \(event)")
            #endif
        case .versusIntro:
            // The first deal sends no events: the lobby → playing snapshot plays it.
            if model?.game == nil || layout == nil { reconcileFromStore() }
            guard model?.game != nil, layout != nil else { return }
            animating = true
            #if DEBUG
            let started = ContinuousClock.now
            #endif
            await playVersusIntro()
            animating = false
            #if DEBUG
            timelineLog("versusIntro + deal \(ContinuousClock.now - started)")
            #endif
        case .presence:
            reconcileFromStore()
        case .lobbyNope:
            break
        }
    }

    /// Before a snap: landed flyers go and anything an animation hid comes back.
    private func settle() {
        for node in transients { node.removeFromParent() }
        transients.removeAll()
        hand.isHidden = false
        laidZone.isHidden = false
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
        node.isPrivate = true  // still my hand's card until the server takes it
        layer(.drag).addChild(node)
        provisionalNode = node
        provisionalCard = card
        redraw()
    }

    /// The in-flight action was refused: the provisional card flies back to its place in the
    /// hand and nopes there.
    func rollbackProvisional() {
        guard let card = provisionalCard else { return }
        let flyer = provisionalNode
        provisionalNode = nil
        provisionalCard = nil
        redraw()
        guard let flyer, let home = hand.node(for: card), let parent = flyer.parent else {
            flyer?.removeFromParent()
            return nope(card: card)
        }
        let target = parent.convert(home.position, from: hand)
        home.alpha = 0
        #if DEBUG
        timelineLog("rollback card \(card) from \(flyer.position) to \(target)")
        #endif
        let back = Effects.fly(from: flyer.position, to: target, duration: 0.2, lift: 24, rotation: home.zRotation, scale: 1)
        let director = director
        Task { [weak self] in
            await director.run(back, on: flyer)
            flyer.removeFromParent()
            home.alpha = 1
            self?.nope(card: card)
        }
    }

    private func clearProvisional() {
        provisionalNode?.removeFromParent()
        provisionalNode = nil
        provisionalCard = nil
    }

    /// The table is about to show the store's room as of now: whole through `settledSeq`.
    private func markDrawn() {
        seenSeq = max(seenSeq, store.settledSeq)
        drawnSeq = store.settledSeq
    }

    /// Redraws from the store's room, keeping the last reveal only while the store is still in
    /// the turn epoch it was granted in (on a multi-seat phone).
    private func reconcileFromStore() {
        guard let room = store.room else { return }
        markDrawn()
        let next = TableModel(room: room)
        if let reveal = pendingReveal { return apply(next, reveal) }
        settle()
        model = next
        revealed = valid(Reveal(seat: revealed, epoch: revealedEpoch), in: next)
        shownRevealed = revealed
        redraw()
        settleCelebration()
    }

    /// Lays every node out for the current model, size and insets.
    private func redraw() {
        defer {
            accessibilityVersion += 1
            director.wake()
            director.noteChange()
            publishCoach()
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
        let barSeats = model.barSeats(bottom: bottom)
        let layout = TableLayout(
            size: size, safeTop: safeInsets.top, safeBottom: safeInsets.bottom, opponents: max(barSeats.count, 1))
        self.layout = layout
        for l in [Layer.rug, .piles, .laidZone, .tower] { layer(l).isHidden = false }
        opponents.isHidden = false

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
        // A phone holding no seat shows every seat in the bar.
        let turnedOn = opponents.update(model: model, seats: barSeats, layout: layout)
        for seat in turnedOn { pulseTurn(seat) }

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
        if let pick = trayYarn, !faceUp || !trayState.canMoveYarn(pick.card, inTray: pick.tray) {
            trayYarn = nil  // its tray changed or the hand went away: drop the pick
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
            trays.show(trayState, hidden: hidden, targets: glows.trays, lifted: trayYarn?.card)
            if !glows.layDown { trays.layDownButton.isHidden = true }
        } else {
            trays.isHidden = true
            trays.update(requirements: [], layout: layout)
            trays.layDownButton.isHidden = true
        }
        sortButton.isHidden = !faceUp || hand.cards.count < 2
        sortButton.position = layout.sortButton

        menuButton.isHidden = false
        // Top-right: in the status bar's right ear when the safe top is tall enough (notch /
        // island phones), else tucked into the bar's corner.
        let menuY = safeInsets.top >= 44
            ? layout.opponentsBar.maxY + Self.menuSize / 2 - 6
            : layout.opponentsBar.maxY - Self.menuSize / 2
        menuButton.position = CGPoint(x: size.width - Self.menuSize / 2 - 10, y: menuY)
    }

    /// The finite ring pulse + paw pop for the seat whose turn just came. Runs through the
    /// director so the view pauses again afterwards.
    func pulseTurn(_ seat: Seat) {
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

    /// No game (or no size yet): nothing of a table shows. Piles, the laid zone, the tower,
    /// the opponents bar, the trays and the hand all go, not just the hand.
    private func clearTable() {
        layout = nil
        bottomSeat = nil
        selection = nil
        trayYarn = nil
        clearProvisional()
        sortButton.isHidden = true
        for l in [Layer.rug, .piles, .laidZone, .tower] { layer(l).isHidden = true }
        opponents.clear()
        opponents.isHidden = true
        trays.isHidden = true
        trays.layDownButton.isHidden = true
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

    private func publishCoach() {
        onCoach(coachSnapshot())
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

    /// The cat tower's tap area (opens the scoreboard).
    var towerFrame: CGRect {
        guard let layout else { return .zero }
        return layout.towerFrame.insetBy(dx: -4, dy: 0)
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
        // Faces are spoken only for the hand shown face up right now.
        let facesShown = bottomSeat != nil && bottomSeat == shownRevealed

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
        if !trays.isHidden, facesShown {
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
            let face = facesShown ? node.card : nil
            let selected = face != nil && face == liftedCard
            items.append(Item(
                id: "table.hand.\(i)", label: CardNode.label(face),
                value: selected ? String(localized: "selected", comment: "VoiceOver: the picked-up hand card") : nil,
                frame: frame, traits: selected ? [.button, .selected] : .button,
                actions: face.map(handCardActions) ?? []))
        }
        if !sortButton.isHidden {
            items.append(Item(
                id: "table.sort", label: String(localized: "Sort hand", comment: "VoiceOver: sort the hand by number or coat"),
                frame: sortFrame))
        }
        items.append(Item(
            id: "table.menu", label: String(localized: "Table menu", comment: "VoiceOver: the paw menu button"),
            frame: menuFrame))
        items.append(Item(
            id: "table.tower", label: String(localized: "Scoreboard", comment: "VoiceOver: the cat tower; opens the scores"),
            frame: towerFrame))
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
        // step|inFlight|hand size|laid|turn|animating|round|game status|store seq|stage seq|pass
        // (UI tests only). The last three tell a stuck table from a shell that hasn't synced yet.
        let director = director
        let store = store
        return [
            TableAccessibility.Item(
                id: "table.frames", label: "frames", frame: CGRect(x: 0, y: 0, width: 24, height: 24),
                traits: .staticText, live: { String(director.framesRendered) }),
            TableAccessibility.Item(
                id: "table.debug", label: "debug", frame: CGRect(x: 24, y: 0, width: 24, height: 24),
                traits: .staticText, live: { [weak self] in
                    guard let self, let game = store.room?.game else { return "-" }
                    let seat = self.bottomSeat ?? -1
                    let laid = (game.laid[safe: seat] ?? nil) != nil
                    let busy = self.animating || !director.isIdle
                    let probe = self.stageProbe
                    return "\(game.step.rawValue)|\(store.actionInFlight ? 1 : 0)|\(game.hands[seat]?.count ?? -1)|\(laid ? 1 : 0)|\(game.turn)|\(busy ? 1 : 0)|\(game.round)|\(game.status.rawValue)|\(store.lastSeq)|\(probe.seq)|\(probe.passCode)"
                }),
        ]
        #else
        return []
        #endif
    }
}

#if DEBUG
/// The shell's last sync, for the DEBUG `table.debug` probe: the store seq it synced at and the
/// pass-and-play state it decided.
struct StageProbe {
    var seq = -1
    var pass: CurtainState = .none

    /// `none`, `curtain<seat>` or `revealed<seat>` (no spaces or pipes).
    var passCode: String {
        switch pass {
        case .none: "none"
        case .curtain(let seat): "curtain\(seat)"
        case .revealed(let seat): "revealed\(seat)"
        }
    }
}
#endif
