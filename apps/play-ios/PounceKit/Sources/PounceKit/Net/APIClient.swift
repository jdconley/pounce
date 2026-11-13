import Foundation

/// One row of `GET /v1/devices/me/tables`. `updatedAt` is epoch milliseconds.
public struct TableEntry: Codable, Equatable, Sendable {
    public let code: String
    /// The table's name; absent for tables the server last heard about before tables had names.
    public let name: String?
    public let status: String
    public let yourTurn: Bool
    public let updatedAt: Double
    /// Play again's table, on a finished table's entry (§10.4).
    public let next: String?
    /// Who sits where, for Home's names; nil from a server (or an entry) older than that, or
    /// when the field can't be read: the list itself never fails over it.
    public let seats: [TableSeat]?
    /// While a game is mid-round: when the current turn began (epoch ms), so Home can say how
    /// long the move has waited. Nil otherwise, and from an older server.
    public let movedAt: Double?
    /// The game's id (`GameCatalog`); the server sends it only for a game other than Cat Tower.
    public let game: String?

    public init(
        code: String, name: String? = nil, status: String, yourTurn: Bool, updatedAt: Double, next: String? = nil,
        seats: [TableSeat]? = nil, movedAt: Double? = nil, game: String? = nil
    ) {
        self.code = code
        self.name = name
        self.status = status
        self.yourTurn = yourTurn
        self.updatedAt = updatedAt
        self.next = next
        self.seats = seats
        self.movedAt = movedAt
        self.game = game
    }

    private enum CodingKeys: String, CodingKey { case code, name, status, yourTurn, updatedAt, next, seats, movedAt, game }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        status = try c.decode(String.self, forKey: .status)
        yourTurn = try c.decode(Bool.self, forKey: .yourTurn)
        updatedAt = try c.decode(Double.self, forKey: .updatedAt)
        next = try c.decodeIfPresent(String.self, forKey: .next)
        seats = (try? c.decodeIfPresent([TableSeat].self, forKey: .seats)) ?? nil
        movedAt = (try? c.decodeIfPresent(Double.self, forKey: .movedAt)) ?? nil
        game = (try? c.decodeIfPresent(String.self, forKey: .game)) ?? nil
    }
}

/// One seat on a tables-list entry: its kind, who sits there, and whether it is the list
/// owner's (this phone's seats on a device's list, the player's own on an account's).
public struct TableSeat: Codable, Equatable, Sendable {
    public var kind: SeatKind
    public var person: Person?
    public var yours: Bool

    public init(kind: SeatKind, person: Person? = nil, yours: Bool = false) {
        self.kind = kind
        self.person = person
        self.yours = yours
    }

    private enum CodingKeys: String, CodingKey { case kind, person, yours }

    /// A kind this app doesn't know reads as closed, and a person it can't read as nobody.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(String.self, forKey: .kind)).flatMap(SeatKind.init(rawValue:)) ?? .closed
        person = (try? c.decodeIfPresent(Person.self, forKey: .person)) ?? nil
        yours = (try? c.decodeIfPresent(Bool.self, forKey: .yours)) ?? false
    }
}

public enum APIError: Error, Equatable {
    case notConfigured, rateLimited, unauthorized, badRequest, notFound
    /// 404 `no_player`: a `/v1/me` route for a person this device hasn't bound to a player yet.
    case noPlayer
    /// 403: not allowed for this person (a kitten signing in, §14.1).
    case forbidden
    /// 409 with the body's `error` (`already_linked`, `already_signed_in`, ...).
    case conflict(String)
    /// 409 `merge_needed`: the identity belongs to another player, shown as these two cats merging.
    case mergeNeeded(name: String, cat: Int)
    /// 426 `update_required`: this version of the app is no longer supported (app updates design §4.3).
    case updateRequired(UpdateRequirement)
    case server(Int)
    case transport(String)
}

