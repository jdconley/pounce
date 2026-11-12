import PounceKit
import SwiftUI

/// What the tile game's scene tells its shell.
@MainActor @Observable
final class TilesStageEvents {
    var menuOpen = false
    /// The seat whose stash the scene is showing (nil: none).
    var shown: Seat?
    /// Set once the game is over and its last move has played.
    var winners: [Seat]?
    /// Scene points from the bottom edge to the top of the stash's band (the action strip, and
    /// the opening meter riding on it): what the pass-and-play curtain covers.
    var bandTop: CGFloat = 0
    /// A piece one of this phone's seats drew on a shared phone, shown once before it is passed on.
    var drew: Drew?
    var tableTaps = 0

    struct Drew: Equatable {
        var seat: Seat
        var tile: TileID
        var serial: Int
    }
}

/// The device's memory of tile game tables: stash orders, half-built turns, the last rug seen.
/// A demo or a UI test keeps its own, so nothing leaks between runs.
@MainActor
enum TilesMemory {
    static let store: TilesDeviceStore = {
        #if DEBUG
        let args = CommandLine.arguments
        if args.contains("-uitest-reset") || args.contains("-demo") {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tiles-\(ProcessInfo.processInfo.processIdentifier)")
            return TilesDeviceStore(directory: dir)
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return TilesDeviceStore(directory: support.appendingPathComponent("Pounce", isDirectory: true))
    }()
}

/// The tile game's table for one session (tile game spec §5): the SpriteKit scene, and over it
/// the pass-and-play curtain, the piece a shared phone's seat just drew, the pills and the game
/// over card. The rug is public, so the curtain only ever covers the stash and the action strip
/// (§5.9); the scene never builds a stash for a seat that isn't shown.
struct TilesStage: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    let session: RoomSession
    /// This phone's connection as the screen shows it.
    let connection: RoomStore.Connection

    @State private var scene: TilesScene?
    @State private var events = TilesStageEvents()
    @State private var forfeitPill: RoomStore.ForfeitNotice?
    /// The game over card's Play again, and whether the server said the game is switched off.
    @State private var playAgain = PlayAgain()
    @State private var againTick = 0
    @State private var gameOff = false

    private var table: TilesTableModel? { session.store.room.flatMap(TilesTableModel.init(room:)) }
    private var pass: PassAndPlay { session.store.pass }

