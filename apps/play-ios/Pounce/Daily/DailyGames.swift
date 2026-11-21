import PounceKit

/// The daily games this app can play. Each game adds its one line here, in any order (the Dish
/// sorts by `DailyCatalog`). A game listed here and by the server appears on Home and the Dish.
@MainActor
enum DailyGames {
    static let play: [any DailyGameView.Type] = {
        var games: [any DailyGameView.Type] = [
            // SniffDaily.self,
            // NineLivesDaily.self,
            // CatNapDaily.self,
            // BoxFortDaily.self,
        ]
        #if DEBUG
            if DailyTestGame.enabled { games.append(DailyTestGameView.self) }
        #endif
        return games
    }()
}
