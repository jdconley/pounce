import Foundation

/// A parsed share, move or pounce link.
public enum DeepLink: Equatable, Sendable {
    case join(code: String)
    case move(code: String, moveCode: String)
    /// A Messages pounce (§12.4): `https://play.conleychaos.com/p/<token>`.
    case pounce(token: String)

    private static let host = "play.conleychaos.com"
    private static let devScheme = "pounce-dev"

    /// The share link for a room: `https://play.conleychaos.com/j/<CODE>`.
    public static func shareURL(code: String) -> URL {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/j/\(code)"
        return parts.url!
    }

    /// The move link for one seat: `https://play.conleychaos.com/j/<CODE>?move=<MOVECODE>`.
    public static func moveURL(code: String, moveCode: String) -> URL {
        var parts = URLComponents(url: shareURL(code: code), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "move", value: moveCode)]
        return parts.url!
    }

    /// The link a Messages pounce sends: `https://play.conleychaos.com/p/<TOKEN>`.
    public static func pounceURL(token: String) -> URL {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/p/\(token)"
        return parts.url!
    }

    /// 16 random bytes, base64url (play-api `LINK_TOKEN`).
    public static func isPounceToken(_ s: String) -> Bool {
        s.utf8.count == 22 && s.unicodeScalars.allSatisfy { tokenScalars.contains($0) }
    }

    private static let tokenScalars = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    /// Accepts `https://play.conleychaos.com/p/<TOKEN>` (and `pounce-dev://p/<TOKEN>` in Debug),
    /// `https://play.conleychaos.com/j/<CODE>[?move=<M>]`, and
    /// `pounce-dev://j/<CODE>[?move=<M>]` only when `allowDevScheme` is true
    /// (Debug builds). A present but malformed `move` parameter rejects the
    /// whole link rather than silently downgrading it to a join.
    public static func parse(_ url: URL, allowDevScheme: Bool = false) -> DeepLink? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased()
        else { return nil }

        let kind: String
        let code: String
        switch scheme {
        case "https":
            guard parts.host?.lowercased() == host, parts.port == nil else { return nil }
            let path = parts.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard path.count == 3, path[0].isEmpty, path[1] == "j" || path[1] == "p" else { return nil }
            kind = path[1]
            code = path[2]
        case devScheme where allowDevScheme:
            guard let h = parts.host, h == "j" || h == "p" else { return nil }
            let path = parts.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard path.count == 2, path[0].isEmpty else { return nil }
            kind = h
            code = path[1]
        default:
            return nil
        }
        if kind == "p" {
            return isPounceToken(code) && (parts.queryItems ?? []).isEmpty ? .pounce(token: code) : nil
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

extension DeepLink {
    /// What "Paste invite" found in the pasteboard's text: the first share, move or pounce link
    /// in it (a whole invite message works, links in it may be wrapped in punctuation), or a room
    /// code on its own. The invite pages copy the bare link; Messages and notes add words around it.
    public static func pasted(_ text: String, allowDevScheme: Bool = false) -> DeepLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if RoomCode.isValid(trimmed.uppercased()) { return .join(code: trimmed.uppercased()) }
        let wrapping = CharacterSet(charactersIn: "<>()[]{}\"'\u{201C}\u{201D}\u{2018}\u{2019}.,;:!?")
        for word in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            let candidate = String(word).trimmingCharacters(in: wrapping)
            if let url = URL(string: candidate), let link = parse(url, allowDevScheme: allowDevScheme) { return link }
        }
        return nil
    }
}
