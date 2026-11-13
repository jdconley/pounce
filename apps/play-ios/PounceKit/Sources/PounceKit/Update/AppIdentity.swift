import Foundation

/// What the app says it is on every request and socket upgrade, from version 1.1 on (app updates
/// design §2): `X-Pounce-App: platform=ios; version=1.1; build=57; protocol=1`.
///
/// Version 1.0 sends no such header, and the server answers a request without one exactly as it
/// always did. With it, the server can say more: which game a table needs (instead of "no such
/// table"), which tables are waiting behind an update, and that this version is no longer supported.
public struct AppIdentity: Equatable, Sendable {
    public static let header = "X-Pounce-App"

    public var platform: String
    /// `CFBundleShortVersionString`, cleaned ("1.1").
    public var version: String
    /// `CFBundleVersion`, when it is a number.
    public var build: String?
    /// The socket protocol this build speaks.
    public var protocolVersion: Int

    public init(platform: String, version: String, build: String? = nil, protocolVersion: Int = PounceKit.protocolVersion) {
        self.platform = platform
        self.version = version
        self.build = build
        self.protocolVersion = protocolVersion
    }

    /// From a bundle's Info.plist: nil when it names no readable version (a command-line tool, a
    /// test runner), and then no header is sent at all.
    public init?(platform: String, info: [String: Any]?) {
        guard let version = AppVersion(info?["CFBundleShortVersionString"] as? String) else { return nil }
        let build = (info?["CFBundleVersion"] as? String).flatMap { text in
            !text.isEmpty && text.count <= 9 && text.allSatisfy { $0.isASCII && $0.isNumber } ? text : nil
        }
        self.init(platform: platform, version: version.description, build: build)
    }

    public var headerValue: String {
        var fields = ["platform=\(platform)", "version=\(version)"]
        if let build { fields.append("build=\(build)") }
        fields.append("protocol=\(protocolVersion)")
        return fields.joined(separator: "; ")
    }

    /// The running app or extension (they share a version). Nil off iOS: the `pounce-e2e` tool and
    /// the package's tests say nothing, as version 1.0 does.
    public static let current: AppIdentity? = {
        #if os(iOS)
        AppIdentity(platform: "ios", info: Bundle.main.infoDictionary)
        #else
        nil
        #endif
    }()
}

/// The headers every request to play-api carries, from the app and from its extensions: who is
/// asking (`AppIdentity`) and the games it can draw (`X-Pounce-Games`). One place, so the API
/// client, the room socket and the widgets can't drift apart: the server takes a request without
/// the games header to mean "Cat Tower only" and stops showing that device its other tables.
public enum ClientHeaders {
    /// The games this build can draw, as the server reads them (tile game design §9.3).
    public static let gamesHeader = "X-Pounce-Games"

    public static let standard: [String: String] = headers(for: AppIdentity.current)

    /// Every game in the catalog, whether or not it is on the shelf yet: this build can draw them all.
    public static var drawable: String { GameCatalog.all.map(\.id).joined(separator: ",") }

    public static func headers(for app: AppIdentity?) -> [String: String] {
        app.map { [AppIdentity.header: $0.headerValue, gamesHeader: drawable] } ?? [:]
    }
}
