import PounceKit
import SwiftUI

/// The room route. Makes sure the app model holds the live session for `code` (one socket for
/// the whole screen: `RoomSession` owns the `RoomSocket` + `RoomStore`, presence, reconnects and
/// the auto-claim), then shows lobby, table or a state card for the store's phase.
struct RoomContainer: View {
    @Environment(AppModel.self) private var model
    let code: String
    let intent: RoomIntent

    var body: some View {
        Group {
            if let session = model.room, session.code == code {
                TableScreen(session: session)
            } else {
                ConnectingView()
            }
        }
        .task(id: code) { model.ensureRoom(code: code, intent: intent) }
    }
}

/// Lobby ↔ table ↔ state cards for one session, plus the reconnecting yarn in a corner.
struct TableScreen: View {
    @Environment(AppModel.self) private var model
    let session: RoomSession

    private var store: RoomStore { session.store }

    private enum Screen: Equatable {
        case connecting, lobby, table, state(StateCard.Kind)
        /// A seat is being moved here from another phone, which holds no seat yet.
        case moveClaim(String, refused: Bool)
    }

    private var screen: Screen {
        switch store.phase {
        case .connecting:
            return session.offline ? .state(.offline) : .connecting
        case .lobby, .playing, .over:
            let seated = !(session.model?.mySeats.isEmpty ?? true)
            if !seated, let move = session.move {
                switch move {
                case .claiming(let code): return .moveClaim(code, refused: false)
                case .refused(_, .tooManyAttempts): return .state(.locked)
                case .refused(let code, _): return .moveClaim(code, refused: true)
                }
            }
            if store.phase == .lobby { return .lobby }
            // No spectating in M1: a game this phone isn't in is "full".
            return seated ? .table : .state(.full)
        case .stalled:
            return .state(.stalled)
        case .closed:
            return .state(.closed)
        case .notFound:
            // A bad code bounces to Join; a known table that 404'd closed.
            return session.goneMeaning == .badCode ? .connecting : .state(.closed)
        case .needsUpdate:
            return .state(.update)
        }
    }

    /// The yarn shows once the room is on screen and the socket is down.
    private var reconnecting: Bool {
        switch screen {
        case .lobby, .table: !store.connected
        default: false
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            if reconnecting {
                YarnIndicator()
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.25), value: screen)
        .animation(.spring(duration: 0.3), value: reconnecting)
        .onChange(of: session.model?.mySeats ?? []) { before, after in
            // This phone's last seat left while it held a move code: the move went through
            // (spec §5.11). Home, not the "full" card. The menu sheet is gone with the table.
            guard !before.isEmpty, after.isEmpty, store.moveCode != nil else { return }
            Haptics.shared.success()
            Sound.shared.play(ArtName.Sound.sfxSparkle)
            model.goHome()
        }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .connecting:
            ConnectingView()
        case .lobby:
            LobbyView(session: session, interactive: store.connected)
        case .table:
            TableStage(session: session)
                .allowsHitTesting(store.connected)
        case .state(let kind):
            StateCard(kind: kind, onRetry: kind == .offline ? { session.retry() } : nil) {
                model.goHome()
            }
        case .moveClaim(let code, let refused):
            MoveClaimView(moveCode: code, refused: refused) { model.goHome() }
        }
    }
}

/// Before the first snapshot: the room backdrop and a big spinning yarn.
struct ConnectingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            RoomBackground()
            YarnIndicator()
                .scaleEffect(1.8)
        }
        .overlay(alignment: .topLeading) {
            CornerHomeButton { model.goHome() }
                .padding(.leading, 16)
                .padding(.top, 4)
                .accessibilityIdentifier("room.home")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-connecting")
    }
}

