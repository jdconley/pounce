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
            // Always there at a table, even while it's being found: the menu can leave it.
            if model.table != nil, model.menu == .closed {
                // At the table the scene draws the paw; over game over (which hides the table's)
                // and in the lobby, this does.
                TVMenuPaw(drawsIcon: model.phase != .table) { openMenu() }
                    .focused($pawFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            if model.menu != .closed {
                TVMenu(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .animation(.easeOut(duration: 0.2), value: model.menu == .closed)
        .onExitCommand(perform: model.table == nil ? nil : { model.back() })
        .task(id: FocusKey(phase: model.phase, menuClosed: model.menu == .closed, changeGame: model.canChangeGame)) {
            // Lobby with Change game: that button takes the focus. Everywhere else at a table the
            // paw is the one thing to focus.
            guard model.table != nil, model.menu == .closed, !model.canChangeGame else { return }
            try? await Task.sleep(for: .milliseconds(80))
            pawFocused = true
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
    }

    private func openMenu() {
        Sound.shared.play(ArtName.Sound.sfxPop, volume: 0.5)
        model.openMenu()
    }

    @ViewBuilder private var backdrop: some View {
        switch model.phase {
        case .starting: Palette.violet.ignoresSafeArea()
        case .home: TVBackdrop(art: ArtName.homeBg)
        case .lobby, .table, .over: TVBackdrop(art: ArtName.roomBg)
        }
    }

    @ViewBuilder private var screen: some View {
        switch model.phase {
        case .starting:
            Color.clear
        case .home:
            HomeView(model: model)
                .transition(.opacity)
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
                ZStack {
                    TableHost(table: table)
                    if model.phase == .over, let room = table.store.room {
                        GameOverView(room: room)
                            .overlay(alignment: .topLeading) {
                                if table.reconnecting { TVReconnecting() }
                            }
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
