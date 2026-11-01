import Foundation

public struct APIConfig: Sendable {
    public let baseURL: URL

    public init(baseURL: URL) { self.baseURL = baseURL }

    /// `host:port` (lowercased host, the scheme's default port when none is given): names this
    /// server for anything kept per server, so the dev server and production never share it.
    public var serverKey: String {
        let host = baseURL.host()?.lowercased() ?? ""
        let port = baseURL.port ?? (baseURL.scheme?.lowercased() == "https" ? 443 : 80)
        return "\(host):\(port)"
    }

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
