import PounceKit
import SwiftUI

/// Pounce on the Apple TV: a TV is no one's seat. It shows a link a phone scans to put its table
/// here, or makes a table from one of the two game posters, and then shows that table for the
/// whole room: the lobby, the game and game over (`TVModel`, `TVRoot`).
@main
struct PounceTVApp: App {
    @State private var model: TVModel? = Self.makeModel()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let preview = TVTablePreview.from(), preview.game == .purrtrait {
                TVDemoTableView(game: .purrtrait, seats: preview.seats, still: true)
            } else if let preview = TVTablePreview.from() {
                TVTablePreviewView(game: preview.game, seats: preview.seats, aim: preview.aim)
            } else if case .table(let game, let seats) = TVDemo.from() {
                TVDemoTableView(game: game, seats: seats)
            } else if let model {
                TVRoot(model: model)
            }
            #else
            if let model { TVRoot(model: model) }
            #endif
        }
    }

    /// The TV against the server this build points at, as its own device.
    private static func makeModel() -> TVModel? {
        #if DEBUG
        // Hosting the unit tests: no server, no Keychain, nothing on screen.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return nil }
        // Before the window shows, so its probe (the UI tests' `watchdog` element) goes on it.
        MainThreadWatchdog.startIfAsked()
        if TVTablePreview.from() != nil { return nil }
        let demo = TVDemo.from()
        if case .table = demo { return nil }
        if demo == .shell { return TVModel(services: .demo()) }
        if case .over(let seats) = demo { return TVModel(services: .demoOver(seats: seats)) }
        if demo == .board { return TVModel(services: .demoBoard()) }
        #endif
        return TVModel(services: .live(config: TVConfig.load()))
    }
}

/// The server: `POUNCE_API_BASE_URL` in the environment wins over the Info.plist's
/// `PounceAPIBaseURL` (from the build's xcconfig), as on the iPhone (`AppConfig`).
enum TVConfig {
    static func load(bundle: Bundle = .main, env: [String: String] = ProcessInfo.processInfo.environment) -> APIConfig {
        if let url = ConfigResolver.baseURL(info: bundle.infoDictionary ?? [:], env: env) {
            return APIConfig(baseURL: url)
        }
        return APIConfig(baseURL: fallbackURL)
    }

    #if DEBUG
    private static let fallbackURL = URL(string: "http://localhost:8787")!
    #else
    private static let fallbackURL = URL(string: "https://play.conleychaos.com")!
    #endif
}
