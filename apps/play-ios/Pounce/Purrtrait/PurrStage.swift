import PounceKit
import SwiftUI

/// Purrtrait's table on a phone or an iPad (spec §11.2, §11.3): the drawer's word pick and easel,
/// everyone else's "Look at the TV", the reveal and game over, under one top bar. On a shared
/// phone the curtain comes down before a word shows. The drawing turn's model lives here, one per
/// turn: it sends the ink, answers the room's resend, and ends the stroke when the app leaves.
struct PurrStage: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: RoomSession
    let connection: RoomStore.Connection

    @State private var draw: PurrDrawModel?
    @State private var revision = PurrCanvas.Revision()
    @State private var arrived = Date()
    @State private var gotItOpen = false
    @State private var menuOpen = false
    @State private var playAgain = PlayAgain()
    @State private var againTick = 0
    @State private var gameOff = false

    private var store: RoomStore { session.store }
    private var table: PurrTableModel? { store.room.flatMap(PurrTableModel.init(room:)) }

    private var curtainSeat: Seat? {
        guard let table, let seat = table.curtained else { return nil }
        if case .revealed(let shown) = store.pass.state, shown == seat { return nil }
        return seat
    }

    private var clock: PurrClock {
        PurrClock(deadline: table?.deadline(arrived: arrived), frozen: table?.view.remainingMs.map { $0 / 1000 })
    }

    var body: some View {
        ZStack {
            RoomBackground()
            if let table {
                VStack(spacing: 0) {
                    // The drawer's screen has the paw in its own top row, beside the word.
                    if !table.isDrawingHere { topBar(table) }
                    content(table)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let seat = curtainSeat, let person = table.room.seats[safe: seat]?.person {
                    PassCurtainView(person: person) { store.completeHold() }
                        .id(store.pass.curtains)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                        .zIndex(TableLayer.curtain)
                }
                if connection != .good {
                    VStack {
                        ConnectionPill(connection: connection).padding(.top, 60)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(TableLayer.connection)
                }
                if table.screen == .over {
                    PurrOverView(table: table, again: againState, onPlayAgain: tapPlayAgain) { model.goHome() }
                        .transition(.opacity)
                        .zIndex(TableLayer.gameOver)
                }
            } else {
                YarnIndicator().scaleEffect(1.6)
            }
            #if DEBUG
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("purr.debug")
                .accessibilityValue(Text(verbatim: probe))
                .allowsHitTesting(false)
            #endif
        }
        .animation(.spring(duration: 0.4, bounce: 0.2).paced, value: table?.screen)
        .animation(.spring(duration: 0.4, bounce: 0.15).paced, value: curtainSeat)
        .animation(.spring(duration: 0.35, bounce: 0.3).paced, value: connection)
        .frameGate()
        .tipHost(.purrtrait, paused: curtainSeat != nil || gotItOpen || menuOpen || table?.screen == .over,
                 person: tipPerson)
        .onChange(of: DrawTurn(table: table), initial: true) { _, turn in follow(turn) }
        .onChange(of: ClockKey(table: table), initial: true) { arrived = Date() }
        .onChange(of: store.connected) { _, on in if on { draw?.reconnected() } }
        .onChange(of: store.easelFull) { _, full in
            guard full != nil, let draw else { return }
            draw.easelFull()
            Sound.shared.play(ArtName.Sound.sfxNope)
            UIAccessibility.post(notification: .announcement, argument: PurrWords.easelFull)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { endStroke() }
        }
        .onChange(of: table?.screen == .over) { _, over in if over { model.tips.note(.gameOver) } }
        .onChange(of: store.rematch) { _, code in
            if let code, let go = playAgain.arrived(code: code) { model.openRematch(code: go, from: session.code) }
        }
        .onChange(of: session.lobbyNope) {
            if store.lastError == .gameOff { gameOff = true }
            if playAgain.waiting { playAgain.refused() }
        }
        .onDisappear {
            endStroke()
            store.ink.onChange = nil
        }
        .sheet(isPresented: $gotItOpen) {
            if let table {
                PurrGotItSheet(table: table, onPick: { seat in
                    gotItOpen = false
                    model.tips.used("purr.gotIt")
                    if let drawer = table.view.drawer { store.actPurrtrait(seat: drawer, .gotIt(seat)) }
                }, onClose: { gotItOpen = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.night)
            }
        }
        .sheet(isPresented: $menuOpen) {
            PurrMenuSheet(
                code: session.code, tableName: store.room?.title ?? TableName.fallback(code: session.code),
                host: store.room?.youAreHost == true,
                forfeit: model.ageBand == .kitten ? nil : forfeitSeat,
                onHome: {
                    menuOpen = false
                    model.goHome()
                },
                onForfeit: { seat in
                    menuOpen = false
                    if !store.actPurrtrait(seat: seat, .forfeit) { session.send(.actPurrtrait(seat: seat, action: .forfeit)) }
                },
                onClose: { menuOpen = false })
                .environment(settings)
                .environment(model)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-purrtrait")
    }

    // MARK: top bar

    private func topBar(_ table: PurrTableModel) -> some View {
        HStack(spacing: 10) {
            PurrPawButton { menuOpen = true }
            Spacer(minLength: 0)
            // The drawer's own screen has the word and the clock beside it; everyone else's here.
            if !table.isDrawingHere, table.view.phase == .choosing || table.view.phase == .drawing {
                if table.view.phase == .drawing, let group = table.view.group {
                    OutlinedText(PurrWords.group(group), size: 20, fill: .white, width: 3)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Palette.magenta).overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 3)))
                        .accessibilityIdentifier("purr.group")
                }
                clock
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    // MARK: content

    @ViewBuilder private func content(_ table: PurrTableModel) -> some View {
        switch table.screen {
        case .pick(let seat, let choices):
            VStack(spacing: 14) {
                if table.isShared, let person = table.room.seats[safe: seat]?.person {
                    NameTag(person.name, maxWidth: 240, size: 18)
                }
                PurrPickView(choices: choices) { level in
                    model.tips.used("purr.pick")
                    store.actPurrtrait(seat: seat, .choose(level))
                }
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .draw(_, let word):
            if let draw {
                PurrDrawView(
                    model: draw, word: word, clock: clock, revision: revision,
                    onTool: { change in redraw(change) },
                    onGotIt: {
                        endStroke()
                        gotItOpen = true
                    },
                    onGiveUp: {
                        endStroke()
                        if let drawer = table.view.drawer { store.actPurrtrait(seat: drawer, .giveUp) }
                    },
                    onStroke: { model.tips.used("purr.stroke") },
                    onMenu: {
                        endStroke()
                        menuOpen = true
                    })
                .transition(.opacity)
            }
        case .watch:
            PurrWatchView(table: table)
                .transition(.opacity)
        case .reveal(let last):
            PurrRevealView(table: table, last: last)
                .id(table.view.turn)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        case .over:
            Color.clear
        }
    }

    // MARK: the drawing turn

    /// The drawing turn on this device, if any: which seat, which turn.
    private struct DrawTurn: Equatable {
        var seat: Seat?
        var turn: String?

        init(table: PurrTableModel?) {
            if let table, case .draw(let seat, _) = table.screen {
                self.seat = seat
                turn = table.view.turn
            }
        }
    }

    private struct ClockKey: Equatable {
        var turn: String?
        var phase: PurrPhase?
        var remaining: Int?
        var paused: Bool?

        init(table: PurrTableModel?) {
            turn = table?.view.turn
            phase = table?.view.phase
            remaining = table?.view.remainingMs
            paused = table?.view.paused
        }
    }

    /// A drawing turn came, went, or changed: a model of its own, wired to the room.
    private func follow(_ turn: DrawTurn) {
        guard let seat = turn.seat, let key = turn.turn else {
            if draw != nil {
                draw?.background()
                draw = nil
                store.ink.onChange = nil
            }
            return
        }
        guard draw?.turn != key || draw?.seat != seat else { return }
        let store = store
        let next = PurrDrawModel(seat: seat, turn: key) { ops, failed in
            store.sendInk(seat: seat, turn: key, ops: ops, failed: failed)
        }
        draw = next
        revision = .init(serial: revision.serial + 1, change: .cleared)
        // The room's copy (after a relaunch), and its asks to send it all again (after it woke).
        store.ink.onChange = { [weak next] change in
            guard let next else { return }
            switch change {
            case .reset:
                if next.adopt(store.ink.compacted) { redraw(.cleared) }
            case .resend(let turn):
                guard turn == next.turn else { return }
                next.resend()
                redraw(.cleared)
            case .ops:
                break
            }
        }
        if !store.ink.ops.isEmpty, next.adopt(store.ink.compacted) { redraw(.cleared) }
    }

    private func redraw(_ change: InkDrawing.Change) {
        revision = .init(serial: revision.serial + 1, change: change)
    }

    /// The finger's stroke ends now (a sheet, the menu, the app leaving).
    private func endStroke() {
        guard let draw, draw.pen.isDrawing else { return }
        draw.background()
        redraw(.cleared)
    }

    // MARK: helpers

    private var tipPerson: String? {
        guard let table else { return nil }
        let seat: Seat? = switch table.screen {
        case .pick(let s, _), .draw(let s, _): s
        default: table.mySeats.first
        }
        return seat.flatMap { table.room.seats[safe: $0]?.person?.id }
    }

    private var forfeitSeat: Seat? {
        guard let table, table.view.isLive else { return nil }
        let mine = table.mySeats.filter { !table.view.isOut($0) }
        if let drawer = table.view.drawer, mine.contains(drawer) { return drawer }
        return mine.first
    }

    private var againState: PurrOverView.Again? {
        _ = againTick
        if gameOff { return .off }
        guard PlayAgain.available(store.room) else { return nil }
        if store.rematch != nil { return .go }
        return playAgain.isWaiting() ? .waiting : .ask
    }

    private func tapPlayAgain() {
        switch playAgain.tap(room: store.room, rematch: store.rematch) {
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

    #if DEBUG
    private var probe: String {
        guard let table else { return "phase=none" }
        let v = table.view
        let screen: String = switch table.screen {
        case .pick: "pick"
        case .draw: "draw"
        case .watch: "watch"
        case .reveal: "reveal"
        case .over: "over"
        }
        return "phase=\(v.phase.rawValue) screen=\(screen) turn=\(v.turn) drawer=\(v.drawer.map(String.init) ?? "-") "
            + "strokes=\(draw?.drawing.strokes.count ?? 0) scores=\(v.scores.map(String.init).joined(separator: ","))"
    }
    #endif
}

/// Purrtrait's paw menu: sound, haptics and home, How to play, Show on TV (the host's, to put the
/// table on a new TV), and Leave game (asks first).
struct PurrMenuSheet: View {
    @Environment(Settings.self) private var settings
    let code: String
    let tableName: String
    let host: Bool
    let forfeit: Seat?
    let onHome: () -> Void
    let onForfeit: (Seat) -> Void
    let onClose: () -> Void

    @State private var howTo = false
    @State private var tv = false
    @State private var confirming = false

    var body: some View {
        Group {
            if howTo {
                HowToPlaySheet(game: GameCatalog.purrtrait, exit: .back) { howTo = false }
            } else if tv {
                ShowOnTVSheet(code: code, onBack: { tv = false }, onClose: onClose)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                menu.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.25).paced, value: tv)
        .presentationDetents(howTo || tv ? [.large] : [.height(forfeit == nil ? 360 : 440)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.night)
    }

    private var menu: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Color.clear.frame(width: SheetBar.side, height: 1)
                Spacer(minLength: 0)
                OutlinedText(tableName, size: 26, fill: Palette.orange, lines: 2)
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
            if host {
                // One TV only: a new one takes the table over from the old (spec §5.1).
                PillButton(icon: ArtName.iconTV, color: Palette.magenta, size: .medium, width: 250,
                           title: String(localized: "New TV", comment: "Purrtrait menu (host): put this table on another TV"),
                           accessibilityLabel: "New TV") { tv = true }
                    .accessibilityIdentifier("menu.tv")
            }
            PillButton(icon: nil, color: Palette.orange, size: .medium, width: 250,
                       title: String(localized: "How to play", comment: "Table menu: open the rules"), accessibilityLabel: "How to play") { howTo = true }
                .accessibilityIdentifier("menu.rules")
            if let forfeit {
                PillButton(icon: nil, color: Palette.refuse, size: .medium, width: 250,
                           title: String(localized: "Leave game", comment: "Purrtrait menu: leave the game (asks first)"),
                           accessibilityLabel: "Leave game") { confirming = true }
                    .accessibilityIdentifier("menu.forfeit")
                    .alert(Text("Leave this game?", comment: "Purrtrait leave confirmation"), isPresented: $confirming) {
                        Button(String(localized: "Leave", comment: "Leave confirmation: the destructive button"), role: .destructive) {
                            onForfeit(forfeit)
                        }
                        .accessibilityIdentifier("forfeit.confirm")
                        Button(String(localized: "Keep playing", comment: "Forfeit confirmation: back to the game"), role: .cancel) {}
                    } message: {
                        Text("Your turns are skipped.", comment: "Purrtrait leave confirmation: what happens")
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-purr-menu")
    }
}
