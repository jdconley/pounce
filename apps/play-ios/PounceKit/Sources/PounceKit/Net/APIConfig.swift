import Foundation

/// How a device joins a room's socket other than as a player: `screen` is a TV that shows the
/// table and holds no seat.
public enum RoomRole: String, Sendable {
    case screen
}

public struct APIConfig: Sendable {
    public let baseURL: URL
    /// Sent with every request and socket upgrade to this server: who is asking (`ClientHeaders`).
    public let headers: [String: String]

    public init(baseURL: URL, headers: [String: String] = ClientHeaders.standard) {
        self.baseURL = baseURL
        self.headers = headers
    }

    /// `host:port` (lowercased host, the scheme's default port when none is given): names this
    /// server for anything kept per server, so the dev server and production never share it.
    public var serverKey: String {
        let host = baseURL.host()?.lowercased() ?? ""
        let port = baseURL.port ?? (baseURL.scheme?.lowercased() == "https" ? 443 : 80)
        return "\(host):\(port)"
    }

    /// `http` becomes `ws`, `https` becomes `wss`; the path is `/v1/rooms/<code>/ws`, with
    /// `?role=screen` for a TV showing the table (docs/tv-protocol.md, "A screen").
    /// `near`: a Purrtrait TV's join key (from its QR) or its 8-character typed code.
    public func socketURL(code: String, role: RoomRole? = nil, near: String? = nil) -> URL {
        var query: [URLQueryItem] = []
        if let role { query.append(URLQueryItem(name: "role", value: role.rawValue)) }
        if let near { query.append(URLQueryItem(name: "near", value: near)) }
        return socket(path: "/v1/rooms/\(code)/ws", query: query)
    }

    /// The socket a TV waits on for a phone to link its code: `/v1/screens/<token>/ws`.
    public func screenSocketURL(token: String) -> URL {
        socket(path: "/v1/screens/\(token)/ws")
    }

    private func socket(path: String, query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.scheme = parts.scheme?.lowercased() == "https" ? "wss" : "ws"
        parts.path = path
        parts.queryItems = query.isEmpty ? nil : query
        parts.fragment = nil
        return parts.url ?? baseURL
    }

    /// The page or route at `path` on this server (for example the privacy page, `/privacy`).
    public func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.path = path
        parts.queryItems = query.isEmpty ? nil : query
        parts.fragment = nil
        return parts.url ?? baseURL
    }
}
