import PounceKit
import SwiftUI

/// What Birdwatch's scene tells its shell.
@MainActor @Observable
final class BirdStageEvents {
    var menuOpen = false
    var scoresOpen = false
    /// The seat whose hand is face up (nil: none).
    var shown: Seat?
    /// Set once the game is over and its last trick has played.
    var winners: [Seat]?
    /// The sill in the view's points (top-left origin): where the phase panels sit.
    var sill: CGRect = .zero
    /// The hand band's top, in points from the bottom edge: what the pass-and-play curtain covers.
    var bandTop: CGFloat = 0
    var tipSpots: [String: CGRect] = [:]
    /// The hand that just ended, for the summary card.
    var summary: BirdHandResult?
    var putBack = 0
    var tableTaps = 0
    /// The words of a refused tap, for a moment.
    var note: Note?

    struct Note: Equatable {
        var text: String
        var serial: Int
    }
}

/// Birdwatch's table for one session (design §5): the SpriteKit scene and over it the phase
/// panels on the sill, the pass-and-play curtain over the hand, the summary between hands, the
/// pills, the score sheet, the menu and the game over card. The window and the sill are public,
/// so the curtain only ever covers the hand's band (§5.5); the scene never builds a hand for a
/// seat that isn't shown, and the panels only come for the shown seat.
struct BirdStage: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let session: RoomSession
    let connection: RoomStore.Connection

    @State private var scene: BirdScene?
    @State private var events = BirdStageEvents()
    @State private var houseCatPill: RoomStore.ForfeitNotice?
    @State private var playAgain = PlayAgain()
    @State private var againTick = 0
    @State private var gameOff = false
    @State private var partnerSheet = false
    /// The hand whose summary was tapped away.
    @State private var dismissedHand: Int?

    private var table: BirdTableModel? { session.store.room.flatMap(BirdTableModel.init(room:)) }
    private var pass: PassAndPlay { session.store.pass }
    /// A TV shows this table: the phone shows just the hand and the controls (ruling 1).
    private var onTV: Bool { session.store.room?.screen == true && !(table?.mySeats.isEmpty ?? true) }

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

    private var localCats: [(seat: Seat, person: Person)] {
        guard events.winners == nil, let table, table.mySeats.count > 1, !table.isMyTurn, case .none = pass.state,
              table.isLive else { return [] }
        return table.mySeats.compactMap { seat in table.room.seats[safe: seat]?.person.map { (seat, $0) } }
    }

    /// The panel for the face-up hand, or the waiting line.
    private var panel: BirdTableModel.Panel? {
        guard events.winners == nil, curtainSeat == nil, let table else { return nil }
        return table.panel(for: events.shown)
    }

    /// Between hands: the hand that just ended (from the room, so a reconnect shows it too).
    private var summary: BirdHandResult? {
        guard events.winners == nil, let table, table.view.phase == .between, let last = table.view.history.last,
              last.hand == table.view.hand, dismissedHand != last.hand else { return nil }
        return last
    }

    #if DEBUG
    private var probe: String {
        guard let table else { return "phase=none" }
        let v = table.view
        let mine = table.mySeats.map(String.init).joined(separator: ",")
        return "phase=\(v.phase.rawValue) hand=\(v.hand) turn=\(v.turn.map(String.init) ?? "-") mine=\(mine) shown=\(events.shown.map(String.init) ?? "-") "
            + "played=\(v.played.count) scores=\(v.scores.map(String.init).joined(separator: ",")) over=\(events.winners != nil ? 1 : 0)"
    }
    #endif

    private var status: (text: String, mine: Bool)? {
        guard onTV, let table, let seat = table.currentSeat else { return nil }
        return StatusLine.turn(name: SeatInfo.name(table.room, seat), mine: table.mySeats.contains(seat), shared: table.isMultiSeat)
    }

    var body: some View {
        @Bindable var events = events
        ZStack {
            if let scene {
                BirdTableView(scene: scene)
                    .ignoresSafeArea()
                    .overlay { TipSpots(spots: events.tipSpots).ignoresSafeArea() }
            } else {
                RoomBackground()
            }
            panels
                .zIndex(TableLayer.controls)
            #if DEBUG
            // The UI tests' probe: the hand's phase and where the game stands.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("bird.debug")
                .accessibilityValue(Text(verbatim: probe))
                .allowsHitTesting(false)
            #endif
            if let status {
                VStack {
                    StatusLine(text: status.text, mine: status.mine)
                        .padding(.top, horizontalSizeClass == .regular ? 74 : 56)
                    Spacer()
                }
                .allowsHitTesting(false)
                .zIndex(TableLayer.controls)
            }
            if let note = events.note {
                VStack {
                    OutlinedText(note.text, size: 20, fill: Palette.yellow, width: 3)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Capsule().fill(Palette.ink.opacity(0.85)))
                        .padding(.top, max(events.sill.minY - 4, 60))
                    Spacer()
                }
                .id(note.serial)
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityIdentifier("bird.note")
                .zIndex(TableLayer.note)
            }
            // The curtain covers the hand's band only: the window stays in view.
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
                        TilesCurtain(person: person, peeking: peeking, cards: true, onBack: {
                            session.store.hidePass()
                            scene?.refresh()
                        }) {
                            session.store.completeHold()
                            scene?.refresh()
                        }
                        .id(pass.curtains)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                    }
                }
                .frame(height: max(events.bandTop, 0))
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .ignoresSafeArea()
            .zIndex(TableLayer.curtain)

            if let result = summary, let table {
                BirdSummary(result: result, model: table) { withAnimation(.easeOut(duration: 0.2).paced) { dismissedHand = result.hand } }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(TableLayer.scoreboard)
            }
            if let pill = houseCatPill, let table {
                VStack {
                    HouseCatPill(name: SeatInfo.name(table.room, pill.seat))
                        .padding(.top, horizontalSizeClass == .regular ? 120 : 64)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(TableLayer.lookPill)
            }
            if connection != .good, events.winners == nil, !events.menuOpen {
                VStack {
                    ConnectionPill(connection: connection)
                        .padding(.top, horizontalSizeClass == .regular ? 120 : 64)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(TableLayer.connection)
            }
            if let winners = events.winners, let table {
                BirdOverView(model: table, winners: winners, again: againState, onPlayAgain: tapPlayAgain) { model.goHome() }
                    .transition(.opacity)
                    .zIndex(TableLayer.gameOver)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.15).paced, value: curtainSeat)
        .animation(.easeOut(duration: 0.2).paced, value: localCats.map(\.seat))
        .animation(.easeOut(duration: 0.3).paced, value: events.winners)
        .animation(.easeOut(duration: 0.2).paced, value: events.note)
        .animation(.spring(duration: 0.3, bounce: 0.2).paced, value: panel)
        .animation(.spring(duration: 0.4, bounce: 0.3).paced, value: summary)
        .animation(.spring(duration: 0.35, bounce: 0.3).paced, value: connection)
        .onChange(of: events.winners != nil) { _, over in if over { model.tips.note(.gameOver) } }
        // The face-up hand's person gets the tips; none while a curtain, a sheet, the summary or
        // game over is up.
        .tipHost(.birdwatch, paused: curtainSeat != nil || events.menuOpen || events.scoresOpen || partnerSheet
                    || summary != nil || events.winners != nil,
                 person: events.shown.flatMap { table?.room.seats[safe: $0]?.person?.id })
        .task {
            await BirdCardFactory.shared.prewarm()
            guard !Task.isCancelled else { return }
            attach()
        }
        .onDisappear { session.detachTable() }
        .onChange(of: onTV, initial: true) { _, tv in scene?.handOnly = tv }
        .onChange(of: BirdStageInput(room: session.store.room, pass: pass), initial: true) {
            scene?.refresh()
        }
        .onChange(of: panel, initial: true) { _, panel in
            let calling = if case .partner = panel { true } else { false }
            if calling != partnerSheet { partnerSheet = calling }
        }
        .onChange(of: session.store.houseCatNotice) { _, notice in
            guard let notice else { return }
            Sound.shared.play(ArtName.Sound.sfxThud, volume: 0.7, kind: .game)
            withAnimation(.spring(duration: 0.45, bounce: 0.4).paced) { houseCatPill = notice }
            Task {
                try? await Task.sleep(for: Pace.duration(.seconds(3)))
                if houseCatPill == notice { withAnimation(.easeIn(duration: 0.3).paced) { houseCatPill = nil } }
            }
        }
        .onChange(of: session.store.rematch) { _, code in
            if let code, let go = playAgain.arrived(code: code) { model.openRematch(code: go, from: session.code) }
        }
        .onChange(of: session.lobbyNope) {
            if session.store.lastError == .gameOff {
                gameOff = true
                UIAccessibility.post(notification: .announcement, argument: BirdOverView.offWords)
            }
            if playAgain.waiting { playAgain.refused() }
        }
        .onChange(of: events.tableTaps) {
            guard peeking, case .revealed = pass.state else { return }
            session.store.hidePass()
            scene?.refresh()
        }
        .onChange(of: model.tvSheet?.id) { _, id in if id != nil { events.menuOpen = false } }
        .sheet(isPresented: $events.menuOpen) {
            BirdMenuSheet(
                code: session.code,
                tableName: session.store.room?.title ?? TableName.fallback(code: session.code),
                rules: session.store.room?.birdRules ?? .official,
                forfeit: model.ageBand == .kitten ? nil : table.flatMap { table in table.forfeitSeat(shown: events.shown).map { ($0, table) } },
                onHome: {
                    events.menuOpen = false
                    model.goHome()
                },
                onForfeit: { seat in
                    events.menuOpen = false
                    if !session.store.actBirdwatch(seat: seat, .forfeit) { session.send(.actBirdwatch(seat: seat, action: .forfeit)) }
                },
                onClose: { events.menuOpen = false })
                .environment(settings)
                .environment(model)
        }
        .sheet(isPresented: $events.scoresOpen) {
            if let table {
                BirdScoreSheet(model: table) { events.scoresOpen = false }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Palette.night)
            }
        }
        .sheet(isPresented: $partnerSheet) {
            if case .partner(let choices) = panel, let seat = events.shown {
                BirdPartnerPicker(choices: choices, trump: table?.view.trump) { card in
                    partnerSheet = false
                    session.store.actBirdwatch(seat: seat, .partner(card))
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-birdwatch")
    }

    /// The phase panel over the sill (or, with a TV, in the room over the hand).
    @ViewBuilder private var panels: some View {
        let sill = events.sill
        if let panel, sill.width > 0 {
            Group {
                switch panel {
                case .bid(let range):
                    BirdBidPanel(range: range) { amount in act(.bid(amount)) } onPass: { act(.pass) }
                case .nest(let count, _):
                    BirdNestBar(count: count, marked: events.putBack) { scene?.sendPutBack() }
                case .trump(let hint):
                    BirdTrumpPanel(hint: hint, onPick: { suit in act(.trump(suit)) }, room: sill.size)
                case .partner:
                    PillButton(icon: nil, color: Palette.orange, size: .medium, width: 220,
                               title: String(localized: "Call a partner", comment: "Birdwatch: reopen the partner picker"),
                               accessibilityLabel: "Call a partner") { partnerSheet = true }
                        .accessibilityIdentifier("bird.partner.open")
                case .waiting(let phase, let seat):
                    BirdWaitingLine(phase: phase, name: table.map { SeatInfo.name($0.room, seat) } ?? "")
                }
            }
            .frame(width: sill.width, height: sill.height, alignment: panelAlignment(panel))
            .position(x: sill.midX, y: sill.midY)
            .ignoresSafeArea()
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private func panelAlignment(_ panel: BirdTableModel.Panel) -> Alignment {
        switch panel {
        case .nest: .bottom
        case .waiting: .center
        default: .center
        }
    }

    private func act(_ action: BirdAction) {
        guard let seat = events.shown else { return }
        if case .bid = action { model.tips.used("bird.bid") }
        if case .pass = action { model.tips.used("bird.bid") }
        session.store.actBirdwatch(seat: seat, action)
    }

    private var againState: BirdOverView.Again? {
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
            Task {
                try? await Task.sleep(for: .seconds(PlayAgain.wait + 0.2))
                againTick += 1
            }
        case .jump(let code): model.openRematch(code: code, from: session.code)
        case .none: break
        }
    }

    private func attach() {
        let scene = self.scene ?? BirdScene(store: session.store)
        let events = events
        scene.handOnly = onTV
        scene.onMenu = { [weak events] in events?.menuOpen = true }
        scene.onScores = { [weak events] in events?.scoresOpen = true }
        scene.onSwipeHome = { [weak model] in model?.goHome() }
        scene.onGameOver = { [weak events] winners in events?.winners = winners }
        scene.onShownSeat = { [weak events] seat in events?.shown = seat }
        scene.onTableTap = { [weak events] in events?.tableTaps += 1 }
        scene.onTipSpots = { [weak events] spots in events?.tipSpots = spots }
        scene.onTipUsed = { [weak model] control in model?.tips.used(control) }
        scene.onPutBack = { [weak events] n in events?.putBack = n }
        scene.onSill = { [weak events] rect in if events?.sill != rect { events?.sill = rect } }
        scene.onBand = { [weak events] top in if events?.bandTop != top { events?.bandTop = top } }
        scene.onNope = { [weak events] words in
            events?.note = .init(text: words, serial: (events?.note?.serial ?? 0) + 1)
            let serial = events?.note?.serial
            Task { [weak events] in
                try? await Task.sleep(for: Pace.duration(.seconds(1.6)))
                if events?.note?.serial == serial { events?.note = nil }
            }
        }
        self.scene = scene
        session.attachTable { [weak scene] intent in scene?.enqueue(intent) }
        scene.reconcileFromStore()
        #if DEBUG
        if CommandLine.arguments.contains("-show-scores") { events.scoresOpen = true }
        #endif
    }
}

private struct BirdStageInput: Equatable {
    var room: RoomView?
    var pass: PassAndPlay
}

/// "Mia left. A House Cat plays on." floating down (design §4.9).
struct HouseCatPill: View {
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            Image(ArtName.cat(SeatInfo.botCat, .awake)).resizable().scaledToFit().frame(width: 40, height: 40)
            OutlinedText(String(localized: "\(name) left. A House Cat plays on.", comment: "Birdwatch notice: a player left and the House Cat took their seat"),
                         size: 18, lines: 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.violet).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 4)))
        .shadow(color: Palette.ink.opacity(0.5), radius: 0, x: 0, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bird.housecat.pill")
    }
}

