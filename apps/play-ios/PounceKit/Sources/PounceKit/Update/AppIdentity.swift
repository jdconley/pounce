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
/// asking (`AppIdentity`). One place, so the API client and the room socket can't drift apart.
public enum ClientHeaders {
    public static let standard: [String: String] = headers(for: AppIdentity.current)

    public static func headers(for app: AppIdentity?) -> [String: String] {
        app.map { [AppIdentity.header: $0.headerValue] } ?? [:]
    }
}