/// HTTP client for the `play-api` worker. It owns the device credential: it mints
/// one on first use, and an authenticated call that gets 401 clears it, mints a
/// fresh one once, and retries once. Concurrent calls that fail with the same stale
/// credential share one re-mint: a call whose credential was already replaced by
/// the time its 401 arrives retries with the replacement instead of minting again.
public actor APIClient {
    private let config: APIConfig
    private let credentials: CredentialStore
    private let session: URLSession
    private var cached: DeviceCredential?
    private var minting: Task<DeviceCredential, any Error>?
    private var onCredentialChange: (@Sendable (DeviceCredential) -> Void)?
    private var onUpdateRequired: (@Sendable (UpdateRequirement) -> Void)?
    private let mints: Bool
    private let timeout: TimeInterval

    /// `mints: false` is the widget extension's client (spec §11): it only ever uses the app's
    /// stored credential. With none stored it throws `.unauthorized`, and a 401 throws without
    /// clearing the credential or minting a new device, so the app's device identity is never
    /// replaced from a widget. `timeout` bounds each request (the widget's fetch uses 5 s).
    public init(
        config: APIConfig, credentials: CredentialStore, session: URLSession = .shared, mints: Bool = true,
        timeout: TimeInterval = 15
    ) {
        self.config = config
        self.credentials = credentials
        self.session = session
        self.mints = mints
        self.timeout = timeout
    }

    /// The device credential, minting one through `POST /v1/devices` if none is stored.
    public func credential() async throws -> DeviceCredential {
        if let cached { return cached }
        if let stored = credentials.load() {
            cached = stored
            return stored
        }
        guard mints else { throw APIError.unauthorized }
        return try await mint()
    }

    /// Called with each credential this client mints (the first one, or a re-mint after a 401
    /// that makes a new device on the server), after it is stored.
    public func setCredentialChangeHandler(_ handler: (@Sendable (DeviceCredential) -> Void)?) {
        onCredentialChange = handler
    }

    /// Called whenever the server answers any call with "this version is no longer supported".
    public func setUpdateRequiredHandler(_ handler: (@Sendable (UpdateRequirement) -> Void)?) {
        onUpdateRequired = handler
    }

    /// A call that needs no device credential (`GET /v1/app`).
    func open(_ method: String, _ path: String) async throws -> Data {
        try await Self.send(
            session: session, method: method, url: config.endpoint(path), headers: config.headers, bearer: nil, body: nil,
            timeout: timeout)
    }

    /// Uploads the APNs token; returns the device id the server stored it for.
    @discardableResult public func setPushToken(_ hex: String) async throws -> String {
        try await authenticatedCall("PUT", "/v1/devices/me/push", body: ["apnsToken": hex]).credential.deviceId
    }

    /// Uploads the widget extension's WidgetKit push token (spec §11.2); returns the device id the
    /// server stored it for. Never called on a kitten's device (`WidgetPushToken`).
    @discardableResult public func setWidgetPushToken(_ hex: String) async throws -> String {
        try await authenticatedCall("PUT", "/v1/devices/me/widget-push", body: ["token": hex]).credential.deviceId
    }

    /// The live table's push-to-start token (spec §11.3, §13.4). Returns the device it went up for.
    @discardableResult public func setLivePushToStart(_ hex: String) async throws -> String {
        try await authenticatedCall("PUT", "/v1/devices/me/live-activity", body: ["pushToStart": hex]).credential.deviceId
    }

    /// One live table's update token; nil tells the server it ended on this device (swiped away),
    /// so "your move" stops being held back for it.
    public func setLiveActivityToken(code: String, token: String?) async throws {
        _ = try await authenticated("PUT", "/v1/devices/me/live-activity", body: LiveActivityBody(code: code, token: token))
    }

    public func listTables() async throws -> [TableEntry] {
        struct Reply: Decodable { let tables: [TableEntry] }
        let data = try await authenticated("GET", "/v1/devices/me/tables", body: nil)
        return try decode(Reply.self, from: data, status: 200).tables
    }

    /// Creates a room for `game` (a `GameCatalog` id; Cat Tower unless told otherwise, the one game
    /// the server deals today) and returns its code. Without a `name` (`TableName.clean`ed) the
    /// server picks one.
    public func createRoom(name: String? = nil, game: String = GameCatalog.dealt.id) async throws -> String {
        struct Reply: Decodable { let code: String }
        var body = ["game": game]
        if let name { body["name"] = name }
        let data = try await authenticated("POST", "/v1/rooms", body: body)
        return try decode(Reply.self, from: data, status: 201).code
    }

    // MARK: minting

    private func mint() async throws -> DeviceCredential {
        // The actor is re-entrant across awaits, so concurrent first calls share one request.
        if let minting { return try await minting.value }
        let session = session
        let url = config.endpoint("/v1/devices")
        let timeout = timeout
        let headers = config.headers
        let task = Task { () throws -> DeviceCredential in
            let data = try await Self.send(
                session: session, method: "POST", url: url, headers: headers, bearer: nil, body: nil, timeout: timeout)
            return try Self.decode(DeviceCredential.self, from: data, status: 200)
        }
        minting = task
        defer { minting = nil }
        let minted = try await task.value
        credentials.save(minted)
        cached = minted
        onCredentialChange?(minted)
        return minted
    }

    /// A credential to retry with after `failed` got 401: one minted since (by a
    /// concurrent call) if there is one, otherwise a fresh mint (shared with any
    /// mint already running).
    private func replacement(for failed: DeviceCredential) async throws -> DeviceCredential {
        if let cached, cached != failed { return cached }
        if cached == failed {
            credentials.clear()
            cached = nil
        }
        return try await mint()
    }

    // MARK: requests

    /// `noPlayer`: a 404 `no_player` throws `.noPlayer` instead of `.notFound` (the streak list,
    /// where a plain 404 means the server has streaks off).
    func authenticated(
        _ method: String, _ path: String, body: (any Encodable & Sendable)?, query: [URLQueryItem] = [],
        noPlayer: Bool = false
    ) async throws -> Data {
        try await authenticatedCall(method, path, body: body, query: query, noPlayer: noPlayer).data
    }

    /// The reply and the credential that got it. A call the server refuses because this version
    /// is too old tells the update handler before it throws.
    private func authenticatedCall(
        _ method: String, _ path: String, body: (any Encodable & Sendable)?, query: [URLQueryItem] = [],
        noPlayer: Bool = false
    ) async throws -> (data: Data, credential: DeviceCredential) {
        do {
            return try await attempt(method, path, body: body, query: query, noPlayer: noPlayer)
        } catch APIError.updateRequired(let need) {
            onUpdateRequired?(need)
            throw APIError.updateRequired(need)
        }
    }

    private func attempt(
        _ method: String, _ path: String, body: (any Encodable & Sendable)?, query: [URLQueryItem], noPlayer: Bool
    ) async throws -> (data: Data, credential: DeviceCredential) {
        let url = config.endpoint(path, query: query)
        let payload = try body.map { try JSONEncoder().encode($0) }
        var cred = try await credential()
        for attempt in 0..<2 {
            do {
                let data = try await Self.send(
                    session: session, method: method, url: url, headers: config.headers, bearer: cred.token, body: payload,
                    noPlayer: noPlayer, timeout: timeout)
                return (data, cred)
            } catch APIError.unauthorized where attempt == 0 && mints {
                cred = try await replacement(for: cred)
            }
        }
        throw APIError.unauthorized  // unreachable: attempt 1 rethrows above
    }

    private static func send(
        session: URLSession, method: String, url: URL, headers: [String: String], bearer: String?, body: Data?,
        noPlayer: Bool = false, timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport((error as? URLError)?.localizedDescription ?? String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("not an HTTP response") }
        switch http.statusCode {
        case 200..<300: return data
        case 400: throw APIError.badRequest
        case 401: throw APIError.unauthorized
        case 403: throw APIError.forbidden
        case 404 where noPlayer && errorCode(in: data) == "no_player": throw APIError.noPlayer
        case 404: throw APIError.notFound
        case 409: throw conflict(in: data)
        case 429: throw APIError.rateLimited
        case UpdateRefusal.status:
            // Too old for the server; any other 426 is the plain server error it always was.
            if case .required(let need)? = UpdateRefusal.read(status: http.statusCode, headers: http.allHeaderFields, body: data) {
                throw APIError.updateRequired(need)
            }
            throw APIError.server(http.statusCode)
        case 503 where errorCode(in: data) == "not_configured": throw APIError.notConfigured
        default: throw APIError.server(http.statusCode)
        }
    }

    private static func conflict(in data: Data) -> APIError {
        struct Body: Decodable {
            struct Other: Decodable { let name: String; let cat: Int }
            let error: String?
            let otherPlayer: Other?
        }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        if body?.error == "merge_needed", let other = body?.otherPlayer {
            return .mergeNeeded(name: other.name, cat: other.cat)
        }
        return .conflict(body?.error ?? "")
    }

    private static func errorCode(in data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data, status: Int) throws -> T {
        try Self.decode(type, from: data, status: status)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, status: Int) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw APIError.server(status) }
    }
}

/// `{"activities": [{"code": ..., "token": ... | null}]}`: an explicit null, which clears it.
struct LiveActivityBody: Encodable, Sendable {
    struct Entry: Encodable, Sendable {
        let code: String
        let token: String?

        private enum CodingKeys: String, CodingKey { case code, token }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(code, forKey: .code)
            try c.encode(token, forKey: .token)
        }
    }

    let activities: [Entry]

    init(code: String, token: String?) {
        activities = [Entry(code: code, token: token)]
    }
}
