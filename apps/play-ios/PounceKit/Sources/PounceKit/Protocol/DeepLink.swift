import Foundation

/// A parsed share or move link.
public enum DeepLink: Equatable, Sendable {
    case join(code: String)
    case move(code: String, moveCode: String)

    private static let host = "play.conleychaos.com"
    private static let devScheme = "pounce-dev"

    /// Accepts `https://play.conleychaos.com/j/<CODE>[?move=<M>]`, and
    /// `pounce-dev://j/<CODE>[?move=<M>]` only when `allowDevScheme` is true
    /// (Debug builds). A present but malformed `move` parameter rejects the
    /// whole link rather than silently downgrading it to a join.
    public static func parse(_ url: URL, allowDevScheme: Bool = false) -> DeepLink? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased()
        else { return nil }

        let code: String
        switch scheme {
        case "https":
            guard parts.host?.lowercased() == host, parts.port == nil else { return nil }
            let path = parts.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard path.count == 3, path[0].isEmpty, path[1] == "j" else { return nil }
            code = path[2]
        case devScheme where allowDevScheme:
            guard parts.host == "j" else { return nil }
            let path = parts.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard path.count == 2, path[0].isEmpty else { return nil }
            code = path[1]
        default:
            return nil
        }
        guard RoomCode.isValid(code) else { return nil }

        let moves = (parts.queryItems ?? []).filter { $0.name == "move" }
        switch moves.count {
        case 0: return .join(code: code)
        case 1:
            guard let value = moves[0].value, RoomCode.isValidMoveCode(value) else { return nil }
            return .move(code: code, moveCode: value)
        default: return nil
        }
    }
}
