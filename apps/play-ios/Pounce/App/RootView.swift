import SwiftUI

/// Switches on the route with a springy transition. Pick-cat, Home, Join and Room are
/// text-free placeholders until their real screens land.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            screen
                .id(routeKey)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .opacity))
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.3), value: model.route)
    }

    /// Re-creates the screen when the route's case changes (not for every associated value).
    private var routeKey: String {
        switch model.route {
        case .pickCat: "pickCat"
        case .home: "home"
        case .join: "join"
        case .room(let code, _): "room-\(code)"
        }
    }

    @ViewBuilder private var screen: some View {
        switch model.route {
        case .pickCat:
            PlaceholderScreen(color: Palette.violet, art: ArtName.gameTile, id: "screen-pickCat")
        case .home:
            PlaceholderScreen(color: Palette.magenta, art: ArtName.homeBg, id: "screen-home")
        case .join:
            PlaceholderScreen(color: Palette.teal, art: ArtName.iconKeypad, id: "screen-join")
        case .room:
            PlaceholderScreen(color: Palette.orange, art: ArtName.roomBg, id: "screen-room")
        }
    }
}

private struct PlaceholderScreen: View {
    let color: Color
    let art: String
    let id: String

    var body: some View {
        ZStack {
            color.ignoresSafeArea()
            Image(art)
                .resizable()
                .scaledToFit()
                .padding(32)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}
