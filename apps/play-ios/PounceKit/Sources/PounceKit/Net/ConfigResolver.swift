import Foundation

/// Picks the API base URL: the launch environment (`POUNCE_API_BASE_URL`) wins over the
/// Info.plist value (`PounceAPIBaseURL`, filled from the build setting). A candidate counts
/// only if it is an http(s) URL with a host; anything else (blank, garbage, an unsubstituted
/// `$(...)` build setting) is skipped.
public enum ConfigResolver {
    public static let envKey = "POUNCE_API_BASE_URL"
    public static let infoKey = "PounceAPIBaseURL"

    public static func baseURL(info: [String: Any], env: [String: String]) -> URL? {
        if let url = parse(env[envKey]) { return url }
        return parse(info[infoKey] as? String)
    }

    private static func parse(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