/// The SpriteKit table for one session. Owns the scene (made once, kept across redraws) and
/// pass-and-play (spec §5.9): every room or turn-epoch change updates `PassAndPlay` with the
/// store's `turnEpoch` and reconciles the scene with its `revealed` seat and that epoch. SwiftUI
/// may coalesce several room changes into one update; the epoch (counted by the store on every
/// room it applies) still tells a skipped turn apart, so a stale reveal never comes back. Over it: the scoreboard (tap the tower), the local cats row on a
/// multi-seat phone, the pass-and-play curtain and, once the scene has played the win, the
/// game-over overlay.
///
/// Privacy: on a multi-seat phone the curtain covers the table whenever `PassAndPlay` says so,
/// and stays up after the hold until the scene reports that seat's hand is actually face up
/// (a reveal can wait for an animating event). While it is up the table takes no touches and
/// VoiceOver skips it. The scene itself never builds faces for an unrevealed seat. Outside
/// play (round over, game over) there is no curtain and no peeking: the celebration plays on
/// the table with every hand face down.
private struct TableStage: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    let session: RoomSession
    @State private var scene: TableScene?
    @State private var pass = PassAndPlay()
    /// What the scene's callbacks set (see `StageEvents`).
    @State private var events = StageEvents()
    /// Bumped each time a new curtain goes up, so a curtain for the same seat starts fresh.
    @State private var curtainKey = 0
    /// The push priming screen is up (spec §10).
    @State private var priming = false
    @State private var primingChecked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var table: TableModel? { session.store.room.map(TableModel.init(room:)) }

    /// The seat the curtain is up for: a curtain waiting for its hold, or a hold that is done
    /// while the scene hasn't shown that hand yet. Never on a one-seat phone.
    private var curtainSeat: Seat? {
        guard events.winners == nil, let table, table.isMultiSeat, table.game?.status == .playing else { return nil }
        switch pass.state {
        case .none: return nil
        case .curtain(let seat): return seat
        case .revealed(let seat): return events.shown == seat ? nil : seat
        }
    }

    /// Looking at a hand outside its turn: the curtain was opened from the local cats row.
    private var peeking: Bool {
        guard let table, table.isMultiSeat, !table.isMyTurn, table.game?.status == .playing else { return false }
        if case .none = pass.state { return false }
        return true
    }

    /// My seats along the bottom on a multi-seat phone while no seat of mine is playing and
    /// nothing is shown: tap one to peek at that hand.
    private var localCats: [(seat: Seat, person: Person)] {
        guard events.winners == nil, let table, table.isMultiSeat, !table.isMyTurn, case .none = pass.state,
              table.room.status == .playing, table.game?.status == .playing else { return [] }
        return table.mySeats.compactMap { seat in
            table.room.seats[safe: seat]?.person.map { (seat, $0) }
        }
    }

    var body: some View {
        @Bindable var events = events
        let covered = curtainSeat != nil
        ZStack {
            if let scene {
                TableView(scene: scene, covered: covered)
                    .ignoresSafeArea()
                    .accessibilityHidden(covered)
                    .allowsHitTesting(!covered)
            } else {
                RoomBackground()
            }
            if !localCats.isEmpty {
                LocalCatsRow(cats: localCats) { seat in
                    pass.peek(seat)
                    sync()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottom)))
            }
            if let board = events.scoreboard, events.winners == nil, board.game != nil {
                // The table as the scene drew it when the tower was tapped, not the store's
                // newer truth: no spoiling a round-over still animating.
                ScoreboardOverlay(model: board) { events.scoreboard = nil }
                    .transition(.opacity)
            }
            if let seat = curtainSeat {
                // The container drops in and lifts away; a curtain for someone else swaps
                // inside it at once, so the table never shows between two curtains.
                ZStack {
                    PassCurtainView(person: person(seat)) {
                        pass.completeHold()
                        sync()
                    }
                    .id(curtainKey)
                    .transition(.identity)
                }
                .transition(curtainTransition)
                .zIndex(10)
                .overlay(alignment: .topLeading) {
                    if peeking {
                        // A peek the person didn't mean: back to the table, nothing shown.
                        CornerHomeButton(label: "Back to the table") {
                            pass.hide()
                            sync()
                        }
                        .padding(.leading, 16)
                        .padding(.top, 4)
                        .accessibilityIdentifier("curtain.back")
                    }
                }
            }
            if priming, events.winners == nil {
                PushPrimingView(
                    person: primingPerson,
                    onAllow: {
                        priming = false
                        Task { await model.acceptPush() }
                    },
                    onNotNow: {
                        priming = false
                        model.declinePush()
                    })
                    .transition(.opacity)
                    .zIndex(15)
            }
            if let winners = events.winners {
                GameOverView(
                    winners: people(winners),
                    onHome: { model.goHome() },
                    onNewGame: { Task { await model.newGame() } })
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .animation(.easeOut(duration: 0.2), value: events.scoreboard != nil)
        .animation(.easeOut(duration: 0.3), value: events.winners)
        .animation(.spring(duration: 0.45, bounce: 0.15), value: curtainSeat)
        .animation(.easeOut(duration: 0.2), value: localCats.map(\.seat))
        .animation(.easeOut(duration: 0.25), value: priming)
        .onAppear(perform: attach)
        .onDisappear { session.detachTable() }
        .onChange(of: StageInput(room: session.store.room, epoch: session.store.turnEpoch), initial: true) {
            sync()
            checkPriming()
        }
        .onChange(of: events.tableTaps) {
            // Tapping away from a peeked hand hides it again.
            guard peeking, case .revealed = pass.state else { return }
            pass.hide()
            sync()
        }
        .sheet(isPresented: $events.menuOpen) {
            TableMenuSheet(
                session: session,
                onHome: {
                    events.menuOpen = false
                    model.goHome()
                },
                onClose: { events.menuOpen = false })
                .environment(model)
                .environment(settings)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-table")
    }

    /// The curtain drops in from above and lifts away like a stage curtain; with Reduce Motion
    /// it fades. Either way the hand under it is already face down when it arrives.
    private var curtainTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top)
    }

    private func attach() {
        let scene = self.scene ?? TableScene(store: session.store)
        // The callbacks hold `events` weakly and never this view: its `@State` owns the scene,
        // so capturing the view would keep the scene alive after leaving the table.
        let events = events
        scene.onMenu = { [weak events] in events?.menuOpen = true }
        scene.onTower = { [weak events] drawn in events?.scoreboard = drawn }
        scene.onGameOver = { [weak events] seats in events?.winners = seats }
        scene.onShownRevealed = { [weak events] seat in events?.shown = seat }
        scene.onTableTap = { [weak events] in events?.tableTaps += 1 }
        self.scene = scene
        events.shown = scene.shownRevealed
        sync(scene)
        // Synchronous: buffered intents are queued ahead of live ones.
        session.attachTable { [weak scene] intent in
            scene?.enqueue(intent)
        }
    }

    /// The first time this phone plays with a human on another phone, offer push — unless the
    /// system already has an answer (then there's nothing to prime).
    private func checkPriming() {
        guard !primingChecked, let table, PushPolicy.shouldPrime(model: table, primed: settings.pushPrimed),
              let push = model.push else { return }
        primingChecked = true
        Task {
            if await push.authorizationStatus() == .notDetermined {
                priming = true
            } else {
                settings.pushPrimed = true
            }
        }
    }

    /// The mock banner's player: this phone's first seat, else the owner.
    private var primingPerson: Person {
        if let seat = table?.mySeats.first { return person(seat) }
        return model.people.owner ?? Person(id: "", name: "", cat: 0)
    }

    /// The person at a seat of this phone (a placeholder if the snapshot lacks one).
    private func person(_ seat: Seat) -> Person {
        session.store.room?.seats[safe: seat]?.person ?? Person(id: "", name: "", cat: 0)
    }

    /// The winners' people; the House Cat bot as `GameOverView.botWinner`.
    private func people(_ seats: [Seat]) -> [Person] {
        let room = session.store.room
        return seats.map { seat in
            room?.seats[safe: seat]?.person ?? GameOverView.botWinner
        }
    }

    private func sync(_ target: TableScene? = nil) {
        guard let room = session.store.room, let scene = target ?? scene else { return }
        let table = TableModel(room: room)
        let before = pass.state
        pass.update(table, epoch: session.store.turnEpoch)
        #if DEBUG
        // `-demo handoff`: skip the hold so a hand is shown to hide later.
        if DemoMode.from() == .handoff, case .curtain = pass.state { pass.completeHold() }
        #endif
        if case .curtain = pass.state, pass.state != before { curtainKey += 1 }
        // The scene hides at once when `revealed` goes away; a new reveal lands on its timeline.
        scene.reconcile(table, revealed: pass.revealed, epoch: pass.epoch)
        #if DEBUG
        scene.timelineLog("stage seq \(session.store.lastSeq) turn \(table.game?.turn ?? -1) \(table.game?.step.rawValue ?? "-") pass \(pass.state) shown \(String(describing: events.shown)) scene \(String(describing: scene.shownRevealed))")
        #endif
    }
}

