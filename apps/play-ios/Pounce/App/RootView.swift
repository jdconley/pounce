import SwiftUI

/// Switches on the route with a springy transition, and tells the app model about scene phase
/// changes (the room socket drops in the background and reconnects on return).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            screen
                .id(routeKey)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .opacity))
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2).paced : .spring(duration: 0.45, bounce: 0.3).paced, value: model.route)
        .onChange(of: scenePhase) { _, phase in model.scenePhaseChanged(phase) }
        .onAppear { Pace.applyToWindows() }
    }

    /// Re-creates the screen when the route's case changes (not for every associated value).
    private var routeKey: String {
        switch model.route {
        case .age: "age"
        case .pickCat: "pickCat"
        case .home: "home"
        case .us: "us"
        case .join: "join"
        case .room(let code, _): "room-\(code)"
        }
    }

    @ViewBuilder private var screen: some View {
        switch model.route {
        case .age:
            AgeGateView()
        case .pickCat:
            PickCatView()
        case .home:
            HomeView()
        case .us:
            UsView()
        case .join:
            JoinView()
        case .room(let code, let intent):
            RoomContainer(code: code, intent: intent)
        }
    }
}
