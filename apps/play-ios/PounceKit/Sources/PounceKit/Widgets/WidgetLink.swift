import Foundation

/// Where a widget tap goes (spec §11.1). `pounce-widget://` isn't a registered URL scheme:
/// WidgetKit hands these straight to the containing app, so nothing else can open them.
public enum WidgetLink: Equatable, Sendable {
    /// Rejoin this table.
    case table(String)
    /// The Us screen, on this pair (or the top one).
    case us(pair: String?)
    /// Just the app.
    case app

    public static let scheme = "pounce-widget"

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .table(let code):
            parts.host = "table"
            parts.path = "/\(code)"
        case .us(let pair):
            parts.host = "us"
            if let pair { parts.queryItems = [URLQueryItem(name: "pair", value: pair)] }
        case .app:
            parts.host = "app"
        }
        return parts.url ?? URL(string: "\(Self.scheme)://app")!
    }

    public static func parse(_ url: URL) -> WidgetLink? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == scheme else { return nil }
        switch parts.host {
        case "table":
            let code = String(parts.path.dropFirst())
            return parts.path.hasPrefix("/") && RoomCode.isValid(code) ? .table(code) : nil
        case "us":
            let pair = parts.queryItems?.first { $0.name == "pair" }?.value
            return .us(pair: pair.flatMap { $0.isEmpty ? nil : $0 })
        case "app":
            return .app
        default:
            return nil
        }
    }
}
