import Observation
import PounceKit
import SpriteKit
import SwiftUI

/// The tile game's table (tile game spec §5). Top to bottom: the opponents bar, the rug where
/// the sets flow in rows with the toy box in its corner, the action strip, and the stash.
///
/// The turn is a draft (`TilesDraft`): every drag and tap changes a local copy of the rug and
/// the stash, and only the turn button sends anything. `redraw` is idempotent: it lays every
/// piece out from the draft (or, off turn, from the store's room), with or without animation.
/// The app lays the rug out, never the player: sets flow like words in a paragraph (`RugFlow`).
///
/// Privacy: stash pieces exist as nodes only for the one seat this phone may show: its only
/// seat, or on a shared phone the seat pass-and-play has revealed (`RoomStore.pass`, read at
/// every redraw and every intent, so a reveal never outlives its turn). The rug is public.
///
/// While a TV shows the table (`tv`), the switch's band is at the top, and on Cards off turn the
/// stash is all there is (TilesController.swift).
///
/// A TV's table (`isScreen`: its store joined as a screen) is this scene in the TV's arrangement
/// (`TilesLayout(tv:insets:seats:)`): every seat across the top, the board filling the room, the
/// toy box and the turn banner along the bottom. The board shows the acting player's draft as they
/// make it on their phone (`RoomStore.aims`), the pieces they are adding marked. It never has a
/// stash, a strip or input, whatever the room says.
@MainActor
final class TilesScene: SKScene {
    /// zPosition bands. Everything inside a layer stays below the next band.
    enum Layer: CGFloat, CaseIterable {
        case background = 0, rug = 10, sets = 20, pool = 30, opponents = 50, strip = 60, rack = 70
        case dim = 78, loupe = 80, drag = 90, fx = 100
    }

    /// One set as the rug shows it: the draft's id for it (its index off turn) and its pieces.
    struct ShownSet: Equatable {
        var id: Int
        var tiles: [TileID]
    }

    let store: RoomStore
    let director = AnimationDirector(view: nil)
    /// This is a TV's table: its store joined the room as a screen. Fixed for the scene's life.
    let isScreen: Bool
    /// A TV's "<Name>'s turn" (and "Reconnecting") along the bottom.
    let banner = TVBanner()
    /// The store's aims and connection are being watched (a TV).
    private var watching = false
    private var warmedBanners: [TVArt.Piece] = []
    /// The seat the banner names (the drawn table's turn, or one that just started).
    private var bannerTurn: Seat?
    /// A TV: the acting player's draft as last seen, for their seat and turn. Their phone takes it
    /// back as it commits (that clear comes before `played`), so the board keeps it for a moment
    /// (`draftHold`) rather than the pieces leaving and flying back in. A clear that isn't followed
    /// by the play in that time was a cancel (on the wire the two are the same message): the draft
    /// goes and the board shows the table as it really is.
    private var keptAim: (seat: Seat, turns: Int, sets: [[TileID]])?
    /// The kept draft's clear came (its hold is running), and the scene time it was first seen at.
    private var aimCleared = false
    private var aimClearedAt: TimeInterval?
    /// How long a draft stays on the board after its player's phone takes it back, waiting for the
    /// play that commits it (seconds of scene time).
    static let draftHold: TimeInterval = 1.5
    /// The draft the board last drew (a TV): a store change that leaves it as it is draws nothing.
    private var drawnAim: [[TileID]]?
    /// Rack orders, half-built drafts and the last rug seen, per table on this device.
    var memory: TilesDeviceStore?

    // What the shell hears about.
    var onMenu: () -> Void = {}
    var onSwipeHome: () -> Void = {}
    /// The game is over and its last move has played (or the table opened finished).
    var onGameOver: ([Seat]) -> Void = { _ in }
    /// The seat whose stash is face up changed (nil: none).
    var onShownSeat: (Seat?) -> Void = { _ in }
    /// A tap on the table while this phone can't act: the shell hides a peeked stash.
    var onTableTap: () -> Void = {}
    /// One of this phone's seats drew on a shared phone: the shell shows the piece for a beat
    /// before the stash is passed on.
    var onDrew: (Seat, TileID) -> Void = { _, _ in }
    /// The top of the stash's band changed (scene points from the bottom edge): what the
    /// pass-and-play curtain covers.
    var onBand: (CGFloat) -> Void = { _ in }
    /// What VoiceOver should say.
    var onAnnounce: (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }
    /// Where UI tips can point (`Tips.swift`), in the view's points from its top-left corner:
    /// `tiles.draw` or `tiles.play` (the turn button), `tiles.sort`, `tiles.meter`, `tiles.set`.
    var onTipSpots: ([String: CGRect]) -> Void = { _ in }
    /// A control a tip teaches was used (`tiles.turn`, `tiles.sort`, `tiles.loupe`).
    var onTipUsed: (String) -> Void = { _ in }
    private var lastTipSpots: [String: CGRect] = [:]
    /// The stash alone is drawn (Cards, off turn) or not: the shell shows the status line then.
    var onStashOnly: (Bool) -> Void = { _ in }
    var publishedStashOnly: Bool?

    /// How a table a TV shows is drawn here (`TilesStage` decides); nil: no TV, today's table.
    var tv: TVFrame? {
        didSet {
            guard tv != oldValue else { return }
            redraw()
            publishAim()
        }
    }
    /// What the TV was last sent of this phone's draft (`publishAim`), and for which seat.
    var aimed: (seat: Seat, table: [[TileID]])?
    /// Whether the last redraw drew the stash alone, so a change between the two slides the stash.
    var drawnStashOnly: Bool?
    /// The stash is sliding between the stash-alone layout and the table's: its pieces' size
    /// changes over the same time as their place.
    var morphing = false
    /// When the stash's slide between the two layouts ends (media time). Redraws until then (the
    /// shell refreshes right after the snapshot that started it) let it finish instead of snapping.
    var slideEnds: CFTimeInterval = 0
    /// The table around the stash (rug, sets, toy box, top bar, strip): hidden, not torn down,
    /// while the stash is alone (TilesController.swift).
    let tableGroup = SKNode()
    /// The room's floor laid over the table, faded to bring the table in or take it away as one
    /// layer (`setTable(up:animated:)`): one opaque sprite, so nothing is drawn offscreen.
    let tableVeil = SKSpriteNode(texture: TableArt.image(ArtName.roomBg))
    /// The paw menu and the sort toggles: drawn with the stash alone too, so outside `tableGroup`
    /// and over the veil.
    let controlsLayer = SKNode()
    /// Whether the table was last asked to show (`setTable(up:animated:)`).
    var tableUpTarget: Bool?

    // Drawn state.
    var model: TilesTableModel?
    /// The seat whose stash is drawn, face up.
    private(set) var shownSeat: Seat? {
        didSet {
            guard shownSeat != oldValue else { return }
            onShownSeat(shownSeat)
            publishAim()
        }
    }
    /// The turn being composed; nil off turn.
    var draft: TilesDraft? {
        didSet { if draft != oldValue { publishAim() } }
    }
    var orders: [Seat: RackOrder] = [:]
    /// Pieces picked up by a tap (tap path): lifted in the stash or the loupe until a target is tapped.
    var selection: [TileID] = []
    /// The set open in the loupe (a draft set id).
    var loupe: Int?
    /// Easy mode (tile game spec §5.10) and its "tricks" (the loupe, splitting and joining).
    var easy = false
    var tricks = false
    /// A turn was sent and its snapshot hasn't come back.
    var sending = false {
        didSet { if sending != oldValue { publishAim() } }
    }
    /// The hint the "show me" paw lit.
    var hint: TilesHints.Hint?
    /// What changed since this phone's last turn, and the rings it is showing for it.
    var recap = TilesRecap()
    var rings: [TileID: UIColor] = [:]
    var ringSerial = 0
    /// The rug another seat's play is animating to, until its snapshot lands.
    var pendingTable: [[TileID]]?
    /// The rug's scroll (0 at the top), its zoom (a piece width asked for by a pinch; nil: fit)
    /// and the stash's sideways scroll.
    var scroll: CGFloat = 0
    var zoom: CGFloat?
    var rackScroll: CGFloat = 0
    private(set) var layout: TilesLayout?
    private(set) var flow: RugFlow?
    private(set) var shown: [ShownSet] = []
    /// The stash as drawn, left to right.
    private(set) var rackShown: [TileID] = []
    /// Interaction state (TilesInput.swift).
    var input = TilesInputState()
    /// The store seq the drawn table reflects, and the one this scene has played up to.
    var drawnSeq = -1
    var playChain: Task<Void, Never>?
    private var reportedOver = false
    /// Whether the "new row" slot's outline was last asked for lit (a piece aimed at it).
    var newSlotAimed = false
    /// The strip size `warmTextures` last drew for, and its drawing.
    var warmedFor: CGSize?
    var warmup: Task<Void, Never>?
    /// The last `fitRug` answer and what it was for.
    var fitCache: (key: RugFitKey, flow: RugFlow)?
    var accessibilityVersion = 0
    var accessibilityCache: (version: Int, elements: [UIAccessibilityElement])?
    #if DEBUG
    var dragPerf = DragPerf()
    var autoplay: Autoplay?
    /// Counts for the UI tests' probe (`tiles.debug`).
    var probe = (redraws: 0, sent: "-", refused: "-", perf: "-")
    #endif

