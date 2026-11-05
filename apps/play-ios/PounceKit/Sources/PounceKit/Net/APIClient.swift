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

    public init(code: String, name: String? = nil, status: String, yourTurn: Bool, updatedAt: Double, next: String? = nil) {
        self.code = code
        self.name = name
        self.status = status
        self.yourTurn = yourTurn
        self.updatedAt = updatedAt
        self.next = next
    }
}

public enum APIError: Error, Equatable {
    case notConfigured, rateLimited, unauthorized, badRequest, notFound
    /// 403: not allowed for this person (a kitten signing in, §14.1).
    case forbidden
    /// 409 with the body's `error` (`already_linked`, `already_signed_in`, ...).
    case conflict(String)
    /// 409 `merge_needed`: the identity belongs to another player, shown as these two cats merging.
    case mergeNeeded(name: String, cat: Int)
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

    public init(config: APIConfig, credentials: CredentialStore, session: URLSession = .shared) {
        self.config = config
        self.credentials = credentials
        self.session = session
    }

    /// The device credential, minting one through `POST /v1/devices` if none is stored.
    public func credential() async throws -> DeviceCredential {
        if let cached { return cached }
        if let stored = credentials.load() {
            cached = stored
            return stored
        }
        return try await mint()
    }

    /// Called with each credential this client mints (the first one, or a re-mint after a 401
    /// that makes a new device on the server), after it is stored.
    public func setCredentialChangeHandler(_ handler: (@Sendable (DeviceCredential) -> Void)?) {
        onCredentialChange = handler
    }

    /// Uploads the APNs token; returns the device id the server stored it for.
    @discardableResult public func setPushToken(_ hex: String) async throws -> String {
        try await authenticatedCall("PUT", "/v1/devices/me/push", body: ["apnsToken": hex]).credential.deviceId
    }

    public func listTables() async throws -> [TableEntry] {
        struct Reply: Decodable { let tables: [TableEntry] }
        let data = try await authenticated("GET", "/v1/devices/me/tables", body: nil)
        return try decode(Reply.self, from: data, status: 200).tables
    }

    /// Creates a Cat Tower room and returns its code. Without a `name` (`TableName.clean`ed) the
    /// server picks one.
    public func createRoom(name: String? = nil) async throws -> String {
        struct Reply: Decodable { let code: String }
        var body = ["game": "cat-tower"]
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
        let task = Task { () throws -> DeviceCredential in
            let data = try await Self.send(session: session, method: "POST", url: url, bearer: nil, body: nil)
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

    func authenticated(
        _ method: String, _ path: String, body: (any Encodable & Sendable)?, query: [URLQueryItem] = []
    ) async throws -> Data {
        try await authenticatedCall(method, path, body: body, query: query).data
    }

    /// The reply and the credential that got it.
    private func authenticatedCall(
        _ method: String, _ path: String, body: (any Encodable & Sendable)?, query: [URLQueryItem] = []
    ) async throws -> (data: Data, credential: DeviceCredential) {
        let url = config.endpoint(path, query: query)
        let payload = try body.map { try JSONEncoder().encode($0) }
        var cred = try await credential()
        for attempt in 0..<2 {
            do {
                let data = try await Self.send(
                    session: session, method: method, url: url, bearer: cred.token, body: payload)
                return (data, cred)
            } catch APIError.unauthorized where attempt == 0 {
                cred = try await replacement(for: cred)
            }
        }
        throw APIError.unauthorized  // unreachable: attempt 1 rethrows above
    }

    private static func send(
        session: URLSession, method: String, url: URL, bearer: String?, body: Data?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
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
        case 404: throw APIError.notFound
        case 409: throw conflict(in: data)
        case 429: throw APIError.rateLimited
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