/// What `TableStage` reacts to: the store's room and its turn epoch.
private struct StageInput: Equatable {
    let room: RoomView?
    let epoch: Int
}

/// What the table scene's callbacks set, kept apart from `TableStage` so the scene's closures
/// can hold it weakly (see `TableStage.attach`).
@MainActor @Observable
private final class StageEvents {
    var menuOpen = false
    /// The scoreboard is up, showing this table (as the scene drew it).
    var scoreboard: TableModel?
    /// Set by the scene when the game-over celebration is done.
    var winners: [Seat]?
    /// The seat whose hand the scene shows face up right now (its `shownRevealed`).
    var shown: Seat?
    /// Bumped by a tap on the table itself while this phone can't act.
    var tableTaps = 0
}

/// The small cats of this phone's seats along the bottom, while another seat plays: tap one
/// to put the curtain up for that person and hold to peek at their hand.
private struct LocalCatsRow: View {
    let cats: [(seat: Seat, person: Person)]
    let onTap: (Seat) -> Void

    private static let side: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom)
            // The trays' strip, empty while no hand is face up (scene space: y up from the bottom).
            let trays = TableLayout(size: full, safeTop: insets.top, safeBottom: insets.bottom, opponents: 1).traysFrame
            HStack(spacing: 18) {
                ForEach(cats, id: \.seat) { cat in
                    LocalCat(seat: cat.seat, person: cat.person, side: Self.side) { onTap(cat.seat) }
                }
            }
            .position(x: geo.size.width / 2, y: full.height - trays.midY - insets.top)
        }
    }
}

private struct LocalCat: View {
    let seat: Seat
    let person: Person
    let side: CGFloat
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tick()
            Sound.shared.play(ArtName.Sound.sfxPop)
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(Palette.night.opacity(0.85))
                    .overlay(Circle().strokeBorder(SeatInfo.ringColor(seat), lineWidth: 5))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2).padding(-1))
                Image(ArtName.cat(person.cat, .idle))
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                Image(ArtName.badgePhone)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * 0.36, height: side * 0.36)
                    .offset(x: side * 0.36, y: side * 0.34)
            }
            .frame(width: side, height: side)
            .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(
            "Peek at \(person.name)'s cards",
            comment: "VoiceOver: one of this phone's players in the row at the bottom; opens the curtain for them"))
        .accessibilityIdentifier("table.local.\(seat)")
    }
}