    var safeInsets: UIEdgeInsets = .zero {
        didSet { if safeInsets != oldValue { redraw() } }
    }

    // Nodes.
    private var layers: [Layer: SKNode] = [:]
    private let background = SKSpriteNode(texture: TableArt.image(ArtName.roomBg))
    private let rugSprite = SKSpriteNode(texture: TableArt.image(ArtName.Tiles.rug))
    private let rugCrop = SKCropNode()
    private let rugMask = SKSpriteNode(color: .white, size: .zero)
    /// Holds the sets and their pieces; moved by the scroll. Its children use the flow's
    /// coordinates with y turned over.
    let rugContent = SKNode()
    /// The stash; dimmed as one layer while a turn is on its way.
    let rackLayer = FadeGroup()
    let loupeLayer = SKNode()
    private let dim = SKSpriteNode(color: UIColor(Palette.ink), size: .zero)
    var pieces: [TileID: TilePieceNode] = [:]
    var setNodes: [Int: TileSetNode] = [:]
    let opponents = TilesOpponentsNode()
    let menuButton = SKSpriteNode(texture: TableArt.image(ArtName.iconPawMenu))
    private let poolSprite = SKSpriteNode(texture: TableArt.image(ArtName.Tiles.toyBox))
    private let poolCount = SKSpriteNode()
    let recapButton = SKSpriteNode()
    private let newSlot = SKSpriteNode()
    private let newSlotPlus = SKSpriteNode()
    let undoButton = SKSpriteNode()
    let resetButton = SKSpriteNode()
    let sortNumberButton = SKSpriteNode()
    let sortToyButton = SKSpriteNode()
    let tidyButton = SKSpriteNode()
    let turnPill = SKSpriteNode()
    /// The turn button with its icon and label, dimmed as one layer.
    private let turnPillGroup = FadeGroup()
    private let turnIcon = SKSpriteNode()
    private let turnLabel = SKSpriteNode()
    let holdFill = SKSpriteNode(color: UIColor.white.withAlphaComponent(0.4), size: .zero)
    let meterNode = SKNode()
    private let meterBar = SKSpriteNode()
    private let meterIcon = SKSpriteNode()
    private let meterLabel = SKSpriteNode()
    private var underlines: [SKSpriteNode] = []
    private let loupePanel = SKSpriteNode()
    let loupeHandle = SKSpriteNode()
    let loupeClose = SKSpriteNode()
    var loupeGaps: [SKSpriteNode] = []
    /// Where the loupe drew each piece and each gap (scene space), for hit testing.
    var loupeSlots: [(tile: TileID, frame: CGRect)] = []
    var loupeGapFrames: [(index: Int, frame: CGRect)] = []
    var loupeFrame = CGRect.zero
    var transients: [SKNode] = []
    /// A dashed outline is breathing somewhere on the rug.
    private var breathing = false
    /// How long a piece takes to slide to its place (longer while another seat's play flies in).
    var flight: TimeInterval = 0.2

    private(set) var look = Look.standard

    init(store: RoomStore, memory: TilesDeviceStore? = nil) {
        self.store = store
        self.memory = memory
        isScreen = store.isScreen
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = UIColor(Palette.night)
        TableArt.preload()
        // Everything but the stash and what floats over it is the table (`tableGroup`).
        tableGroup.zPosition = 1
        addChild(tableGroup)
        // Over every table layer (the strip's meter reaches about 67), under the stash (70).
        tableVeil.zPosition = Layer.rack.rawValue - 2
        tableVeil.isHidden = true
        addChild(tableVeil)
        controlsLayer.zPosition = Layer.rack.rawValue - 1
        addChild(controlsLayer)
        for layer in Layer.allCases {
            let node = SKNode()
            node.zPosition = layer.rawValue
            layers[layer] = node
            if [.rug, .sets, .pool, .opponents, .strip].contains(layer) { tableGroup.addChild(node) } else { addChild(node) }
        }
        layer(.background).addChild(background)
        layer(.rug).addChild(rugSprite)
        // Only the calm middle stretches: the braided border keeps its width on any screen.
        rugSprite.centerRect = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6)
        rugCrop.maskNode = rugMask
        layer(.sets).addChild(rugCrop)
        rugCrop.addChild(rugContent)
        newSlot.zPosition = 1
        newSlotPlus.zPosition = 2
        rugContent.addChild(newSlot)
        newSlot.addChild(newSlotPlus)
        layer(.pool).addChild(poolSprite)
        poolCount.zPosition = 2
        layer(.pool).addChild(poolCount)
        recapButton.zPosition = 3
        layer(.pool).addChild(recapButton)
        layer(.opponents).addChild(opponents)
        layer(.opponents).addChild(banner)
        banner.zPosition = 30
        controlsLayer.addChild(menuButton)
        for node in [undoButton, resetButton, tidyButton] {
            layer(.strip).addChild(node)
        }
        for node in [sortNumberButton, sortToyButton] { controlsLayer.addChild(node) }
        turnPillGroup.addChild(turnPill)
        layer(.strip).addChild(turnPillGroup)
        holdFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        holdFill.zPosition = 1
        holdFill.isHidden = true
        turnPill.addChild(holdFill)
        turnIcon.zPosition = 2
        turnLabel.zPosition = 2
        turnPill.addChild(turnIcon)
        turnPill.addChild(turnLabel)
        meterNode.zPosition = 5
        layer(.strip).addChild(meterNode)
        meterBar.zPosition = 0
        meterIcon.zPosition = 1
        meterLabel.zPosition = 1
        [meterBar, meterIcon, meterLabel].forEach(meterNode.addChild)
        layer(.rack).addChild(rackLayer)
        dim.anchorPoint = .zero
        dim.alpha = 0
        dim.isHidden = true
        layer(.dim).addChild(dim)
        layer(.loupe).addChild(loupeLayer)
        loupePanel.centerRect = TilePieceFactory.plateCenter
        loupePanel.zPosition = 0
        loupeHandle.zPosition = 3
        loupeClose.zPosition = 3
        [loupePanel, loupeHandle, loupeClose].forEach(loupeLayer.addChild)
        loupeLayer.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    func layer(_ layer: Layer) -> SKNode { layers[layer]! }

    /// The table's look. The tile game keeps its own rug whatever the look says: the sets need
    /// a calm, square-cornered field, and Cat Tower's rugs are round and loud. (The card back
    /// has no part in this game either.)
    func setLook(_ next: Look) {
        look = next
    }

    // MARK: lifecycle

    override func didMove(to view: SKView) {
        #if DEBUG
        if autoplay == nil { autoplay = Autoplay.start(self) }
        #endif
        director.view = view
        safeInsets = view.safeAreaInsets
        if isScreen {
            // The game's sounds are the TV's; its pieces are drawn ahead, off the main thread.
            Sound.shared.preload()
            Task { await TilePieceFactory.shared.prewarm() }
            TVArt.shared.scale = max(view.traitCollection.displayScale, 1)
            watchStore()
        }
        redraw()
        speed = CGFloat(Pace.factor)
    }

    override func willMove(from view: SKView) {
        saveDraft()
        clearAim()
        director.cancelAll()
        warmup?.cancel()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        redraw()
    }

    override func update(_ currentTime: TimeInterval) {
        let work = FrameWork("tiles.update"); defer { work.end() }
        stepInput(currentTime)
        if aimCleared { holdDraft(currentTime) }
        // A set that isn't one yet breathes, so the view stays awake while one is on the rug.
        if breathing { director.wake() }
        #if DEBUG
        if input.isDragging { dragPerf.frame(currentTime, drawn: input.dragNodes.first?.position) }
        #endif
        director.frame(currentTime)
    }

