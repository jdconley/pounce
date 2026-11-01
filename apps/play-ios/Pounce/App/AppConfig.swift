import Foundation
import PounceKit

struct AppConfig {
    /// Env var `POUNCE_API_BASE_URL` (Xcode scheme, simctl, XCUITest) wins over the Info.plist
    /// `PounceAPIBaseURL` (from the xcconfig build setting). If neither is a usable http(s) URL,
    /// fall back to the build flavor's default so the app never launches without a server.
    static func load(
        bundle: Bundle = .main, env: [String: String] = ProcessInfo.processInfo.environment
    ) -> APIConfig {
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
