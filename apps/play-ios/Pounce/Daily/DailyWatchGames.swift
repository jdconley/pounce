import PounceKit

/// The daily games the TV can watch. Each game adds its one line here. The TV target builds this
/// file and the listed watch views, never the play views.
enum DailyWatchGames {
    static let watch: [any DailyWatchView.Type] = [
        // SniffWatch.self,
        // NineLivesWatch.self,
        // CatNapWatch.self,
        // BoxFortWatch.self,
    ]

    static func view(for game: String) -> (any DailyWatchView.Type)? {
        watch.first { $0.game.id == game }
    }
}