    // MARK: reconcile

    /// The seat whose stash may show now: this phone's only seat, or the one pass-and-play has
    /// revealed. Nil outside play.
    func currentReveal(_ model: TilesTableModel) -> Seat? {
        // A TV shows no stash, ever.
        guard model.isLive, !isScreen else { return nil }
        let mine = model.myActiveSeats
        if mine.count == 1, model.mySeats.count == 1 { return mine[0] }
        if case .revealed(let seat) = store.pass.state, mine.contains(seat) { return seat }
        return nil
    }

    /// Draws the store's room exactly, without animation: the snapshot is the truth.
    func reconcileFromStore() {
        let work = FrameWork("tiles.reconcile"); defer { work.end() }
        guard let room = store.room, let model = TilesTableModel(room: room) else {
            self.model = nil
            draft = nil
            redraw()
            return
        }
        self.model = model
        bannerTurn = model.room.liveTurn
        if let kept = keptAim, !model.isLive || kept.seat != model.view.turn || kept.turns != model.view.turns { dropKeptAim() }
        drawnSeq = store.settledSeq
        pendingTable = nil
        for node in transients { node.removeFromParent() }
        transients.removeAll()
        setLook(room.look ?? .standard)
        if !store.actionInFlight { sending = false }
        applyReveal(model)
        if model.view.status == .gameOver, !reportedOver {
            reportedOver = true
            onGameOver(model.view.winners)
        }
    }

    /// Settles who is shown and what draft is on the table for `model`, then redraws.
    private func applyReveal(_ model: TilesTableModel) {
        let seat = currentReveal(model)
        if seat != shownSeat {
            hideStash()
            selection = []
            closeLoupe(animated: false)
            rackScroll = 0
        }
        shownSeat = seat
        if let seat, let rack = model.rack(seat) {
            var order = orders[seat] ?? memory?.memory(code: store.code).orders[seat] ?? RackOrder()
            order.sync(rack)
            // Easy mode: the stash sorts itself, by toy unless the player picked the other.
            if easy, order.sort == nil { order.apply(.toy) }
            orders[seat] = order
        }
        if let seat, model.canCompose(seat), !sending {
            let saved = draft == nil ? memory?.memory(code: store.code).draft(seat: seat, turns: model.view.turns) : nil
            var next = model.draft(for: seat, keeping: draft, saved: saved)
            // Sets stay in the order they were laid (the tidy toggle is gone).
            next?.tidy = false
            draft = next
            if let next, let open = loupe, next.set(open) == nil { closeLoupe(animated: false) }
        } else if !sending {
            draft = nil
            closeLoupe(animated: false)
            selection = []
            hint = nil
        }
        // Coming back to a table others played on: mark what is new (a cold start has no
        // events, so it compares against the last rug this phone drew).
        if recap.isEmpty, rings.isEmpty, draft != nil, let last = memory?.memory(code: store.code).lastTable,
           last != model.view.table {
            recap = .since(last, now: model.view.table)
        }
        memory?.update(code: store.code) { $0.lastTable = model.view.table }
        redraw()
        if draft != nil, !recap.isEmpty { showRecap() }
    }

    /// The shell says pass-and-play changed (a hold finished, a peek was put away): the stash
    /// follows `RoomStore.pass` at once.
    func refresh() {
        guard let model else { return reconcileFromStore() }
        if currentReveal(model) != shownSeat || (draft == nil && model.canCompose(shownSeat ?? -1)) {
            applyReveal(model)
        } else {
            redraw()
        }
    }

    /// Privacy never waits for a snapshot: the moment the store says the shown seat's turn is
    /// gone on a shared phone, its stash goes face down.
    @discardableResult
    func hideIfStale() -> Bool {
        guard let model, let seat = shownSeat, model.isMultiSeat else { return false }
        if case .revealed(seat) = store.pass.state { return false }
        hideStash()
        shownSeat = nil
        draft = nil
        selection = []
        closeLoupe(animated: false)
        redraw()
        return true
    }

    /// Takes every stash piece off the table (the rug's stay).
    private func hideStash() {
        for (tile, node) in pieces where node.isPrivate {
            node.removeFromParent()
            pieces[tile] = nil
        }
        rackShown = []
    }

    /// Keeps a half-built turn and the stash's order for when the app comes back.
    func saveDraft() {
        guard let memory, let model, let seat = shownSeat else { return }
        let draft = self.draft
        let order = orders[seat]
        memory.update(code: store.code) { m in
            if let order { m.orders[seat] = order }
            if let draft, !draft.isUntouched, !self.sending {
                m.draft = .init(seat: seat, turns: model.view.turns, draft: draft)
            } else if m.draft?.seat == seat || m.draft?.turns != model.view.turns {
                m.draft = nil
            }
        }
    }

    // MARK: drawing

    /// The sets the rug shows now: the draft's, another seat's play in flight, or the room's.
    func currentSets() -> [ShownSet] {
        if let draft { return draft.shownSets.map { ShownSet(id: $0.id, tiles: $0.tiles) } }
        let table = pendingTable ?? aimTable ?? model?.view.table ?? []
        return table.enumerated().map { ShownSet(id: $0.offset, tiles: $0.element) }
    }

    /// A TV: the acting player's draft of the table, while they make it on their phone
    /// (`RoomStore.aims`); nil for none, and always nil off a TV.
    /// A clear from their phone doesn't take it off the board while the turn lasts (`keptAim`).
    var aimTable: [[TileID]]? {
        guard isScreen, let model, model.isLive else { return nil }
        if case .table(let sets)? = store.aims[model.view.turn] { return sets }
        guard let kept = keptAim, kept.seat == model.view.turn, kept.turns == model.view.turns else { return nil }
        return kept.sets
    }

    /// Keeps the acting player's draft as their phone last sent it (`keptAim`), and starts its hold
    /// when the phone takes it back.
    private func keepAim() {
        guard isScreen, let model, model.isLive else { return }
        if case .table(let sets)? = store.aims[model.view.turn] {
            keptAim = (model.view.turn, model.view.turns, sets)
            aimCleared = false
            aimClearedAt = nil
            return
        }
        guard !aimCleared, let kept = keptAim, kept.seat == model.view.turn, kept.turns == model.view.turns else { return }
        aimCleared = true
        aimClearedAt = nil
        // The view stays awake through the hold, so its frames can end it (`holdDraft`).
        let director = director
        let node = layer(.fx)
        Task { await director.run(.wait(forDuration: Self.draftHold + 0.2), on: node, decorative: true) }
    }

    /// Each frame of a draft's hold: once `draftHold` of scene time has passed since its clear with no
    /// play landing, it was a cancel, and the board goes back to the table as it is.
    private func holdDraft(_ now: TimeInterval) {
        guard let since = aimClearedAt else {
            aimClearedAt = now
            return
        }
        guard (now - since) * Double(speed) >= Self.draftHold else { return }
        dropKeptAim()
        redraw(animated: true)
    }

    /// Forgets the kept draft (the play landed, the turn moved on, or its hold ran out).
    func dropKeptAim() {
        keptAim = nil
        aimCleared = false
        aimClearedAt = nil
    }

    /// The pieces the acting player's draft adds to the table (a TV marks them).
    func aimAdded() -> Set<TileID> {
        guard pendingTable == nil, let model, let sets = aimTable else { return [] }
        return Set(sets.joined()).subtracting(model.view.table.joined())
    }

    /// The seat the bottom band is laid out for: the one shown, else the one behind the curtain.
    func bandSeat(_ model: TilesTableModel) -> Seat? {
        if let shownSeat { return shownSeat }
        switch store.pass.state {
        case .curtain(let seat), .revealed(let seat): return seat
        case .none: return model.isMultiSeat ? model.myActiveSeats.first : nil
        }
    }

