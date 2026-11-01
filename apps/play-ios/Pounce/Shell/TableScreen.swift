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
            // Task 15 replaces this with the SpriteKit table.
            TablePlaceholder(session: session)
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

/// Text-free stand-in for the table until Task 15: the rug with every seated cat around it.
private struct TablePlaceholder: View {
    @Environment(AppModel.self) private var model
    let session: RoomSession

    var body: some View {
        ZStack {
            RoomBackground()
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.9
                let seats = session.store.room?.seats ?? []
                ZStack {
                    Image(ArtName.rug)
                        .resizable()
                        .frame(width: side, height: side * 0.8)
                        .accessibilityHidden(true)
                    ForEach(seats.indices, id: \.self) { i in
                        let angle = (-90.0 + Double(i) * 360.0 / Double(max(seats.count, 1))) * .pi / 180
                        let seat = seats[i]
                        Image(ArtName.cat(seat.kind == .bot ? 3 : seat.person?.cat ?? 0, .idle))
                            .resizable()
                            .scaledToFit()
                            .frame(width: side * 0.26, height: side * 0.26)
                            .overlay(alignment: .bottomTrailing) {
                                Image(seat.kind == .bot ? ArtName.badgeBot : seat.yours ? ArtName.badgePhone : ArtName.badgeRemote)
                                    .resizable().scaledToFit().frame(width: 28, height: 28)
                            }
                            .offset(x: cos(angle) * side * 0.36, y: sin(angle) * side * 0.3)
                            .accessibilityLabel(Text(verbatim: seat.person?.name ?? "House Cat"))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .overlay(alignment: .topLeading) {
            CornerHomeButton { model.goHome() }
                .padding(.leading, 16)
                .padding(.top, 4)
                .accessibilityIdentifier("table.home")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen-table")
    }
}