    /// Easy mode (§5.10): on for a kitten unless they turned it off, off for everyone else
    /// unless they turned it on.
    private var easy: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("-tiles-easy") { return true }
        #endif
        return TilesMemory.store.memory(code: session.code).easy ?? (model.ageBand == .kitten)
    }

    private var tricks: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("-tiles-tricks") { return true }
        #endif
        return TilesMemory.store.memory(code: session.code).tricks ?? false
    }

    /// The seat the curtain is up for: waiting for its hold, or held while the scene hasn't
    /// shown that stash yet. Never on a one-seat phone.
    private var curtainSeat: Seat? {
        guard events.winners == nil, let table, table.isMultiSeat, table.isLive else { return nil }
        switch pass.state {
        case .none: return nil
        case .curtain(let seat): return seat
        case .revealed(let seat): return events.shown == seat ? nil : seat
        }
    }

    private var peeking: Bool {
        guard let table, table.isMultiSeat, !table.isMyTurn, table.isLive else { return false }
        if case .none = pass.state { return false }
        return true
    }

    /// This phone's seats along the bottom while another seat plays: tap one to peek.
    private var localCats: [(seat: Seat, person: Person)] {
        guard events.winners == nil, let table, table.myActiveSeats.count > 1, !table.isMyTurn, case .none = pass.state,
              table.isLive else { return [] }
        return table.myActiveSeats.compactMap { seat in table.room.seats[safe: seat]?.person.map { (seat, $0) } }
    }

    var body: some View {
        @Bindable var events = events
        ZStack {
            if let scene {
                TilesTableView(scene: scene)
                    .ignoresSafeArea()
            } else {
                RoomBackground()
            }
            // Everything that sits over the stash's band is anchored to the bottom edge.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    if !localCats.isEmpty {
                        TilesLocalCats(cats: localCats) { seat in
                            session.store.peek(seat)
                            scene?.refresh()
                        }
                        .transition(.opacity)
                    }
                    if let seat = curtainSeat, let person = table?.room.seats[safe: seat]?.person {
                        TilesCurtain(person: person, peeking: peeking, onBack: {
                            session.store.hidePass()
                            scene?.refresh()
                        }) {
                            session.store.completeHold()
                            scene?.refresh()
                        }
                        .id(pass.curtains)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                    }
                    if let drew = events.drew, let person = table?.room.seats[safe: drew.seat]?.person {
                        TilesDrewCard(person: person, tile: drew.tile) { events.drew = nil }
                            .id(drew.serial)
                            .transition(.opacity)
                    }
                }
                .frame(height: max(events.bandTop, 0))
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .ignoresSafeArea()
            .zIndex(TableLayer.curtain)

            if let pill = forfeitPill, let table, !table.mySeats.contains(pill.seat) || table.isMultiSeat {
                VStack {
                    ForfeitPill(name: SeatInfo.name(table.room, pill.seat), cat: SeatInfo.catIndex(table.room.seats[safe: pill.seat]))
                        .padding(.top, horizontalSizeClass == .regular ? 236 : 136)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(TableLayer.lookPill)
            }
            if connection != .good, events.winners == nil, !events.menuOpen {
                VStack {
                    ConnectionPill(connection: connection)
                        .padding(.top, horizontalSizeClass == .regular ? 196 : 104)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(TableLayer.connection)
            }
            if let winners = events.winners, let table {
                TilesOverView(table: table, winners: winners, again: againState, onPlayAgain: tapPlayAgain) { model.goHome() }
                    .transition(.opacity)
                    .zIndex(TableLayer.gameOver)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.15).paced, value: curtainSeat)
        .animation(.easeOut(duration: 0.2).paced, value: localCats.map(\.seat))
        .animation(.easeOut(duration: 0.3).paced, value: events.winners)
        .animation(.easeOut(duration: 0.2).paced, value: events.drew)
        .animation(.spring(duration: 0.35, bounce: 0.3).paced, value: connection)
        .onAppear(perform: attach)
        .onDisappear {
            scene?.saveDraft()
            session.detachTable()
        }
        .onChange(of: TilesStageInput(room: session.store.room, pass: pass), initial: true) {
            scene?.refresh()
        }
        .onChange(of: session.store.forfeitNotice) { _, notice in
            guard let notice else { return }
            Sound.shared.play(ArtName.Sound.sfxThud, volume: 0.7)
            withAnimation(.spring(duration: 0.45, bounce: 0.4).paced) { forfeitPill = notice }
            Task {
                try? await Task.sleep(for: Pace.duration(.seconds(3)))
                if forfeitPill == notice { withAnimation(.easeIn(duration: 0.3).paced) { forfeitPill = nil } }
            }
        }
        .onChange(of: session.store.rematch) { _, code in
            // The phone that asked goes to the new table; the others' pill now jumps there.
            if let code, let go = playAgain.arrived(code: code) { model.openRematch(code: go) }
        }
        .onChange(of: session.lobbyNope) {
            // A refused Play again. `game_off`: the server no longer deals this game, so no new
            // table can be dealt, and the card says so instead of offering it again.
            if session.store.lastError == .gameOff {
                gameOff = true
                UIAccessibility.post(notification: .announcement, argument: TilesOverView.offWords)
            }
            if playAgain.waiting { playAgain.refused() }
        }
        .onChange(of: events.tableTaps) {
            // Tapping away from a peeked stash hides it again.
            guard peeking, case .revealed = pass.state else { return }
            session.store.hidePass()
            scene?.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scene?.saveDraft() }
        }
        .sheet(isPresented: $events.menuOpen) {
            TilesMenuSheet(
                tableName: session.store.room?.title ?? TableName.fallback(code: session.code),
                easy: easy, tricks: tricks,
                // A kitten can't forfeit: giving up a game someone else is in is a grown-up's call.
                forfeit: model.ageBand == .kitten ? nil : table.flatMap { table in
                    table.forfeitSeat(shown: events.shown).map { ($0, table) }
                },
                onEasy: { on in
                    TilesMemory.store.update(code: session.code) { $0.easy = on }
                    applyModes()
                },
                onTricks: { on in
                    TilesMemory.store.update(code: session.code) { $0.tricks = on }
                    applyModes()
                },
                onHome: {
                    events.menuOpen = false
                    model.goHome()
                },
                onForfeit: { seat in
                    events.menuOpen = false
                    if !session.store.actTiles(seat: seat, .forfeit) { session.send(.actTiles(seat: seat, action: .forfeit)) }
                },
                onClose: { events.menuOpen = false })
                .environment(settings)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-tiles")
    }

    private var againState: TilesOverView.Again? {
        _ = againTick
        if gameOff { return .off }
        guard PlayAgain.available(session.store.room) else { return nil }
        if session.store.rematch != nil { return .go }
        return playAgain.isWaiting() ? .waiting : .ask
    }

    private func tapPlayAgain() {
        switch playAgain.tap(room: session.store.room, rematch: session.store.rematch) {
        case .send:
            session.send(.rematch)
            // No answer by then (the send never left, or the deal failed): the pill wakes up again.
            Task {
                try? await Task.sleep(for: .seconds(PlayAgain.wait + 0.2))
                againTick += 1
            }
        case .jump(let code): model.openRematch(code: code)
        case .none: break
        }
    }

    private func applyModes() {
        scene?.easy = easy
        scene?.tricks = tricks
        scene?.refresh()
        scene?.redraw()
    }

    private func attach() {
        let scene = self.scene ?? TilesScene(store: session.store, memory: TilesMemory.store)
        // The callbacks hold `events` weakly and never this view, whose state owns the scene.
        let events = events
        scene.easy = easy
        scene.tricks = tricks
        scene.onMenu = { [weak events] in events?.menuOpen = true }
        scene.onSwipeHome = { [weak model] in model?.goHome() }
        scene.onGameOver = { [weak events] winners in events?.winners = winners }
        scene.onShownSeat = { [weak events] seat in events?.shown = seat }
        scene.onTableTap = { [weak events] in events?.tableTaps += 1 }
        scene.onBand = { [weak events] top in if events?.bandTop != top { events?.bandTop = top } }
        scene.onDrew = { [weak events] seat, tile in
            events?.drew = .init(seat: seat, tile: tile, serial: (events?.drew?.serial ?? 0) + 1)
        }
        self.scene = scene
        session.attachTable { [weak scene] intent in scene?.enqueue(intent) }
        scene.reconcileFromStore()
        #if DEBUG
        TilesDemo.stage(scene)
        #endif
    }
}