    /// Lays everything out for the drawn state. `animated` slides pieces to their places;
    /// otherwise they snap.
    func redraw(animated: Bool = false) {
        let work = FrameWork("tiles.redraw"); defer { work.end() }
        guard size.width > 0, size.height > 0 else { return }
        director.wake()
        accessibilityVersion += 1
        #if DEBUG
        probe.redraws += 1
        #endif
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        // The room art is portrait; a TV turns it on its side, as Cat Tower's wide table does.
        background.zRotation = isScreen ? .pi / 2 : 0
        let art = isScreen ? CGSize(width: 844, height: 390) : CGSize(width: 390, height: 844)
        let bgScale = max(size.width / art.width, size.height / art.height)
        background.size = CGSize(width: 390 * bgScale, height: 844 * bgScale)
        tableVeil.position = background.position
        tableVeil.size = background.size
        guard let model else {
            clearTable()
            return
        }
        if !animated { director.cancelActions(under: rugContent) }

        let seat = shownSeat
        if isScreen {
            keepAim()
            drawnAim = aimTable
        }
        let sets = currentSets()
        // A TV marks what the acting player's draft adds (a paw and a yellow ring, lifted a little).
        let added = isScreen ? aimAdded() : []
        let placed = draft?.placedTiles ?? added
        let rackTiles: [TileID]
        if let seat, let order = orders[seat] {
            let rack = draft?.rack ?? model.rack(seat) ?? []
            rackTiles = order.shown(rack).filter { !(input.isDragging && input.dragTiles.contains($0)) }
        } else {
            rackTiles = []
        }
        rackShown = rackTiles
        let band = isScreen ? nil : bandSeat(model)
        let controls = !isScreen && model.isLive && !model.myActiveSeats.isEmpty
        let layout = isScreen
            ? TilesLayout(tv: size, insets: TVInsets(safeInsets), seats: model.barSeats(bottom: nil).count)
            : TilesLayout(
                size: size, safeTop: safeInsets.top, safeBottom: safeInsets.bottom,
                opponents: model.barSeats(bottom: seat).count,
                rackCount: max(band.map(model.rackCount) ?? 0, rackTiles.count + input.dragTiles.count),
                meter: draft?.openingMeter != nil, controls: controls, controller: controllerMode(model))
        director.fxScale = isScreen ? 2 * layout.tvUnit : 1
        self.layout = layout
        // Just the stash (Cards, off turn): the curtain and the shared phone's cats take all of
        // the room under the status line.
        let stashOnly = layout.arrangement == .controller
        let morph = drawnStashOnly.map { $0 != stashOnly } ?? false
        drawnStashOnly = stashOnly
        shown = stashOnly ? [] : sets
        if publishedStashOnly != stashOnly {
            publishedStashOnly = stashOnly
            onStashOnly(stashOnly)
        }
        let savedFlight = flight
        if morph {
            flight = max(flight, 0.32)
            slideEnds = CACurrentMediaTime() + flight / max(Double(speed), 0.01)
        }
        // Scene time left of a slide under way (the whole of it on the redraw that starts it).
        let slideLeft = max(slideEnds - CACurrentMediaTime(), 0) * Double(speed)
        let sliding = slideLeft > 0
        morphing = morph
        defer {
            flight = savedFlight
            morphing = false
        }
        onBand(controls ? (stashOnly ? layout.statusLine.minY : (layout.meter == .zero ? layout.strip.maxY : layout.meter.maxY) + 2) : 0)

        // With just the stash the table stays drawn, under the veil, as it will show on this phone's turn
        // (`tableLayout`), so the turn's first frame only shows it: no nodes, flows or textures
        // made then.
        let table = stashOnly ? tableLayout(model, seat: seat, stash: layout) : layout
        setTable(up: !stashOnly, animated: morph)
        var live: Set<TileID> = []
        /// The first set on the rug that opens in the loupe (the loupe tip points at it).
        let firstOpenSet = drawRug(
            sets, model: model, layout: table, placed: placed, added: added, live: &live, animated: animated && !stashOnly)
        if input.isDragging { live.formUnion(input.dragTiles) }

        // The stash.
        rackLayer.position = CGPoint(x: -rackScroll, y: 0)
        rackLayer.alpha = sending ? 0.6 : 1  // fade-ok: a FadeGroup
        if let seat, model.rack(seat) != nil {
            let gapSlot = input.isDragging && input.target == .rack ? input.rackSlot : nil
            let slotCount = rackTiles.count + (gapSlot == nil ? 0 : input.dragTiles.count)
            let slots = layout.rackSlots(count: slotCount).centers
            let ready = orders[seat]?.readySets(in: rackTiles) ?? []
            var slot = 0
            for (i, tile) in rackTiles.enumerated() {
                if let gapSlot, i == gapSlot { slot += input.dragTiles.count }
                guard slot < slots.count else { break }
                live.insert(tile)
                var target = slots[slot]
                // Ready sets sit a hair closer together.
                if let range = ready.first(where: { $0.contains(i) }) {
                    let mid = CGFloat(range.lowerBound + range.upperBound - 1) / 2
                    target.x -= (CGFloat(i) - mid) * 1.5
                }
                let lifted = selection.contains(tile)
                if lifted { target.y += layout.rackPiece.height * 0.16 }
                let node = piece(tile, in: rackLayer, size: layout.rackPiece, face: .large, at: target)
                node.isPrivate = true
                let was = node.pieceSize
                node.show(size: layout.rackPiece, face: .large, standing: nil)
                // Between the stash alone and the table, each piece grows or shrinks on its way
                // (it starts at the size it was drawn).
                if morph, was.width > 0, was != layout.rackPiece { node.setScale(node.xScale * was.width / layout.rackPiece.width) }
                node.zPosition = lifted ? 5 : 1 + CGFloat(i) * 0.01
                node.setPlaced(false)
                node.setRing(lifted ? .white : hintRing(tile))
                node.alpha = 1  // the stash dims as a whole (`rackLayer`)
                // Already sliding to this very place: let it get there.
                let onItsWay = sliding && !morph && !animated && node.home == target && !lifted
                if !onItsWay { settle(node, at: target, scale: lifted ? 1.08 : 1, animated: animated || morph) }
                slot += 1
            }
            drawUnderlines(ready, tiles: rackTiles, layout: layout, after: sliding ? slideLeft : nil)
        } else {
            drawUnderlines([], tiles: [], layout: layout, after: nil)
        }
        rackScroll = min(max(rackScroll, 0), layout.rackScrollLimit(count: rackTiles.count))

        for (tile, node) in pieces where !live.contains(tile) && !input.dragTiles.contains(tile) {
            node.removeFromParent()
            pieces[tile] = nil
        }

        drawLoupe(layout: layout, animated: animated)
        drawPool(model, layout: table)
        drawStrip(model, layout: table, toggles: layout, controls: controls && seat != nil, animated: sliding)
        let turned = opponents.update(model: model, seats: model.barSeats(bottom: seat), layout: table)
        if !stashOnly { for seat in turned { pulse(seat) } }
        menuButton.size = CGSize(width: layout.menuSide, height: layout.menuSide)
        menuButton.position = layout.menuButton
        // `clearTable` hides it while there's no table yet; the table is here now.
        menuButton.isHidden = false
        publishProbe()
        if controls { warmTextures(layout: table) }
        if isScreen {
            showBanner(pop: false)
        } else {
            publishTipSpots(firstSet: firstOpenSet.flatMap { layout.rug.contains(CGPoint(x: $0.midX, y: $0.midY)) ? $0 : nil })
        }
    }

