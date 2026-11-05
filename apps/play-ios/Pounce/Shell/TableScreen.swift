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
        .animation(.spring(duration: 0.4, bounce: 0.25).paced, value: screen)
        .animation(.spring(duration: 0.3).paced, value: reconnecting)
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

/// The SpriteKit table for one session. Owns the scene (made once, kept across redraws) and shows
/// pass-and-play (spec §5.9) as the store decides it (`RoomStore.pass`, updated with every room
/// the store applies). The curtain is read from the store in `body`, never from state an
/// `onChange` keeps: SwiftUI runs an `onChange` action at most once per frame and drops a second
/// change in the same frame, which once left a seat's turn face down with no curtain. Room and
/// reveal changes reconcile the scene with the store's `revealed` seat and turn epoch (the scene
/// also hides a stale reveal by itself, and redraws from the store after every action). Over it:
/// the first-game coach's tips (`CoachMark`), the scoreboard (tap the tower), the local cats row
/// on a multi-seat phone, the pass-and-play curtain and, once the scene has played the win, the
/// game-over overlay. Under all of those, the turn cue (`TurnCueView`): "Your turn" when a hand
/// of this phone is up (after its curtain), "Mochi's turn" under whoever else is.
///
/// Privacy: on a multi-seat phone the curtain covers the table whenever `RoomStore.pass` says so,
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
    /// What the scene's callbacks set (see `StageEvents`).
    @State private var events = StageEvents()
    /// The push priming screen is up (spec §10).
    @State private var priming = false
    @State private var primingChecked = false
    /// The first-game tips for whoever's hand is face up (each person's first games).
    @State private var coach = Coach()
    /// The app went to the background: back on this phone's turn, the turn cue plays again.
    @State private var backgrounded = false
    /// The game over screen's Play again (§10.4).
    @State private var playAgain = PlayAgain()
    /// The look pill floating down after someone changed the table (§9.4).
    @State private var lookPill: RoomStore.LookChange?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var table: TableModel? { session.store.room.map(TableModel.init(room:)) }
    private var pass: PassAndPlay { session.store.pass }

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

    /// The table as the coach should see it: nothing while tips are off, or while the curtain, the
    /// scoreboard, the menu, the push priming or the game over is up.
    private var coachView: TableCoach? {
        guard model.tipsEnabled, curtainSeat == nil, events.scoreboard == nil, events.winners == nil, !priming,
              !events.menuOpen else { return nil }
        return events.coach
    }

    /// The turn cue as it should show now: nothing while the curtain, the scoreboard, the menu,
    /// the push priming or the game over is up (it plays once they are gone).
    private var turnCue: TurnCue? {
        guard curtainSeat == nil, events.scoreboard == nil, events.winners == nil, !priming, !events.menuOpen else { return nil }
        return events.turnCue
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
                    session.store.peek(seat)
                    sync()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottom)))
            }
            if let badge = tableStreak, events.winners == nil {
                GeometryReader { geo in
                    TableStreakBadge(badge: badge, stamp: session.stamp, at: streakBadgeCenter(geo), scale: streakScale)
                }
                .ignoresSafeArea()
                .transition(.scale.combined(with: .opacity))
                .zIndex(3)
            }
            if let pill = lookPill, let seat = table?.room.seats[safe: pill.seat] {
                VStack {
                    LookPill(cat: SeatInfo.catIndex(seat), art: lookArt(pill), isBack: lookIsBack(pill))
                        .padding(.top, 70)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(6)
            }
            probes
            if let cue = turnCue {
                TurnCueView(cue: cue, yield: coach.tip != nil && coachView != nil)
                    .transition(.opacity.combined(with: .scale(scale: cue.isMine ? 0.85 : 1)))
                    .zIndex(4)
            }
            if let tip = coach.tip, let shown = coachView, shown.person.id == coach.person {
                CoachMark(
                    tip: tip, coach: shown,
                    onOK: {
                        coach.dismiss()
                        feedCoach(allowNew: false)
                    },
                    onOff: {
                        coach.turnOff()
                        feedCoach(allowNew: false)
                    })
                    .id(tip)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .zIndex(5)
            }
            if let board = events.scoreboard, events.winners == nil, board.game != nil {
                // The table as the scene drew it when the tower was tapped, not the store's
                // newer truth: no spoiling a round-over still animating.
                ScoreboardOverlay(model: board, focus: TableScene.bottomSeat(board, revealed: events.shown)) {
                    events.scoreboard = nil
                }
                    .transition(.opacity)
            }
            if let seat = curtainSeat {
                // The container drops in and lifts away; a curtain for someone else swaps
                // inside it at once, so the table never shows between two curtains.
                ZStack {
                    PassCurtainView(person: person(seat)) {
                        session.store.completeHold()
                        sync()
                    }
                    // A new curtain (even for the same seat) starts the hold afresh.
                    .id(pass.curtains)
                    .transition(.identity)
                }
                .transition(curtainTransition)
                .zIndex(10)
                .overlay(alignment: .topLeading) {
                    if peeking {
                        // A peek the person didn't mean: back to the table, nothing shown.
                        CornerHomeButton(label: "Back to the table") {
                            session.store.hidePass()
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
                    tableName: session.store.room?.title ?? TableName.fallback(code: session.code),
                    winners: people(winners),
                    standings: session.model.map(GameOverView.standings) ?? [],
                    onHome: { model.goHome() },
                    onNewGame: { Task { await model.newGame() } },
                    again: againState,
                    onPlayAgain: tapPlayAgain)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .animation(.easeOut(duration: 0.2).paced, value: events.scoreboard != nil)
        .animation(.easeOut(duration: 0.3).paced, value: events.winners)
        .animation(.spring(duration: 0.45, bounce: 0.15).paced, value: curtainSeat)
        .animation(.easeOut(duration: 0.2).paced, value: localCats.map(\.seat))
        .animation(.easeOut(duration: 0.25).paced, value: priming)
        .animation(.spring(duration: 0.35, bounce: 0.3).paced, value: coach.tip)
        // Out of the way fast once the table is touched.
        .animation(.easeOut(duration: 0.15).paced, value: turnCue)
        .onAppear(perform: attach)
        .onDisappear { session.detachTable() }
        .onChange(of: StageInput(room: session.store.room, pass: session.store.pass), initial: true) {
            // Can be skipped (at most one call per frame): the curtain doesn't depend on it, and
            // the scene redraws from the store after every action and hides a stale reveal itself.
            sync()
            checkPriming()
        }
        .onChange(of: coachView) { feedCoach(allowNew: false) }
        .onChange(of: session.store.lookChange) { _, change in
            guard let change else { return }
            Sound.shared.play(ArtName.Sound.sfxWhoosh)
            withAnimation(.spring(duration: 0.45, bounce: 0.4).paced) { lookPill = change }
            Task {
                try? await Task.sleep(for: Pace.duration(.seconds(2)))
                if lookPill == change { withAnimation(.easeIn(duration: 0.3).paced) { lookPill = nil } }
            }
        }
        .onChange(of: session.store.rematch) { _, code in
            // The phone that asked goes to the new table; the others' pill now jumps there.
            if let code, let go = playAgain.arrived(code: code) { model.openRematch(code: go) }
        }
        .onChange(of: session.lobbyNope) {
            // A refused Play again (the server said no): it can be asked again.
            if playAgain.waiting { playAgain.refused() }
        }
        // A new tip waits until the table has held still for a moment (and the last tip is gone).
        .task(id: CoachWait(table: coachView, tip: coach.tip)) {
            try? await Task.sleep(for: Pace.duration(.milliseconds(900)))
            guard !Task.isCancelled else { return }
            feedCoach(allowNew: true)
        }
        .onChange(of: coach.tip) { _, tip in
            guard let tip, let shown = coachView else { return }
            Sound.shared.play(ArtName.Sound.sfxPop)
            let words = CoachCopy.words(tip, shown)
            UIAccessibility.post(notification: .announcement, argument: "\(words.title). \(words.body)")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                backgrounded = true
            } else if phase == .active, backgrounded {
                backgrounded = false
                scene?.replayTurnCue()
            }
        }
        .onChange(of: model.tipsReplays) {
            coach.turnOn()
            feedCoach(allowNew: true)
        }
        .onChange(of: events.tableTaps) {
            // Tapping away from a peeked hand hides it again.
            guard peeking, case .revealed = pass.state else { return }
            session.store.hidePass()
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
        scene.onCoach = { [weak events] coach in
            if events?.coach != coach { events?.coach = coach }
        }
        scene.onTurnCue = { [weak events] cue in events?.turnCue = cue }
        self.scene = scene
        events.shown = scene.shownRevealed
        sync(scene)
        #if DEBUG
        // `-show-look` (screenshots): the table menu open on its look tray.
        if CommandLine.arguments.contains("-show-look") {
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                events.menuOpen = true
            }
        }
        // `-show-scoreboard` (screenshots): the scoreboard over the table as it opens.
        if CommandLine.arguments.contains("-show-scoreboard"), let room = session.store.room {
            events.scoreboard = TableModel(room: room)
        }
        #endif
        // Synchronous: buffered intents are queued ahead of live ones.
        session.attachTable { [weak scene] intent in
            scene?.enqueue(intent)
        }
    }

    /// Tells the coach what the table shows now and saves what that person has now seen.
    private func feedCoach(allowNew: Bool) {
        let shown = coachView
        let person = shown?.person.id
        let seen = person.flatMap { model.tipsSeen[$0] } ?? []
        let marked = coach.update(shown?.context, seen: seen, allowNew: allowNew && !(shown?.busy ?? true))
        if let person, !marked.isEmpty { model.markTipsSeen(marked, person: person) }
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

    // MARK: streaks and looks

    /// The badge for the top pair seated here (§10.3), once the server has streaks on.
    private var tableStreak: StreakBadge? {
        guard model.streaks.enabled != false, let table else { return nil }
        let mine = table.mySeats.compactMap { table.room.seats[safe: $0]?.person }
        let owner = model.people.owner?.id
        let ordered = mine.filter { $0.id == owner } + mine.filter { $0.id != owner }
        let candidates = ordered.flatMap { person in model.streaks.views(for: person.id).map { (person: person.id, view: $0) } }
        let others = table.room.seats.indices.filter { !table.mySeats.contains($0) }.compactMap { table.room.seats[$0].person }
        guard let pick = TableStreak.pick(code: session.code, candidates: candidates, reported: session.streakPairs, others: others)
        else { return nil }
        return StreakBadge.make(pick.view, all: [], signedIn: true, offersSignIn: false)
    }

    private var streakScale: CGFloat { horizontalSizeClass == .regular ? 1.15 : 0.8 }

    /// Just under the top bar's right end (the paw menu sits above it in the status bar's ear).
    private func streakBadgeCenter(_ geo: GeometryProxy) -> CGPoint {
        let size = geo.size
        let insets = geo.safeAreaInsets
        guard let table else { return CGPoint(x: size.width - 70, y: 140) }
        let bottom = TableScene.bottomSeat(table, revealed: events.shown)
        let n = max(table.barSeats(bottom: bottom).count, 1)
        let bar = TableLayout(size: size, safeTop: insets.top, safeBottom: insets.bottom, opponents: n).opponentsBar
        // Under the bar's name tags (the bar's frame holds the rings; the tags hang below it).
        return CGPoint(x: size.width - 84 * streakScale - insets.trailing, y: size.height - bar.minY + 104 * streakScale)
    }

    private func lookIsBack(_ change: RoomStore.LookChange) -> Bool {
        lastLook.map { $0.rug == change.look.rug } ?? false
    }

    private func lookArt(_ change: RoomStore.LookChange) -> String {
        lookIsBack(change) ? ArtName.Habit.back(change.look.back) : ArtName.Habit.rug(change.look.rug)
    }

    /// The look before the last change (for the pill: what changed).
    @State private var lastLook: Look?

    /// Hidden values for the UI tests: the table's look and code.
    private var probes: some View {
        let look = table?.room.look ?? .standard
        return ZStack {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("table.look")
                .accessibilityValue("\(look.rug)|\(look.back)")
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("table.code")
                .accessibilityValue(session.code)
        }
        .allowsHitTesting(false)
        .onChange(of: look, initial: true) { old, _ in lastLook = old }
    }

    private var againState: GameOverView.Again? {
        guard PlayAgain.available(session.store.room) else { return nil }
        if session.store.rematch != nil { return .go }
        return playAgain.waiting ? .waiting : .ask
    }

    private func tapPlayAgain() {
        switch playAgain.tap(room: session.store.room, rematch: session.store.rematch) {
        case .send: session.send(.rematch)
        case .jump(let code): model.openRematch(code: code)
        case .none: break
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

    /// The winners' people; a House Cat bot as `GameOverView.botWinner`.
    private func people(_ seats: [Seat]) -> [Person] {
        guard let room = session.store.room else { return [] }
        return seats.map { seat in
            room.seats[safe: seat]?.person ?? GameOverView.botWinner(name: SeatInfo.name(room, seat))
        }
    }

    /// Reconciles the scene with the store's room and pass-and-play reveal.
    private func sync(_ target: TableScene? = nil) {
        guard let room = session.store.room, let scene = target ?? scene else { return }
        let table = TableModel(room: room)
        #if DEBUG
        // `-demo handoff`: skip the hold so a hand is shown to hide later.
        if DemoMode.from() == .handoff, case .curtain = pass.state { session.store.completeHold() }
        #endif
        scene.setLook(room.look ?? .standard)
        // The scene hides at once when `revealed` goes away; a new reveal lands on its timeline.
        scene.reconcile(table, revealed: pass.revealed, epoch: pass.epoch)
        #if DEBUG
        scene.stageProbe = StageProbe(seq: session.store.lastSeq, pass: pass.state)
        scene.timelineLog("stage seq \(session.store.lastSeq) turn \(table.game?.turn ?? -1) \(table.game?.step.rawValue ?? "-") pass \(pass.state) shown \(String(describing: events.shown)) scene \(String(describing: scene.shownRevealed))")
        #endif
    }
}

/// What `TableStage` reacts to: the store's room and its pass-and-play decision.
private struct StageInput: Equatable {
    let room: RoomView?
    let pass: PassAndPlay
}

/// What the coach's settle timer restarts on.
private struct CoachWait: Equatable {
    let table: TableCoach?
    let tip: CoachTip?
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
    /// The scene's view of the face-up hand for the first-game coach.
    var coach: TableCoach?
    /// Whose turn the scene says to show.
    var turnCue: TurnCue?
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
            .overlay(alignment: .bottom) {
                NameTag(person.name, maxWidth: 96)
                    .offset(y: 14)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(
            "Peek at \(person.name)'s cards",
            comment: "VoiceOver: one of this phone's players in the row at the bottom; opens the curtain for them"))
        .accessibilityIdentifier("table.local.\(seat)")
    }
}