/// Birdwatch's paw menu: sound, haptics and home in one row, then Show on TV, how to play (this
/// table's rule set) and forfeit (behind a confirmation: a House Cat plays on for you).
struct BirdMenuSheet: View {
    @Environment(Settings.self) private var settings
    let code: String
    let tableName: String
    let rules: BirdRules
    let forfeit: (seat: Seat, table: BirdTableModel)?
    let onHome: () -> Void
    let onForfeit: (Seat) -> Void
    let onClose: () -> Void

    @State private var howTo = false
    @State private var tv = false
    @State private var confirming = false

    var body: some View {
        Group {
            if howTo {
                HowToPlaySheet(game: GameCatalog.birdwatch, exit: .back, birdRules: rules) { howTo = false }
            } else if tv {
                ShowOnTVSheet(code: code, onBack: { tv = false }, onClose: onClose)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                menu.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.25).paced, value: tv)
        .presentationDetents(howTo || tv ? [.large] : [.height(forfeit == nil ? 420 : 500)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.night)
    }

    private var menu: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Color.clear.frame(width: SheetBar.side, height: 1)
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    OutlinedText(tableName, size: 26, fill: Palette.orange, lines: 2)
                    OutlinedText(BirdWords.rules(rules), size: 16, width: 2.5)
                }
                Spacer(minLength: 0)
                SheetCloseButton(action: onClose).accessibilityIdentifier("menu.close")
            }
            .padding(.horizontal, 16)
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
                PillButton(icon: ArtName.iconHome, color: Palette.sky, size: .medium, accessibilityLabel: "Home", action: onHome)
                    .accessibilityIdentifier("menu.home")
            }
            PillButton(icon: ArtName.iconTV, color: Palette.magenta, size: .medium, width: 250,
                       title: String(localized: "Show on TV", comment: "Table menu: put this table on a TV"), accessibilityLabel: "Show on TV") { tv = true }
                .accessibilityIdentifier("menu.tv")
            PillButton(icon: nil, color: Palette.orange, size: .medium, width: 250,
                       title: String(localized: "How to play", comment: "Table menu: open the rules"), accessibilityLabel: "How to play") { howTo = true }
                .accessibilityIdentifier("menu.rules")
            if let forfeit {
                PillButton(icon: nil, color: Palette.refuse, size: .medium, width: 250,
                           title: String(localized: "Leave game", comment: "Birdwatch menu: leave; a House Cat takes the seat (asks first)"),
                           accessibilityLabel: "Leave game") { confirming = true }
                    .accessibilityIdentifier("menu.forfeit")
                    .alert(forfeitTitle(forfeit), isPresented: $confirming) {
                        Button(String(localized: "Leave", comment: "Birdwatch leave confirmation: the destructive button"), role: .destructive) {
                            onForfeit(forfeit.seat)
                        }
                        .accessibilityIdentifier("forfeit.confirm")
                        Button(String(localized: "Keep playing", comment: "Forfeit confirmation: back to the game"), role: .cancel) {}
                    } message: {
                        Text("A House Cat plays on for your team.", comment: "Birdwatch leave confirmation: what happens to the seat")
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-bird-menu")
    }

    private func forfeitTitle(_ forfeit: (seat: Seat, table: BirdTableModel)) -> String {
        guard forfeit.table.isMultiSeat else { return String(localized: "Leave this game?", comment: "Birdwatch leave confirmation title") }
        return String(localized: "Leave for \(SeatInfo.name(forfeit.table.room, forfeit.seat))?", comment: "Birdwatch leave confirmation title on a shared phone")
    }
}