    /// Lays the rug's sets out (and the "new row" slot) and returns the first set that opens in the
    /// loupe; every piece it draws goes in `live`.
    private func drawRug(
        _ sets: [ShownSet], model: TilesTableModel, layout: TilesLayout, placed: Set<TileID>, added: Set<TileID>,
        live: inout Set<TileID>, animated: Bool
    ) -> CGRect? {
        rugSprite.isHidden = false
        rugSprite.setScale(1)
        let rugBase = CGSize(width: 132 * layout.rugBorderScale, height: 176 * layout.rugBorderScale)
        rugSprite.size = rugBase
        rugSprite.position = CGPoint(x: layout.rugArt.midX, y: layout.rugArt.midY)
        rugSprite.xScale = layout.rugArt.width / rugBase.width
        rugSprite.yScale = layout.rugArt.height / rugBase.height
        rugMask.size = CGSize(width: layout.rugArt.width - 8, height: layout.rugArt.height - 8)
        rugMask.position = CGPoint(x: layout.rugArt.midX, y: layout.rugArt.midY)
        let flow = fitRug(lengths: sets.map(\.tiles.count), layout: layout, zoom: zoom)
        self.flow = flow
        scroll = min(max(scroll, 0), max(flow.contentHeight - layout.rug.height, 0))
        rugContent.position = CGPoint(x: layout.rug.minX, y: layout.rug.maxY + scroll)

        var liveSets: Set<Int> = []
        var firstOpenSet: CGRect?
        let small: TilePieceFactory.Size = flow.pieceSize.width >= 42 ? .large : .small
        let reduce = Effects.reduceMotion
        for (index, set) in sets.enumerated() {
            let placement = flow.sets[index]
            let standings = set.tiles.contains(where: Tile.isYarn) ? TilesRules.standings(set.tiles) : nil
            let inLoupe = loupe == set.id
            liveSets.insert(set.id)
            let node = setNodes[set.id] ?? {
                let n = TileSetNode()
                n.zPosition = 5
                setNodes[set.id] = n
                rugContent.addChild(n)
                return n
            }()
            var center = CGPoint(x: placement.frame.midX, y: -placement.frame.midY)
            if firstOpenSet == nil, draft.map({ !$0.isLocked(set.id) }) == true {
                let a = rugContent.convert(CGPoint(x: placement.frame.minX, y: -placement.frame.maxY), to: self)
                let b = rugContent.convert(CGPoint(x: placement.frame.maxX, y: -placement.frame.minY), to: self)
                firstOpenSet = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            }
            // The set a dragged piece is over swells toward stash size, so the target is large.
            var swell: CGFloat = 1
            if input.isDragging, case .set(let aimed) = input.target, aimed == set.id {
                swell = min(layout.rackPiece.width / flow.pieceSize.width, 1.5, (layout.rug.width - 4) / placement.frame.width)
                let half = placement.frame.width * swell / 2
                center.x = min(max(center.x, half), max(layout.rug.width - half, half))
            }
            place(node, at: center, animated: animated && node.look != nil)
            node.show(look(for: set, model: model), size: placement.frame.size, reduceMotion: reduce)
            node.alpha = inLoupe ? 0.5 : 1  // fade-ok: TileSetNode is a FadeGroup
            node.setScale(swell)
            node.zPosition = swell > 1 ? 40 : 5
            guard !inLoupe else {
                live.formUnion(set.tiles)
                continue
            }
            for (i, tile) in set.tiles.enumerated() where !(input.dragTiles.contains(tile) && input.isDragging) {
                live.insert(tile)
                var target = CGPoint(x: placement.pieces[i].x, y: -placement.pieces[i].y)
                // A TV lifts what the acting player's draft adds, a little.
                if added.contains(tile) { target.y += flow.pieceSize.height * 0.06 }
                if swell > 1 {
                    target = CGPoint(
                        x: center.x + (target.x - placement.frame.midX) * swell,
                        y: center.y + (target.y + placement.frame.midY) * swell)
                }
                let node = piece(tile, in: rugContent, size: flow.pieceSize, face: small, at: target)
                node.isPrivate = false
                node.show(size: flow.pieceSize, face: swell > 1.2 ? .large : small, standing: standings?[i])
                node.zPosition = (swell > 1 ? 45 : 10) + CGFloat(i) * 0.01
                node.setPlaced(placed.contains(tile))
                node.setRing(
                    rings[tile] ?? (selection.contains(tile) ? .white : added.contains(tile) ? UIColor(Palette.yellow) : hintRing(tile)))
                node.alpha = 1
                settle(node, at: target, scale: selection.contains(tile) ? 1.12 : swell, animated: animated)
            }
        }
        for (id, node) in setNodes where !liveSets.contains(id) {
            node.removeFromParent()
            setNodes[id] = nil
        }
        breathing = setNodes.values.contains { $0.breathes }

        // The "new row" slot: where a piece starts a set of its own.
        let composing = draft != nil && !sending
        newSlot.isHidden = !composing
        if composing {
            let frame = flow.newSlot
            let aimed = input.target == .newSet
            let color = aimed ? UIColor(Palette.lime) : UIColor.white.withAlphaComponent(0.9)
            let fill = UIColor(Palette.ink).withAlphaComponent(0.2)
            let factory = TilePieceFactory.shared
            if newSlot.texture == nil {
                // The table opening: drawn now, so the slot never shows empty.
                newSlot.texture = factory.dashed(frame.size, color: color, fill: fill)
            } else if let ready = factory.dashedIfReady(frame.size, color: color, fill: fill, then: { [weak self] texture in
                // Still the slot that asked for it (no newer size or colour since).
                guard let self, self.newSlot.size == frame.size, self.newSlotAimed == aimed else { return }
                self.newSlot.texture = texture
            }) {
                newSlot.texture = ready
            }
            // A new size keeps the last outline, stretched, until its own is drawn (a frame or two).
            newSlotAimed = aimed
            newSlot.size = frame.size
            newSlot.position = CGPoint(x: frame.midX, y: -frame.midY)
            let plus = TilePieceFactory.shared.label("+", size: min(frame.height * 0.6, 24), outline: 2)
            newSlotPlus.texture = plus
            newSlotPlus.size = plus.size()
        } else if newSlot.texture == nil {
            // Off turn: the slot's outline is drawn off the main thread now, for the turn's first frame.
            let size = flow.newSlot.size
            newSlot.texture = TilePieceFactory.shared.dashedIfReady(
                size, color: UIColor.white.withAlphaComponent(0.9), fill: UIColor(Palette.ink).withAlphaComponent(0.2)
            ) { [weak self] texture in
                if self?.newSlot.texture == nil { self?.newSlot.texture = texture }
            }
        }
        return firstOpenSet
    }

