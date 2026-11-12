import Foundation

/// `GET /v1/app` (app updates design §3): what is current. Every key is absent when the server
/// doesn't know it, and a key this build can't read is absent too: the whole answer never fails
/// over one field.
public struct AppStatus: Codable, Equatable, Sendable {
    /// The version live on the App Store.
    public var latest: String?
    /// The oldest version the server still supports.
    public var minimum: String?
    public var storeUrl: String?
    public var testflightUrl: String?

    public init(latest: String? = nil, minimum: String? = nil, storeUrl: String? = nil, testflightUrl: String? = nil) {
        self.latest = latest
        self.minimum = minimum
        self.storeUrl = storeUrl
        self.testflightUrl = testflightUrl
    }

    private enum CodingKeys: String, CodingKey { case latest, minimum, storeUrl, testflightUrl }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        latest = text(.latest)
        minimum = text(.minimum)
        storeUrl = text(.storeUrl)
        testflightUrl = text(.testflightUrl)
    }
}

/// What a 426 `update_required` says: the version needed, and where to get it.
public struct UpdateRequirement: Codable, Equatable, Sendable {
    public var minimum: String?
    public var storeUrl: String?
    public var testflightUrl: String?

    public init(minimum: String? = nil, storeUrl: String? = nil, testflightUrl: String? = nil) {
        self.minimum = minimum
        self.storeUrl = storeUrl
        self.testflightUrl = testflightUrl
    }
}

/// The server turned this app away and said why (design §4.2, §4.3). Read from the status and
/// headers alone when it has to be: a refused socket upgrade's body never reaches the app.
public enum UpdateRefusal: Equatable, Sendable {
    /// This version of the app is no longer supported.
    case required(UpdateRequirement)
    /// The table is playing a game this version can't draw. `title` is the game's name as the
    /// server says it, for a game this build has never heard of.
    case game(id: String, title: String?)

    public static let status = 426
    static let header = "x-pounce-update"
    static let gameHeader = "x-pounce-game"
    static let gameTitleHeader = "x-pounce-game-title"

    private struct Body: Decodable {
        var error: String?
        var minimum: String?
        var storeUrl: String?
        var testflightUrl: String?
        var game: String?
        var title: String?
    }

    /// The refusal in an answer, or nil when it isn't one: any status but 426, or a 426 that
    /// says neither (the server's older "this route wants a WebSocket", `upgrade_required`).
    /// The header says which; without it, the body's `error` does.
    public static func read(status: Int, headers: [AnyHashable: Any], body: Data?) -> UpdateRefusal? {
        guard status == Self.status else { return nil }
        var lowered: [String: String] = [:]
        for (key, value) in headers {
            if let key = key as? String, let value = value as? String { lowered[key.lowercased()] = value }
        }
        let parsed = body.flatMap { try? JSONDecoder().decode(Body.self, from: $0) }
        let kind = lowered[header]?.trimmingCharacters(in: .whitespaces).lowercased()
        if kind == "required" || (kind == nil && parsed?.error == "update_required") {
            return .required(
                UpdateRequirement(minimum: parsed?.minimum, storeUrl: parsed?.storeUrl, testflightUrl: parsed?.testflightUrl))
        }
        if kind == "game" || (kind == nil && parsed?.error == "game_unsupported") {
            guard let id = clean(lowered[gameHeader]) ?? clean(parsed?.game) else { return nil }
            let title = clean(lowered[gameTitleHeader]?.removingPercentEncoding) ?? clean(parsed?.title)
            return .game(id: id, title: title)
        }
        return nil
    }

    /// A game id or name worth showing: trimmed, not empty, not absurdly long, no control characters.
    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty, trimmed.count <= 40,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return trimmed
    }
}

/// One table in the tables list's `locked`: a table this app was left out of because it can't
/// draw the game. There to say "update to join", never to open.
public struct LockedTable: Codable, Equatable, Sendable {
    public var code: String
    public var name: String?
    public var game: String
    public var title: String?
    public var updatedAt: Double
    public var seats: [TableSeat]?

    public init(code: String, name: String? = nil, game: String, title: String? = nil, updatedAt: Double, seats: [TableSeat]? = nil) {
        self.code = code
        self.name = name
        self.game = game
        self.title = title
        self.updatedAt = updatedAt
        self.seats = seats
    }

    private enum CodingKeys: String, CodingKey { case code, name, game, title, updatedAt, seats }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        game = try c.decode(String.self, forKey: .game)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil
        updatedAt = ((try? c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? nil) ?? 0
        seats = (try? c.decodeIfPresent([TableSeat].self, forKey: .seats)) ?? nil
    }
}

/// `GET /v1/devices/me/tables` as an app that says what it is reads it: the tables, and the ones
/// locked behind an update. `locked` that is missing, or holds anything unreadable, is empty: the
/// tables never fail over it.
public struct TablesReply: Decodable, Equatable, Sendable {
    public var tables: [TableEntry]
    public var locked: [LockedTable]

    public init(tables: [TableEntry], locked: [LockedTable] = []) {
        self.tables = tables
        self.locked = locked
    }

    private enum CodingKeys: String, CodingKey { case tables, locked }

    /// One element of `locked`, kept or dropped on its own.
    private struct Loose: Decodable {
        let table: LockedTable?
        init(from decoder: any Decoder) throws { table = try? LockedTable(from: decoder) }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tables = try c.decode([TableEntry].self, forKey: .tables)
        locked = (((try? c.decodeIfPresent([Loose].self, forKey: .locked)) ?? nil) ?? []).compactMap(\.table)
    }
}
