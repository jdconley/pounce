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
    }

    private var screen: Screen {
        switch store.phase {
        case .connecting:
            return session.offline ? .state(.offline) : .connecting
        case .lobby:
            return .lobby
        case .playing, .over:
            // No spectating in M1: a game this phone isn't in is "full".
            return (session.model?.mySeats.isEmpty ?? true) ? .state(.full) : .table
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
/// pass-and-play: every room change updates `PassAndPlay` and reconciles the scene with its
/// `revealed` seat. Over it: the scoreboard (tap the tower) and, once the scene has played the
/// win, the game-over overlay. Task 19 adds the curtain overlay on top.
private struct TableStage: View {
    @Environment(AppModel.self) private var model
    let session: RoomSession
    @State private var scene: TableScene?
    @State private var pass = PassAndPlay()
    @State private var scoreboard = false
    /// Set by the scene when the game-over celebration is done.
    @State private var winners: [Seat]?

    var body: some View {
        ZStack {
            if let scene {
                TableView(scene: scene)
                    .ignoresSafeArea()
            } else {
                RoomBackground()
            }
            if scoreboard, winners == nil, let room = session.store.room, room.game != nil {
                ScoreboardOverlay(model: TableModel(room: room)) { scoreboard = false }
                    .transition(.opacity)
            }
            if let winners {
                GameOverView(
                    winners: people(winners),
                    onHome: { model.goHome() },
                    onNewGame: { Task { await model.newGame() } })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: scoreboard)
        .animation(.easeOut(duration: 0.3), value: winners)
        .onAppear(perform: attach)
        .onDisappear { session.detachTable() }
        .onChange(of: session.store.room, initial: true) { sync() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-table")
    }

    private func attach() {
        let scene = self.scene ?? TableScene(store: session.store)
        // Task 20 replaces this with the table menu sheet; until then the paw goes home.
        scene.onMenu = { [weak model] in model?.goHome() }
        scene.onTower = { scoreboard = true }
        scene.onGameOver = { seats in winners = seats }
        self.scene = scene
        sync(scene)
        session.attachTable { [weak scene] intent in
            await scene?.play(intent)
        }
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
        pass.update(table)
        scene.reconcile(table, revealed: pass.revealed)
    }
}
