import PounceKit
import SwiftUI

/// Toy Tumble's table for one session (spec §5.2 to §5.5): the SpriteKit scene, and over it only
/// what a moment needs: the round's standings between rounds (the winner on top with paw tokens,
/// "Waiting for Sam", the host's "Play without Sam"), game over, the connection pill and the menu.
/// The system's edge gestures are deferred while it shows, so drags at the edges move the toy.
struct TumbleStage: View {
    @Environment(AppModel.self) private var model
    @Environment(Settings.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let session: RoomSession
    let connection: RoomStore.Connection

    @State private var scene: TumbleScene?
    @State private var menuOpen = false
    @State private var tipSpots: [String: CGRect] = [:]
    @State private var playAgain = PlayAgain()
    @State private var againTick = 0
    @State private var now = Date()

    private var room: RoomView? { session.store.room }
    private var view: TumbleView? { room?.tumble }
    private var mySeat: Int? { room?.seats.indices.first { room?.seats[$0].yours == true } }
    private var over: Bool { view?.status == .over || room?.status == .over }

    #if DEBUG
    private var probe: String {
        guard let view else { return "status=none" }
        let local = session.tumble?.local
        return "status=\(view.status.rawValue) r=\(view.r) wins=\(view.wins.map(String.init).joined(separator: ",")) "
            + "next=\(local?.box.next ?? -1) held=\(local?.box.held.count ?? -1) out=\(local?.isOut == true ? 1 : 0) "
            + "rows=\(local?.box.rows ?? 0) outs=\(view.outs.map(String.init).joined(separator: ","))"
    }
    #endif

    var body: some View {
        ZStack {
            if let scene {
                TumbleTableView(scene: scene)
                    .ignoresSafeArea()
                    .overlay { TipSpots(spots: tipSpots).ignoresSafeArea() }
            } else {
                RoomBackground()
            }
            #if DEBUG
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("tumble.debug")
                .accessibilityValue(Text(verbatim: probe))
                .allowsHitTesting(false)
            #endif
            if let view, let room, view.status == .between, !over {
                TumbleBetween(view: view, room: room, mine: mySeat, now: now, offset: session.tumble?.clockOffset ?? 0) { seat in
                    session.send(.actTumble(seat: seat, action: .playWithout))
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .zIndex(TableLayer.scoreboard)
            }
            if connection != .good, !over, !menuOpen {
                VStack {
                    ConnectionPill(connection: connection)
                        .padding(.top, horizontalSizeClass == .regular ? 120 : 64)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(TableLayer.connection)
            }
            if over, let view, let room {
                TumbleOverView(view: view, room: room, mine: mySeat, again: againState, onPlayAgain: tapPlayAgain) { model.goHome() }
                    .transition(.opacity)
                    .zIndex(TableLayer.gameOver)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3).paced, value: view?.status)
        .animation(.spring(duration: 0.35, bounce: 0.3).paced, value: connection)
        .defersSystemGestures(on: .all)
        .persistentSystemOverlays(.hidden)
        .tipHost(.tumble, paused: menuOpen || over || view?.status != .playing)
        .onChange(of: over) { _, isOver in if isOver { model.tips.note(.gameOver) } }
        .task {
            await TumbleArt.shared.prewarm()
            guard !Task.isCancelled else { return }
            attach()
        }
        .task(id: view?.status == .between) {
            // The between card's waiting line counts up to Play without.
            while view?.status == .between, !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear { session.detachTable() }
        .onChange(of: session.store.rematch) { _, code in
            if let code, let go = playAgain.arrived(code: code) { model.openRematch(code: go, from: session.code) }
        }
        .onChange(of: model.tvSheet?.id) { _, id in if id != nil { menuOpen = false } }
        .sheet(isPresented: $menuOpen) {
            TumbleMenuSheet(
                code: session.code, tableName: room?.title ?? TableName.fallback(code: session.code),
                leaveSeat: model.ageBand == .kitten || over ? nil : mySeat,
                onHome: {
                    menuOpen = false
                    model.goHome()
                },
                onLeave: { seat in
                    menuOpen = false
                    session.send(.actTumble(seat: seat, action: .leave))
                    model.goHome()
                },
                onClose: { menuOpen = false })
                .environment(settings)
                .environment(model)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-tumble")
    }

    private var againState: BirdOverView.Again? {
        _ = againTick
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
        let table = session.tumbleTable()
        let scene = self.scene ?? TumbleScene(store: session.store, table: table)
        scene.onMenu = { menuOpen = true }
        scene.onTipSpots = { spots in if tipSpots != spots { tipSpots = spots } }
        scene.onTipUsed = { [weak model] control in model?.tips.used(control) }
        scene.onTipEvent = { [weak model] event in model?.tips.note(event) }
        self.scene = scene
    }
}

/// Between rounds (spec §5.5): the round's winner on top of its box with confetti, everyone's
/// paw tokens, then "Waiting for Sam" while a device is missing, and the host's Play without.
struct TumbleBetween: View {
    let view: TumbleView
    let room: RoomView
    let mine: Int?
    let now: Date
    /// The server's clock minus this device's (`TumbleTable.clockOffset`).
    var offset: Double = 0
    let onPlayWithout: (Int) -> Void

    /// Human seats still in the game whose device isn't here.
    private var missing: [Int] {
        room.seats.indices.filter { s in
            room.seats[s].kind == .human && !(view.left[safe: s] ?? false) && !(view.away[safe: s] ?? false)
                && room.seats[s].presence != .awake
        }
    }

    private var waitedLong: Bool {
        guard let since = view.waitingSince else { return false }
        return now.timeIntervalSince1970 * 1000 + offset - since >= 20_000
    }

    var body: some View {
        VStack(spacing: 14) {
            if let w = view.winner {
                Image(ArtName.cat(SeatInfo.catIndex(room.seats[safe: w]), .celebrate))
                    .resizable().scaledToFit().frame(width: 110, height: 110)
                    .accessibilityHidden(true)
                OutlinedText(w == mine ? TumbleWords.youWin : SeatInfo.name(room, w), size: 30, fill: Palette.orange, width: 4, lines: 2)
                    .accessibilityIdentifier("tumble.between.title")
            }
            VStack(spacing: 6) {
                ForEach(0..<view.seats, id: \.self) { s in
                    HStack(spacing: 8) {
                        Image(ArtName.cat(SeatInfo.catIndex(room.seats[safe: s]), .awake)).resizable().scaledToFit().frame(width: 34, height: 34)
                        OutlinedText(SeatInfo.name(room, s), size: 17, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 3) {
                            ForEach(0..<max(view.wins[safe: s] ?? 0, 0), id: \.self) { _ in
                                Image(ArtName.Habit.pawOne).resizable().scaledToFit().frame(width: 20, height: 20)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(SeatInfo.name(room, s)), \(view.wins[safe: s] ?? 0)"))
                }
            }
            .padding(12)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 20).fill(Palette.night).overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.ink, lineWidth: 4)))
            if view.waitingSince != nil, !missing.isEmpty {
                let names = missing.map { SeatInfo.name(room, $0) }
                OutlinedText(missing.count == 1 ? TumbleWords.waiting(for: names[0]) : TumbleWords.waiting(count: missing.count), size: 19, lines: 2)
                    .accessibilityIdentifier("tumble.waiting")
                if room.youAreHost, waitedLong, let host = mine {
                    PillButton(icon: nil, color: Palette.orange, size: .medium, width: 260,
                               title: missing.count == 1 ? TumbleWords.playWithout(names[0]) : TumbleWords.playWithout(names.formatted(.list(type: .and))),
                               accessibilityLabel: "Play without") { onPlayWithout(host) }
                        .accessibilityIdentifier("tumble.playWithout")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Palette.ink.opacity(0.55).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tumble.between")
    }
}

/// Game over: the seat with the most round wins, then Play again.
struct TumbleOverView: View {
    let view: TumbleView
    let room: RoomView
    let mine: Int?
    var again: BirdOverView.Again?
    let onPlayAgain: () -> Void
    let onHome: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var winner: Int? {
        guard let top = view.wins.max(), top > 0 else { return nil }
        return view.wins.firstIndex(of: top)
    }

    private var title: String {
        guard let winner else { return String(localized: "Game over", comment: "Toy Tumble game over: nobody won") }
        return String(localized: "\(SeatInfo.name(room, winner)) wins!", comment: "Game over title")
    }

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                if let winner {
                    Image(ArtName.cat(SeatInfo.catIndex(room.seats[safe: winner]), .celebrate))
                        .resizable().scaledToFit().frame(width: 130, height: 130)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                        .accessibilityHidden(true)
                }
                OutlinedText(title, size: 34, fill: Palette.orange, width: 5, lines: 2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("tumble.over.title")
                HStack(spacing: 14) {
                    if let again, again != .off {
                        PillButton(
                            icon: ArtName.iconPlay, color: again == .waiting ? Palette.violet : Palette.orange, size: .medium, width: 210,
                            title: again == .go
                                ? String(localized: "Join", comment: "Game over: someone dealt the next table; join it")
                                : String(localized: "Play again", comment: "Game over: deal a new table with the same players"),
                            accessibilityLabel: "Play again", action: onPlayAgain)
                            .accessibilityIdentifier("tumble.over.again")
                    }
                    PillButton(icon: ArtName.iconHome, color: Palette.sky, size: .medium, width: 84, accessibilityLabel: "Home", action: onHome)
                        .accessibilityIdentifier("tumble.over.home")
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
        .onAppear {
            Sound.shared.play(ArtName.Sound.sfxFanfare, kind: .game)
            Haptics.shared.celebrate()
            withAnimation(.spring(duration: 0.5, bounce: 0.45).paced) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-tumble-over")
    }
}

/// Toy Tumble's paw menu: sound, haptics and home in one row, then Show on TV, How to play, and
/// Leave (behind a confirmation: no House Cat takes the seat).
struct TumbleMenuSheet: View {
    @Environment(Settings.self) private var settings
    let code: String
    let tableName: String
    let leaveSeat: Int?
    let onHome: () -> Void
    let onLeave: (Int) -> Void
    let onClose: () -> Void

    @State private var howTo = false
    @State private var tv = false
    @State private var confirming = false

    var body: some View {
        Group {
            if howTo {
                HowToPlaySheet(game: GameCatalog.tumble, exit: .back) { howTo = false }
            } else if tv {
                ShowOnTVSheet(code: code, onBack: { tv = false }, onClose: onClose)
            } else {
                menu
            }
        }
        .presentationDetents(howTo || tv ? [.large] : [.height(leaveSeat == nil ? 420 : 500)])
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
            PillButton(icon: ArtName.iconTV, color: Palette.magenta, size: .medium, width: 250,
                       title: String(localized: "Show on TV", comment: "Table menu: put this table on a TV"), accessibilityLabel: "Show on TV") { tv = true }
                .accessibilityIdentifier("menu.tv")
            PillButton(icon: nil, color: Palette.orange, size: .medium, width: 250,
                       title: String(localized: "How to play", comment: "Table menu: open the rules"), accessibilityLabel: "How to play") { howTo = true }
                .accessibilityIdentifier("menu.rules")
            if let leaveSeat {
                PillButton(icon: nil, color: Palette.refuse, size: .medium, width: 250,
                           title: String(localized: "Leave game", comment: "Toy Tumble menu: leave for good (asks first)"),
                           accessibilityLabel: "Leave game") { confirming = true }
                    .accessibilityIdentifier("menu.forfeit")
                    .alert(String(localized: "Leave this game?", comment: "Toy Tumble leave confirmation title"), isPresented: $confirming) {
                        Button(String(localized: "Leave", comment: "Toy Tumble leave confirmation: the destructive button"), role: .destructive) {
                            onLeave(leaveSeat)
                        }
                        .accessibilityIdentifier("forfeit.confirm")
                        Button(String(localized: "Keep playing", comment: "Forfeit confirmation: back to the game"), role: .cancel) {}
                    } message: {
                        Text("Your wins stay on the board.", comment: "Toy Tumble leave confirmation: what happens")
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-tumble-menu")
    }
}