private struct TilesStageInput: Equatable {
    var room: RoomView?
    var pass: PassAndPlay
}

/// The pass-and-play curtain over the stash (tile game spec §5.9): the rug stays in view above
/// it. The person's cat and name, and a paw to press and hold. Letting go early does nothing.
struct TilesCurtain: View {
    let person: Person
    var peeking = false
    var onBack: () -> Void = {}
    let onRevealed: () -> Void

    var body: some View {
        ZStack {
            Palette.night
                .overlay {
                    Image(ArtName.curtainStage)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                }
                .clipped()
                .overlay(alignment: .top) { Rectangle().fill(Palette.ink).frame(height: 4) }
            HStack(spacing: 14) {
                Image(ArtName.cat(person.cat, .idle))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    OutlinedText(person.name, size: 34, fill: Palette.orange, width: 4)
                        .accessibilityIdentifier("curtain.name")
                    OutlinedText(String(localized: "Hold to show your stash", comment: "Tile game curtain: what the paw does"), size: 16, lines: 2)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TilesHoldButton(
                    label: Text("Hold to show \(person.name)'s stash", comment: "VoiceOver: the tile game curtain's paw button"),
                    onDone: onRevealed)
                    .accessibilityIdentifier("curtain.hold")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .overlay(alignment: .topLeading) {
            if peeking {
                CornerHomeButton(label: "Back to the table", action: onBack)
                    .padding(.leading, 12)
                    .padding(.top, 10)
                    .accessibilityIdentifier("curtain.back")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-curtain")
        .onAppear { Sound.shared.play(ArtName.Sound.sfxWhoosh, volume: 0.7) }
    }
}

/// A round paw that must be held for a moment (the curtain, the drawn piece's "continue").
struct TilesHoldButton: View {
    var side: CGFloat = 84
    let label: Text
    let onDone: () -> Void

    static let holdDuration: Double = Pace.seconds(0.6)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var done = false

    var body: some View {
        let ring = side + 22
        ZStack {
            Circle().stroke(Palette.ink.opacity(0.6), lineWidth: 14).frame(width: ring, height: ring)
            Circle().stroke(Palette.teal.opacity(0.45), lineWidth: 9).frame(width: ring, height: ring)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(done ? Palette.lime : Palette.teal, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ring, height: ring)
            Circle()
                .fill(LinearGradient(
                    colors: [Palette.magenta.mix(with: .white, by: 0.12), Palette.magenta, Palette.magenta.mix(with: Palette.violet, by: 0.35)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 4))
                .overlay {
                    Image(ArtName.iconHold).resizable().scaledToFit().frame(width: side * 0.56, height: side * 0.56)
                }
                .frame(width: side, height: side)
                .offset(y: pressing ? 3 : 0)
        }
        .frame(width: ring + 14, height: ring + 14)
        .scaleEffect(pressing && !reduceMotion ? 0.95 : 1)
        .animation(.spring(duration: 0.15, bounce: 0.3).paced, value: pressing)
        .contentShape(Circle())
        .onLongPressGesture(
            minimumDuration: Self.holdDuration, maximumDistance: side / 2,
            perform: complete,
            onPressingChanged: { down in
                guard !done else { return }
                pressing = down
                if down {
                    Haptics.shared.tick()
                    withAnimation(.linear(duration: Self.holdDuration)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2).paced) { progress = 0 }
                }
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
    }

    private func complete() {
        guard !done else { return }
        done = true
        pressing = false
        progress = 1
        Haptics.shared.success()
        Sound.shared.play(ArtName.Sound.sfxSparkle)
        onDone()
    }
}

/// After a draw on a shared phone the turn has already moved on, so the stash is hidden: the new
/// piece shows here for a beat, for the person who drew it, with a hold to continue.
struct TilesDrewCard: View {
    let person: Person
    let tile: TileID
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Palette.night
                .overlay(alignment: .top) { Rectangle().fill(Palette.ink).frame(height: 4) }
            HStack(spacing: 16) {
                Image(uiImage: TilePieceFactory.shared.image(tile))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 86)
                    .accessibilityLabel(Text(TilesWords.piece(tile)))
                VStack(alignment: .leading, spacing: 2) {
                    OutlinedText(String(localized: "\(person.name) drew", comment: "Tile game: the piece a shared phone's player just drew"), size: 26, fill: Palette.orange, width: 4)
                    OutlinedText(String(localized: "Hold to continue", comment: "Tile game: dismiss the drawn piece"), size: 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TilesHoldButton(side: 72, label: Text("Hold to continue", comment: "VoiceOver: dismiss the drawn piece"), onDone: onDone)
                    .accessibilityIdentifier("tiles.drew.hold")
            }
            .padding(.horizontal, 20)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tiles.drew")
    }
}

/// This phone's seats in the stash's band while another seat plays: tap one to peek.
struct TilesLocalCats: View {
    let cats: [(seat: Seat, person: Person)]
    let onTap: (Seat) -> Void

    var body: some View {
        HStack(spacing: 22) {
            ForEach(cats, id: \.seat) { cat in
                Button {
                    Haptics.shared.tick()
                    Sound.shared.play(ArtName.Sound.sfxPop)
                    onTap(cat.seat)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Palette.night.opacity(0.85))
                            .overlay(Circle().strokeBorder(SeatInfo.ringColor(cat.seat), lineWidth: 5))
                            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2).padding(-1))
                        Image(ArtName.cat(cat.person.cat, .idle)).resizable().scaledToFit().padding(4)
                    }
                    .frame(width: 64, height: 64)
                    .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
                    .overlay(alignment: .bottom) { NameTag(cat.person.name, maxWidth: 96).offset(y: 14) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Peek at \(cat.person.name)'s stash", comment: "VoiceOver: one of this phone's players; opens the curtain for them"))
                .accessibilityIdentifier("table.local.\(cat.seat)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The end of a tile game: who won, and everyone's score and what they were left with. Leftover
/// racks are never shown, only their totals (tile game spec §4.7).
struct TilesOverView: View {
    /// The Play again pill: ask for a new table, waiting on the server, go to the table someone
    /// dealt, or off (the server no longer deals this game).
    enum Again: Equatable { case ask, waiting, go, off }

    let table: TilesTableModel
    let winners: [Seat]
    var again: Again?
    var onPlayAgain: () -> Void = {}
    let onHome: () -> Void

    static var offWords: String {
        String(localized: "This game is off for now.", comment: "Tile game over: Play again was refused because the server stopped dealing this game")
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var title: String {
        let names = winners.map { SeatInfo.name(table.room, $0) }.formatted(.list(type: .and))
        return winners.count > 1
            ? String(localized: "\(names) win!", comment: "Game over title: a shared win")
            : String(localized: "\(names) wins!", comment: "Game over title")
    }

    private var reason: String {
        switch table.view.endReason {
        case .blocked: String(localized: "Nobody could move.", comment: "Tile game over: the game was blocked")
        case .forfeit: String(localized: "Everyone else left.", comment: "Tile game over: won by forfeit")
        default: String(localized: "Stash empty!", comment: "Tile game over: someone emptied their rack")
        }
    }

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.72).ignoresSafeArea()
            // The winners shrink on a short screen (an iPhone SE) before Home leaves it; at the
            // largest text sizes the column scrolls.
            ViewThatFits(in: .vertical) {
                column(cat: 150, vertical: 32)
                column(cat: 96, vertical: 16)
                ScrollView { column(cat: 96, vertical: 16) }
            }
        }
        .onAppear {
            Sound.shared.play(ArtName.Sound.sfxFanfare)
            Haptics.shared.celebrate()
            withAnimation(.spring(duration: 0.5, bounce: 0.45).paced) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-tiles-over")
    }

    private func column(cat: CGFloat, vertical: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: -18) {
                ForEach(winners, id: \.self) { seat in
                    Image(ArtName.cat(SeatInfo.catIndex(table.room.seats[safe: seat]), .celebrate))
                        .resizable().scaledToFit().frame(width: cat, height: cat)
                }
            }
            .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
            .accessibilityHidden(true)
            OutlinedText(title, size: 38, fill: Palette.orange, width: 5, lines: 2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("tiles.over.title")
            OutlinedText(reason, size: 18, lines: 2)
            VStack(spacing: 8) {
                ForEach(Array(table.standings.enumerated()), id: \.element) { place, seat in
                    row(place: place + 1, seat: seat)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22).fill(Palette.night).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.ink, lineWidth: 4)))
            if again == .off {
                OutlinedText(Self.offWords, size: 17, fill: Palette.orange, lines: 3)
                    .accessibilityIdentifier("tiles.over.off")
                    .padding(.top, 4)
            }
            // Play again and Home on one row (Home as its icon alone beside Play again), so
            // both fit a small phone without scrolling.
            HStack(spacing: 14) {
                if let again, again != .off {
                    PillButton(
                        icon: ArtName.iconPlay, color: again == .waiting ? Palette.violet : Palette.orange, size: .medium, width: 210,
                        title: again == .go
                            ? String(localized: "Join", comment: "Game over: someone dealt the next table; join it")
                            : again == .waiting
                                ? String(localized: "Dealing…", comment: "Game over: Play again was asked and the server hasn't answered")
                                : String(localized: "Play again", comment: "Game over: deal a new table with the same players"),
                        accessibilityLabel: again == .go ? "Join the new game" : "Play again", action: onPlayAgain)
                        .accessibilityIdentifier("tiles.over.again")
                    PillButton(icon: ArtName.iconHome, color: Palette.sky, size: .medium, width: 84, accessibilityLabel: "Home", action: onHome)
                        .accessibilityIdentifier("tiles.over.home")
                } else {
                    PillButton(
                        icon: ArtName.iconHome, color: Palette.sky, size: .medium, width: 200,
                        title: String(localized: "Home", comment: "Game over: go home"), accessibilityLabel: "Home", action: onHome)
                        .accessibilityIdentifier("tiles.over.home")
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, vertical)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private func row(place: Int, seat: Seat) -> some View {
        let out = table.view.isOut(seat)
        let score = table.view.scores[safe: seat] ?? 0
        let name = SeatInfo.name(table.room, seat)
        return HStack(spacing: 10) {
            OutlinedText("\(place)", size: 24, fill: winners.contains(seat) ? Palette.orange : .white)
                .frame(width: 30)
            Image(ArtName.cat(SeatInfo.catIndex(table.room.seats[safe: seat]), .idle))
                .resizable().scaledToFit().frame(width: 44, height: 44)
            OutlinedText(name, size: 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            if out {
                OutlinedText(String(localized: "Forfeited", comment: "Game over row: a player who left"), size: 16, fill: Palette.refuse)
            } else {
                OutlinedText(score > 0 ? "+\(score)" : "\(score)", size: 24, fill: score > 0 ? Palette.lime : .white)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(out
            ? Text("\(place). \(name), forfeited", comment: "VoiceOver: a game over row for a player who left")
            : Text("\(place). \(name), \(score) points", comment: "VoiceOver: a game over row"))
    }
}

/// The tile game's paw menu: sound, haptics, easy mode and its tricks, how to play, home and
/// forfeit (behind a confirmation).
struct TilesMenuSheet: View {
    @Environment(Settings.self) private var settings
    let tableName: String
    @State var easy: Bool
    @State var tricks: Bool
    let forfeit: (seat: Seat, table: TilesTableModel)?
    let onEasy: (Bool) -> Void
    let onTricks: (Bool) -> Void
    let onHome: () -> Void
    let onForfeit: (Seat) -> Void
    let onClose: () -> Void

    @State private var rules = false
    @State private var confirming = false

    var body: some View {
        Group {
            if rules {
                HowToPlaySheet(game: GameCatalog.tiles) { rules = false }
            } else {
                menu
            }
        }
        .presentationDetents(rules ? [.large] : [.height(forfeit == nil ? 520 : 600)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.night)
    }

    private var menu: some View {
        VStack(spacing: 18) {
            OutlinedText(tableName, size: 26, fill: Palette.orange, lines: 2)
                .padding(.horizontal, 20)
            HStack(spacing: 18) {
                PillButton(
                    icon: settings.soundOn ? ArtName.iconSoundOn : ArtName.iconSoundOff,
                    color: settings.soundOn ? Palette.teal : Palette.violet, size: .medium,
                    accessibilityLabel: settings.soundOn ? "Sound on" : "Sound off"
                ) { settings.soundOn.toggle() }
                    .accessibilityIdentifier("menu.sound")
                PillButton(
                    icon: settings.hapticsOn ? ArtName.iconHapticsOn : ArtName.iconHapticsOff,
                    color: settings.hapticsOn ? Palette.orange : Palette.violet, size: .medium,
                    accessibilityLabel: settings.hapticsOn ? "Haptics on" : "Haptics off"
                ) { settings.hapticsOn.toggle() }
                    .accessibilityIdentifier("menu.haptics")
            }
            PillButton(
                icon: nil, color: easy ? Palette.lime : Palette.violet, size: .medium, width: 250,
                title: easy
                    ? String(localized: "Easy mode: on", comment: "Tile game menu: the easy mode toggle")
                    : String(localized: "Easy mode: off", comment: "Tile game menu: the easy mode toggle"),
                accessibilityLabel: easy ? "Easy mode on" : "Easy mode off"
            ) {
                easy.toggle()
                onEasy(easy)
            }
            .accessibilityIdentifier("menu.easy")
            if easy {
                PillButton(
                    icon: nil, color: tricks ? Palette.magenta : Palette.violet, size: .medium, width: 250,
                    title: tricks
                        ? String(localized: "Tricks: on", comment: "Tile game menu: rearranging the rug in easy mode")
                        : String(localized: "Tricks: off", comment: "Tile game menu: rearranging the rug in easy mode"),
                    accessibilityLabel: tricks ? "Tricks on: open, split and join sets" : "Tricks off"
                ) {
                    tricks.toggle()
                    onTricks(tricks)
                }
                .accessibilityIdentifier("menu.tricks")
            }
            PillButton(
                icon: nil, color: Palette.orange, size: .medium, width: 250,
                title: String(localized: "How to play", comment: "Table menu: open the rules"), accessibilityLabel: "How to play"
            ) { rules = true }
                .accessibilityIdentifier("menu.rules")
            PillButton(icon: ArtName.iconHome, color: Palette.sky, size: .medium, accessibilityLabel: "Home", action: onHome)
                .accessibilityIdentifier("menu.home")
            if let forfeit {
                PillButton(
                    icon: nil, color: Palette.refuse, size: .medium, width: 250,
                    title: String(localized: "Forfeit", comment: "Table menu: give up this game (asks first)"),
                    accessibilityLabel: "Forfeit this game"
                ) { confirming = true }
                    .accessibilityIdentifier("menu.forfeit")
                    .alert(forfeitTitle(forfeit), isPresented: $confirming) {
                        Button(String(localized: "Forfeit", comment: "Forfeit confirmation: the destructive button"), role: .destructive) {
                            onForfeit(forfeit.seat)
                        }
                        .accessibilityIdentifier("forfeit.confirm")
                        Button(String(localized: "Keep playing", comment: "Forfeit confirmation: back to the game"), role: .cancel) {}
                    } message: {
                        Text(forfeitMessage(forfeit))
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-tiles-menu")
    }

    private func forfeitTitle(_ forfeit: (seat: Seat, table: TilesTableModel)) -> String {
        guard forfeit.table.isMultiSeat else { return String(localized: "Forfeit this game?", comment: "Forfeit confirmation title") }
        return String(localized: "Forfeit for \(SeatInfo.name(forfeit.table.room, forfeit.seat))?", comment: "Forfeit confirmation title on a shared phone: whose seat")
    }

    private func forfeitMessage(_ forfeit: (seat: Seat, table: TilesTableModel)) -> String {
        switch forfeit.table.forfeitOutcome(forfeit.seat) {
        case .ends(let winner):
            return String(localized: "\(SeatInfo.name(forfeit.table.room, winner)) wins.", comment: "Forfeit confirmation: with one other player left, the game ends and they win")
        case .out:
            return forfeit.table.isMultiSeat
                ? String(localized: "\(SeatInfo.name(forfeit.table.room, forfeit.seat)) finishes last. The rest play on.", comment: "Forfeit confirmation on a shared phone: that seat is out, the rest play on")
                : String(localized: "You finish last. The rest play on.", comment: "Forfeit confirmation: you are out, the rest play on")
        }
    }
}
