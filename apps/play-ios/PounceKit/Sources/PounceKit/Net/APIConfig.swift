import Foundation

public struct APIConfig: Sendable {
    public let baseURL: URL

    public init(baseURL: URL) { self.baseURL = baseURL }

    /// `http` becomes `ws`, `https` becomes `wss`; the path is `/v1/rooms/<code>/ws`.
    public func socketURL(code: String) -> URL {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.scheme = parts.scheme?.lowercased() == "https" ? "wss" : "ws"
        parts.path = "/v1/rooms/\(code)/ws"
        parts.query = nil
        parts.fragment = nil
        return parts.url ?? baseURL
    }

    func endpoint(_ path: String) -> URL {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.path = path
        parts.query = nil
        parts.fragment = nil
        return parts.url ?? baseURL
    }
}