    /// Tells the shell where the tips' controls are now (only when that changed).
    private func publishTipSpots(firstSet: CGRect?) {
        guard view != nil, let layout else { return }
        var spots: [String: CGRect] = [:]
        func put(_ id: String, _ r: CGRect) {
            let a = convertPoint(toView: CGPoint(x: r.minX, y: r.maxY))
            let b = convertPoint(toView: CGPoint(x: r.maxX, y: r.minY))
            spots[id] = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)).integral
        }
        if tableUp, !turnPill.isHidden {
            switch turnButton {
            case .draw: put("tiles.draw", layout.turn)
            case .play: put("tiles.play", layout.turn)
            default: break
            }
        }
        if !sortToyButton.isHidden { put("tiles.sort", layout.sortNumber.union(layout.sortToy)) }
        if tableUp, !undoButton.isHidden, layout.undo != .zero { put("tiles.undo", layout.undo.union(layout.reset)) }
        if tableUp, easy, !tidyButton.isHidden, layout.tidy != .zero { put("tiles.hint", layout.tidy) }
        if tableUp, !meterNode.isHidden, layout.meter != .zero { put("tiles.meter", layout.meter) }
        if loupe == nil, selection.isEmpty, tricksAllowed, let firstSet { put("tiles.set", firstSet) }
        guard spots != lastTipSpots else { return }
        lastTipSpots = spots
        onTipSpots(spots)
    }

    var maxScroll: CGFloat {
        guard let flow, let layout, tableUp else { return 0 }
        return max(flow.contentHeight - layout.rug.height, 0)
    }

    private func clearTable() {
        if !lastTipSpots.isEmpty {
            lastTipSpots = [:]
            onTipSpots([:])
        }
        for node in pieces.values { node.removeFromParent() }
        pieces.removeAll()
        for node in setNodes.values { node.removeFromParent() }
        setNodes.removeAll()
        opponents.clear()
        rugSprite.isHidden = true
        newSlot.isHidden = true
        for node in [undoButton, resetButton, sortNumberButton, sortToyButton, tidyButton, turnPill, poolSprite, poolCount, recapButton, menuButton] {
            node.isHidden = true
        }
        meterNode.isHidden = true
        _ = banner.show(nil, banner: .zero, room: .zero, unit: 1, pop: false, reduceMotion: true)
    }

    // MARK: a TV's table

    /// A TV watches what its store hears between snapshots: the acting player's draft and whether
    /// the TV still has the table. A new draft slides the board's pieces to it (and only a new
    /// one: anything else the store changes redraws nothing); the connection redraws the banner.
    private func watchStore() {
        guard isScreen, !watching else { return }
        watching = true
        withObservationTracking {
            _ = store.aims
            _ = store.connection
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.watching = false
                guard self.view != nil else { return }
                self.keepAim()
                if self.aimTable != self.drawnAim { self.redraw(animated: true) }
                self.showBanner(pop: false)
                self.watchStore()
            }
        }
    }

    /// A TV's banner pops for the turn that just started.
    func showBanner(turn started: Seat) {
        bannerTurn = started
        showBanner(pop: true)
    }

    /// A TV's banner: whose turn it is, or "Reconnecting" while the TV has lost the table; gone
    /// after the game. `pop`: a turn just started.
    private func showBanner(pop: Bool) {
        guard isScreen, let model, let layout, layout.arrangement == .tv else {
            _ = banner.show(nil, banner: .zero, room: .zero, unit: 1, pop: false, reduceMotion: true)
            return
        }
        let names = SeatInfo.names(model.room)
        let words = TVSeatWords(.zero, unit: layout.tvUnit)
        let pieces = names.indices.map {
            TVBanner.piece(name: names[$0], seat: $0, banner: layout.banner, room: layout.bannerRoom, unit: layout.tvUnit)
        } + [TVBanner.lost(banner: layout.banner, unit: layout.tvUnit)] + model.view.scores.map(words.piece)
        if pieces != warmedBanners {
            warmedBanners = pieces
            TVArt.shared.warm(pieces)
        }
        let next: TVBanner.Shown?
        if store.connection == .reconnecting {
            next = .reconnecting
        } else if let turn = bannerTurn {
            next = .turn(seat: turn, name: names[safe: turn] ?? "", cat: SeatInfo.catIndex(model.room.seats[safe: turn]))
        } else {
            next = nil
        }
        let motion = banner.show(
            next, banner: layout.banner, room: layout.bannerRoom, unit: layout.tvUnit, pop: pop, reduceMotion: Effects.reduceMotion)
        director.wake()
        if let (action, node) = motion {
            let director = director
            Task { await director.run(action, on: node, decorative: true) }
        }
    }

    /// The node for `tile`, in `parent`. A piece that changes parent keeps its place on screen
    /// (it slides from there); a new one appears at `spawn`.
    func piece(_ tile: TileID, in parent: SKNode, size: CGSize, face: TilePieceFactory.Size, at spawn: CGPoint) -> TilePieceNode {
        if let node = pieces[tile] {
            if node.parent !== parent {
                let position = node.parent.map { parent.convert(node.position, from: $0) } ?? spawn
                node.removeFromParent()
                parent.addChild(node)
                node.position = position
            }
            return node
        }
        let node = TilePieceNode(tile: tile, size: size, face: face)
        node.position = spawn
        pieces[tile] = node
        parent.addChild(node)
        return node
    }

    /// Puts a node where the layout wants it, sliding there when `animated`.
    func place(_ node: SKNode, at target: CGPoint, animated: Bool) {
        guard animated, hypot(node.position.x - target.x, node.position.y - target.y) > 0.5 else {
            node.position = target
            return
        }
        director.cancelActions(on: node)
        let action = Effects.reduceMotion
            ? SKAction.move(to: target, duration: 0.01)
            : SKAction.move(to: target, duration: morphing ? flight : 0.2).eased(.easeOut)
        director.play(action, on: node)
    }

    private func settle(_ node: TilePieceNode, at target: CGPoint, scale: CGFloat, animated: Bool) {
        node.home = target
        node.zRotation = 0
        node.alpha = node.alpha == 0 ? 1 : node.alpha
        if !animated {
            director.cancelActions(on: node)
            node.position = target
            node.setScale(scale)
            return
        }
        let moved = hypot(node.position.x - target.x, node.position.y - target.y) > 0.5
        let scaled = abs(node.xScale - scale) > 0.01
        guard moved || scaled else { return }
        director.cancelActions(on: node)
        let reduce = Effects.reduceMotion
        var actions: [SKAction] = []
        if moved { actions.append(SKAction.move(to: target, duration: reduce ? 0.01 : flight).eased(.easeOut)) }
        if scaled { actions.append(SKAction.scale(to: scale, duration: reduce ? 0.01 : morphing ? flight : 0.14).eased(.easeOut)) }
        // Nothing waits for a settle: started now, without a task per piece.
        director.play(SKAction.group(actions), on: node)
    }

    /// The rug's flow for these set lengths, from the last redraw's when nothing it depends on
    /// changed: `RugFlow.fit` lays the whole rug out at every size it tries, and a drag redraws
    /// every time its aim moves.
    func fitRug(lengths: [Int], layout: TilesLayout, zoom: CGFloat?) -> RugFlow {
        let key = RugFitKey(
            lengths: lengths, width: layout.rug.width, height: layout.rug.height,
            maxPiece: layout.rugPieceMax, minPiece: layout.rugPieceMin, zoom: zoom)
        if let fitCache, fitCache.key == key { return fitCache.flow }
        let flow = RugFlow.fit(
            lengths: lengths, width: key.width, height: key.height, maxPiece: key.maxPiece, minPiece: key.minPiece, zoom: zoom)
        fitCache = (key, flow)
        return flow
    }

    private func hintRing(_ tile: TileID) -> UIColor? {
        switch hint {
        case .newSet(let tiles): tiles.contains(tile) ? UIColor(Color(hex: 0xFFD21F)) : nil
        case .fits(let hinted, _): hinted == tile ? UIColor(Color(hex: 0xFFD21F)) : nil
        case nil: nil
        }
    }

    /// How a set's bed is drawn now.
    private func look(for set: ShownSet, model: TilesTableModel) -> TileSetNode.Look {
        if case .set(let id) = input.target, id == set.id { return input.targetRefused ? .refused : .target }
        if case .fits(_, let id) = hint, id == set.id { return .target }
        guard let draft else { return .plain }
        if input.wiggling.contains(set.id) { return .refused }
        switch draft.state(of: set.id) {
        case .unchanged: return draft.isLocked(set.id) ? .locked : .plain
        case .changed: return .changed
        case .broken(let problem): return .broken(problem)
        }
    }

    /// The bars under the stash's ready sets. `after`: the stash is sliding to its place; they show
    /// once it is there.
    private func drawUnderlines(_ ready: [Range<Int>], tiles: [TileID], layout: TilesLayout, after: TimeInterval?) {
        for node in underlines { node.removeFromParent() }
        underlines.removeAll()
        guard !ready.isEmpty else { return }
        let slots = layout.rackSlots(count: tiles.count).centers
        for range in ready {
            // One bar per row the set sits in.
            var start = range.lowerBound
            while start < range.upperBound {
                var end = start
                while end + 1 < range.upperBound, abs(slots[end + 1].y - slots[start].y) < 1 { end += 1 }
                let a = slots[start], b = slots[end]
                let bar = SKSpriteNode(color: UIColor(Palette.lime), size: CGSize(width: b.x - a.x + layout.rackPiece.width * 0.8, height: 3.5))
                bar.position = CGPoint(x: (a.x + b.x) / 2, y: a.y - layout.rackPiece.height / 2 - 1.5)
                bar.zPosition = 0.5
                rackLayer.addChild(bar)
                underlines.append(bar)
                if let after {
                    // Bars apart from one another, over nothing: each fades on its own.
                    bar.alpha = 0  // fade-ok: one bar alone
                    director.play(.sequence([.wait(forDuration: after), .fadeIn(withDuration: 0.15)]), on: bar)
                }
                start = end + 1
            }
        }
    }

    private func drawPool(_ model: TilesTableModel, layout: TilesLayout) {
        guard layout.pool != .zero else {
            // Just the stash: the toy box is on the TV.
            [poolSprite, poolCount, recapButton].forEach { $0.isHidden = true }
            return
        }
        // Under the paw menu, off the rug.
        poolSprite.isHidden = false
        poolSprite.size = layout.pool.size
        poolSprite.position = CGPoint(x: layout.pool.midX, y: layout.pool.midY)
        poolSprite.alpha = model.view.poolCount == 0 ? 0.55 : 1  // fade-ok: the toy box alone
        // A TV's count is read from the couch: 36 points.
        let onTV = layout.arrangement == .tv
        let count = TilePieceFactory.shared.count(model.view.poolCount, size: onTV ? (36 * layout.tvUnit).rounded() : layout.roomy ? 18 : 14)
        poolCount.isHidden = false
        poolCount.texture = count
        poolCount.size = count.size()
        if onTV {
            // In the toy box's bottom-right corner, inside the TV-safe area.
            poolCount.position = CGPoint(
                x: layout.pool.maxX - count.size().width / 2 + 6 * layout.tvUnit, y: layout.pool.minY + count.size().height / 2)
        } else {
            poolCount.position = CGPoint(x: layout.pool.minX + count.size().width / 2 - 6, y: layout.pool.minY + count.size().height / 2 - 4)
        }
        // The "what changed" paw, at the strip's right end, while there is something to show again.
        // Easy mode's hint has that slot, and the rings on the rug show what changed there.
        let side: CGFloat = layout.roomy ? 50 : 40
        recapButton.isHidden = recap.isEmpty || easy || layout.recap == .zero || turnPill.isHidden
        recapButton.texture = TilePieceFactory.shared.button(.changed, side: side)
        recapButton.size = CGSize(width: side, height: side + 3)
        recapButton.position = CGPoint(x: layout.recap.midX, y: layout.recap.midY)
    }

    /// The turn button's word.
    static func turnText(_ button: TilesDraft.TurnButton?, sending: Bool) -> String {
        switch button {
        case .draw: String(localized: "Draw", comment: "Tile game turn button: take a piece from the toy box")
        case .pass: String(localized: "Pass", comment: "Tile game turn button: the toy box is empty and nothing fits")
        case .play, .blocked: String(localized: "Play", comment: "Tile game turn button: send the turn")
        case nil:
            sending
                ? String(localized: "Sent", comment: "Tile game turn button while the turn is on its way")
                : String(localized: "Wait", comment: "Tile game turn button when it is not this player's turn")
        }
    }

    /// The turn button as it stands: one of four things, always (tile game spec §5.5).
    var turnButton: TilesDraft.TurnButton? {
        sending ? nil : draft?.turnButton
    }

    /// The action strip, and its sort toggles at `toggles`' place for them: the strip's, or with
    /// just the stash (Cards, off turn) over the stash, while the rest of the strip waits hidden
    /// with the table. `animated`: the toggles slide to their new place (the stash is sliding too).
    private func drawStrip(_ model: TilesTableModel, layout: TilesLayout, toggles: TilesLayout, controls: Bool, animated: Bool) {
        let factory = TilePieceFactory.shared
        let nodes = [undoButton, resetButton, sortNumberButton, sortToyButton, tidyButton, turnPill]
        guard controls, let seat = shownSeat else {
            nodes.forEach { $0.isHidden = true }
            meterNode.isHidden = true
            return
        }
        nodes.forEach { $0.isHidden = false }
        let drawn: CGFloat = layout.roomy ? 50 : 40
        func button(_ node: SKSpriteNode, _ frame: CGRect, _ texture: SKTexture) {
            node.texture = texture
            node.setScale(1)
            node.size = CGSize(width: drawn, height: drawn + 3)
            place(node, at: CGPoint(x: frame.midX, y: frame.midY), animated: animated)
        }
        let composing = draft != nil && !sending
        button(undoButton, layout.undo, factory.button(.undo, side: drawn, dim: !(composing && draft?.canUndo == true)))
        button(resetButton, layout.reset, factory.button(.reset, side: drawn, dim: !(composing && draft?.isUntouched == false)))
        let sort = orders[seat]?.sort
        // Over an iPad's stash alone the toggles grow with its pieces (`TilesLayout`).
        let sortDrawn = toggles.arrangement == .controller && toggles.roomy
            ? (toggles.sortNumber.width * 50 / 56).rounded() : drawn
        func toggle(_ node: SKSpriteNode, _ frame: CGRect, _ texture: SKTexture) {
            button(node, frame, texture)
            node.size = CGSize(width: sortDrawn, height: sortDrawn + 3)
        }
        // That size is drawn off the main thread the first time (`buttonIfReady`); until it is in,
        // the table's size stands in, stretched, for a frame or two.
        func toggleTexture(_ node: SKSpriteNode, _ symbol: TilePieceFactory.Symbol?, suit: TileSuit?, on: Bool) -> SKTexture {
            let table = factory.button(symbol, suit: suit, side: drawn, on: on)
            guard sortDrawn != drawn else { return table }
            let side = sortDrawn
            return factory.buttonIfReady(symbol, suit: suit, side: side, on: on) { [weak node] texture in
                // Still standing in at that size (no other state or size since).
                guard let node, node.size.width == side, node.texture == table else { return }
                node.texture = texture
            } ?? table
        }
        toggle(sortNumberButton, toggles.sortNumber, toggleTexture(sortNumberButton, .sortNumber, suit: nil, on: sort == .number))
        toggle(sortToyButton, toggles.sortToy, toggleTexture(sortToyButton, nil, suit: .fish, on: sort == .toy))
        if easy {
            button(tidyButton, layout.tidy, factory.button(.hint, side: drawn, on: hint != nil, dim: !composing))
        } else {
            tidyButton.isHidden = true
        }

        // The turn button.
        let pill: TilePieceFactory.Pill
        let icon: SKTexture?
        switch turnButton {
        case .draw:
            pill = .draw
            icon = TableArt.image(ArtName.Tiles.toyBox)
        case .pass:
            pill = .pass
            icon = TableArt.image(ArtName.iconZzz)
        case .play:
            pill = .play
            icon = TableArt.image(ArtName.iconPawMenu)
        case .blocked:
            pill = .blocked
            icon = TableArt.image(ArtName.iconPawMenu)
        case nil:
            pill = .blocked
            icon = sending ? TableArt.image(ArtName.Habit.iconHourglass) : TableArt.image(ArtName.iconZzz)
        }
        let text = Self.turnText(turnButton, sending: sending)
        let size = layout.turn.size
        turnPill.texture = factory.pill(pill, size: size, pressed: input.pressed == .turn)
        turnPill.size = CGSize(width: size.width, height: size.height + 4)
        turnPill.position = CGPoint(x: layout.turn.midX, y: layout.turn.midY)
        turnPillGroup.alpha = turnButton == nil ? 0.75 : 1  // fade-ok: a FadeGroup
        let label = factory.label(text, size: (size.height * 0.46).rounded(), outline: 2.5)
        turnLabel.texture = label
        turnLabel.size = label.size()
        let iconSide = size.height * 0.62
        turnIcon.texture = icon
        turnIcon.size = CGSize(width: iconSide, height: iconSide)
        let total = iconSide + 6 + label.size().width
        turnIcon.position = CGPoint(x: -total / 2 + iconSide / 2, y: 2)
        turnLabel.position = CGPoint(x: total / 2 - label.size().width / 2, y: 2)
        turnIcon.alpha = pill == .blocked ? 0.6 : 1  // fade-ok: the icon alone on its pill
        holdFill.size = CGSize(width: size.width - 10, height: size.height - 10)
        holdFill.position = CGPoint(x: -size.width / 2 + 5, y: 2)
        if input.hold == nil { holdFill.isHidden = true }
        // The Play paw pulses once when the draft becomes a play.
        if pill == .play, input.lastPill != .play, !Effects.reduceMotion {
            let director = director
            let pop = SKAction.sequence([.scale(to: 1.1, duration: 0.12).eased(.easeOut), .scale(to: 1, duration: 0.16).eased(.easeInEaseOut)])
            turnPill.setScale(1)
            Task { await director.run(pop, on: turnPill, decorative: true) }
        }
        input.lastPill = pill

        // The opening meter.
        if let meter = draft?.openingMeter, layout.meter != .zero {
            meterNode.isHidden = false
            meterNode.position = CGPoint(x: layout.meter.midX, y: layout.meter.midY)
            let gold = meter.points >= meter.goal
            let barSize = layout.meter.size
            let bar = factory.meter(size: barSize, fraction: CGFloat(meter.points) / CGFloat(meter.goal), gold: gold)
            meterBar.texture = bar
            meterBar.size = barSize
            let side = barSize.height * (easy ? 1.7 : 1.35)
            meterIcon.texture = TableArt.image(gold ? ArtName.Tiles.toyBox : ArtName.Tiles.toyBoxClosed)
            meterIcon.size = CGSize(width: side, height: side)
            meterIcon.position = CGPoint(x: -barSize.width / 2 - side * 0.2, y: 1)
            let words = factory.label("\(meter.points)/\(meter.goal)", size: (barSize.height * 0.62).rounded(), outline: 2)
            meterLabel.texture = words
            meterLabel.size = words.size()
            meterLabel.position = CGPoint(x: 6, y: 0)
        } else {
            meterNode.isHidden = true
        }
    }

    // MARK: the loupe

    /// Opens a set at stash size over the dimmed rug (tile game spec §5.4).
    func openLoupe(_ id: Int) {
        guard let draft, draft.set(id) != nil, !draft.isLocked(id) else { return }
        loupe = id
        selection = []
        onTipUsed("tiles.loupe")
        Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
        Haptics.shared.tick()
        redraw(animated: true)
    }

    func closeLoupe(animated: Bool = true) {
        guard loupe != nil else { return }
        loupe = nil
        selection = selection.filter { rackShown.contains($0) }
        if animated { redraw(animated: true) }
    }

    private func drawLoupe(layout: TilesLayout, animated: Bool) {
        for node in loupeGaps { node.removeFromParent() }
        loupeGaps.removeAll()
        loupeSlots = []
        loupeGapFrames = []
        guard let id = loupe, let index = shown.firstIndex(where: { $0.id == id }), let flow else {
            loupeLayer.isHidden = true
            dim.isHidden = true
            dim.alpha = 0
            loupeFrame = .zero
            return
        }
        let placed = draft?.placedTiles ?? []
        let tiles = shown[index].tiles.filter { !(input.isDragging && input.dragTiles.contains($0)) }
        let all = shown[index].tiles
        // The rug and the top bar dim; the stash and the strip stay lit, since pieces go there too.
        dim.isHidden = false
        let floor = layout.strip.height > 0 ? (layout.meter == .zero ? layout.strip.maxY : layout.meter.maxY) : 0
        dim.position = CGPoint(x: 0, y: floor)
        dim.size = CGSize(width: size.width, height: size.height - floor)
        dim.alpha = 0.55  // fade-ok: the veil, one sprite over the rug
        loupeLayer.isHidden = false

        // Rows of up to seven at stash size, near where the set sits on the rug.
        let pieceSize = layout.rackPiece
        let gap: CGFloat = 10
        let perRow = max(min(Int((size.width - 56) / (pieceSize.width + gap)), 7), 3)
        let rows = max(Int((Double(max(all.count, 1)) / Double(perRow)).rounded(.up)), 1)
        let longest = min(all.count, perRow)
        let handle: CGFloat = 40
        let panelW = min(CGFloat(longest) * pieceSize.width + CGFloat(longest - 1) * gap + 28, size.width - 12)
        let panelH = CGFloat(rows) * pieceSize.height + CGFloat(rows - 1) * 8 + 24 + handle
        let home = flow.sets[index].frame
        let setCenter = rugContent.convert(CGPoint(x: home.midX, y: -home.midY), to: self)
        let x = min(max(setCenter.x, panelW / 2 + 6), size.width - panelW / 2 - 6)
        let lowest = (layout.strip.maxY > 0 ? layout.strip.maxY : layout.rug.minY) + panelH / 2 + 8
        let y = min(max(setCenter.y, lowest), layout.rug.maxY - panelH / 2)
        loupeFrame = CGRect(x: x - panelW / 2, y: y - panelH / 2, width: panelW, height: panelH)
        loupePanel.texture = TilePieceFactory.shared.panel()
        loupePanel.setScale(1)
        loupePanel.size = CGSize(width: 36, height: 36)
        loupePanel.position = CGPoint(x: x, y: y)
        loupePanel.xScale = panelW / 36
        loupePanel.yScale = panelH / 36
        // The handle (move the whole set) and the close button, along the top.
        let top = loupeFrame.maxY - handle / 2 - 6
        loupeHandle.texture = TilePieceFactory.shared.button(.handle, side: 36, on: Set(selection) == Set(all) && !all.isEmpty)
        loupeHandle.size = CGSize(width: 36, height: 39)
        loupeHandle.position = CGPoint(x: loupeFrame.minX + 28, y: top)
        loupeClose.texture = TilePieceFactory.shared.button(.close, side: 36)
        loupeClose.size = CGSize(width: 36, height: 39)
        loupeClose.position = CGPoint(x: loupeFrame.maxX - 28, y: top)

        let standings = all.contains(where: Tile.isYarn) ? TilesRules.standings(all) : nil
        let firstRowY = loupeFrame.maxY - handle - 10 - pieceSize.height / 2
        for (i, tile) in all.enumerated() {
            let row = i / perRow, column = i % perRow
            let inRow = min(all.count - row * perRow, perRow)
            let rowW = CGFloat(inRow) * pieceSize.width + CGFloat(inRow - 1) * gap
            let center = CGPoint(
                x: x - rowW / 2 + pieceSize.width / 2 + CGFloat(column) * (pieceSize.width + gap),
                y: firstRowY - CGFloat(row) * (pieceSize.height + 8))
            // A gap to tap between two pieces: the set breaks there.
            if column > 0, tricksAllowed {
                let mark = SKSpriteNode(color: UIColor.white.withAlphaComponent(0.85), size: CGSize(width: 3, height: pieceSize.height * 0.5))
                mark.position = CGPoint(x: center.x - pieceSize.width / 2 - gap / 2, y: center.y)
                mark.zPosition = 1
                loupeLayer.addChild(mark)
                loupeGaps.append(mark)
                loupeGapFrames.append((i, CGRect(x: mark.position.x - 11, y: center.y - pieceSize.height / 2, width: 22, height: pieceSize.height)))
            }
            guard tiles.contains(tile) else { continue }
            let lifted = selection.contains(tile)
            var target = center
            if lifted { target.y += pieceSize.height * 0.14 }
            let node = piece(tile, in: loupeLayer, size: pieceSize, face: .large, at: target)
            node.isPrivate = false
            node.show(size: pieceSize, face: .large, standing: standings?[i])
            node.zPosition = lifted ? 6 : 2 + CGFloat(i) * 0.01
            node.setPlaced(placed.contains(tile))
            node.setRing(lifted ? .white : nil)
            node.alpha = 1
            settle(node, at: target, scale: lifted ? 1.08 : 1, animated: animated)
            loupeSlots.append((tile, CGRect(x: center.x - pieceSize.width / 2 - gap / 2 + 4, y: center.y - pieceSize.height / 2, width: pieceSize.width + gap - 8, height: pieceSize.height)))
        }
    }

    /// Splitting and joining are part of the game, behind the "tricks" paw in easy mode.
    var tricksAllowed: Bool { !easy || tricks }

    // MARK: small motions

    /// The finite pop on a ring whose turn just came.
    private func pulse(_ seat: Seat) {
        guard let cat = opponents.node(for: seat), view != nil else { return }
        let director = director
        for (action, node) in cat.turnPulse(reduceMotion: Effects.reduceMotion) {
            Task { await director.run(action, on: node, decorative: true) }
        }
    }

    /// The "nope" wiggle: a few quick turns that end where they started.
    func nope(_ node: SKNode) {
        Sound.shared.play(ArtName.Sound.sfxNope, volume: 0.6)
        Haptics.shared.thump()
        guard !Effects.reduceMotion else { return }
        let wiggle = SKAction.sequence([
            .rotate(toAngle: 0.14, duration: 0.05), .rotate(toAngle: -0.12, duration: 0.08),
            .rotate(toAngle: 0.07, duration: 0.07), .rotate(toAngle: 0, duration: 0.06),
        ])
        let director = director
        Task { await director.run(wiggle, on: node, decorative: true) }
    }

    /// Shakes the opening meter: the explanation for a locked rug.
    func shakeMeter() {
        Sound.shared.play(ArtName.Sound.sfxNope, volume: 0.6)
        Haptics.shared.thump()
        guard !meterNode.isHidden, !Effects.reduceMotion, let layout else { return }
        let x = layout.meter.midX
        let shake = SKAction.sequence([
            .moveTo(x: x - 7, duration: 0.05), .moveTo(x: x + 6, duration: 0.07), .moveTo(x: x - 4, duration: 0.06),
            .moveTo(x: x + 2, duration: 0.05), .moveTo(x: x, duration: 0.04),
        ])
        let director = director
        Task { await director.run(shake, on: meterNode, decorative: true) }
    }

    /// Scrolls the rug so `set` shows, and wiggles it.
    func reveal(set id: Int) {
        guard let index = shown.firstIndex(where: { $0.id == id }), let flow, let layout else { return }
        let frame = flow.sets[index].frame
        if frame.minY < scroll || frame.maxY > scroll + layout.rug.height {
            scroll = min(max(frame.midY - layout.rug.height / 2, 0), maxScroll)
        }
        redraw(animated: true)
        if let node = setNodes[id] { nope(node) }
    }

    private func publishProbe() {}
}

/// What `RugFlow.fit` depends on (`TilesScene.fitRug`).
struct RugFitKey: Equatable {
    var lengths: [Int]
    var width: CGFloat
    var height: CGFloat
    var maxPiece: CGFloat
    var minPiece: CGFloat
    var zoom: CGFloat?
}
