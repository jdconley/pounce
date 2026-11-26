import PounceKit
import SwiftUI

/// The TV's one screen: home, or the table it shows (lobby, table, game over) with the menu's paw
/// in the corner and the menu over it. The remote's Menu button leaves the app from home, as
/// tvOS users expect; at a table it opens the menu and goes back through it instead.
struct TVRoot: View {
    let model: TVModel
    @Environment(\.scenePhase) private var scenePhase
    /// The paw has the remote's focus whenever nothing else on the screen can take it, so Select
    /// and Menu always have somewhere to go after the screen changes under them.
    @FocusState private var pawFocused: Bool

    var body: some View {
        ZStack {
            backdrop
            screen
                .disabled(model.menu != .closed)
            // Always there at a table, even while it's being found: the menu can leave it. On the
            // board too, unless a run is being watched (its Board button goes back).
            if model.table != nil || (model.phase == .board && model.board?.state.watching == nil), model.menu == .closed {
                // At the table the scene draws the paw; over game over (which hides the table's)
                // and in the lobby, this does.
                TVMenuPaw(drawsIcon: model.phase != .table) { openMenu() }
                    .focused($pawFocused)
                    // On the board, top right, beside a card's title: the bottom corner holds rows.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.phase == .board ? .topTrailing : .bottomTrailing)
                    // Up into the top margin, so its focus ring clears the card's first row.
                    .offset(y: model.phase == .board ? -26 : 0)
            }
            if model.menu != .closed {
                // Scrim and panel fade as one layer.
                TVMenu(model: model)
                    .compositingGroup()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .animation(.easeOut(duration: 0.2), value: model.menu == .closed)
        .onExitCommand(perform: model.takesBack ? { model.back() } : nil)
        .task(id: FocusKey(phase: model.phase, menuClosed: model.menu == .closed, changeGame: model.canChangeGame, boardBusy: model.board?.state.offer != nil || model.board?.state.watching != nil)) {
            // Lobby with Change game: that button takes the focus. Everywhere else at a table the
            // paw is the one thing to focus; on the board too, unless a card or a run has it.
            guard model.table != nil || model.phase == .board, model.menu == .closed, !model.canChangeGame else { return }
            guard model.board?.state.offer == nil, model.board?.state.watching == nil else { return }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            pawFocused = true
        }
        // The TV stays on while a table is live on it (`KeepAwake`): its lobby and its game.
        .onChange(of: KeepAwake.tv(atTable: model.phase == .lobby || model.phase == .table, status: model.table?.store.room?.status),
                  initial: true) { _, on in
            IdleTimer.keepAwake(on, for: "tv")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: Task { await model.background() }
            case .active: Task { await model.active() }
            default: break
            }
        }
        .task {
            await model.start()
            #if DEBUG
            await TVShots.run(model)
            #endif
        }
    }

    private struct FocusKey: Equatable {
        let phase: TVModel.Phase
        let menuClosed: Bool
        let changeGame: Bool
        var boardBusy = false
    }

    private func openMenu() {
        Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
        model.openMenu()
    }

    @ViewBuilder private var backdrop: some View {
        switch model.phase {
        case .starting: Palette.violet.ignoresSafeArea()
        case .home: TVBackdrop(art: ArtName.homeBg)
        case .board, .lobby, .table, .over: TVBackdrop(art: ArtName.roomBg)
        }
    }

    @ViewBuilder private var screen: some View {
        switch model.phase {
        case .starting:
            Color.clear
        case .home:
            HomeView(model: model)
                .transition(.opacity)
        case .board:
            if let board = model.board {
                BoardView(model: model, board: board)
                    .transition(.opacity)
            }
        case .lobby:
            if let table = model.table {
                LobbyView(model: model, table: table, live: model.menu == .closed)
                    .overlay(alignment: .topLeading) {
                        if table.reconnecting { TVReconnecting() }
                    }
                    .id(table.code)
                    .transition(.opacity)
            }
        case .table, .over:
            if let table = model.table {
                let over = model.phase == .over
                ZStack {
                    // Behind game over the table recedes: softened out of focus, so the title and
                    // the places read alone over it (the scrim darkens it too).
                    TableHost(table: table)
                        .blur(radius: over ? 18 : 0, opaque: true)
                        .animation(.easeOut(duration: 0.4), value: over)
                        // The whole screen, not the safe area, or the blur stops at its edge.
                        .ignoresSafeArea()
                    if over, let room = table.store.room {
                        // Scrim, sunburst and panel fade as one layer.
                        GameOverView(room: room)
                            .overlay(alignment: .topLeading) {
                                if table.reconnecting { TVReconnecting() }
                            }
                            .compositingGroup()
                            .transition(.opacity)
                    }
                }
                .id(table.code)
            }
        }
    }
}

#if DEBUG
/// DEBUG launch arguments for screenshots and live checks, standing in for the remote:
/// `-tv-make <cat-tower|tiles>` presses that game's poster at home; `-tv-show-menu` opens the
/// menu once a table is up, and `-tv-show-menu link` its "Link another table" too.
@MainActor
enum TVShots {
    static func run(_ model: TVModel, arguments: [String] = CommandLine.arguments) async {
        if let i = arguments.firstIndex(of: "-tv-make"), let game = arguments[safe: i + 1], model.phase == .home {
            try? await Task.sleep(for: .seconds(1))
            await model.make(game: game)
        }
        guard let i = arguments.firstIndex(of: "-tv-show-menu") else { return }
        for _ in 0..<100 where model.table?.store.room == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(1.5))
        model.openMenu()
        if arguments[safe: i + 1] == "link" { model.showLink() }
    }
}
#endif
