import Foundation

/// One row of `GET /v1/devices/me/tables`. `updatedAt` is epoch milliseconds.
public struct TableEntry: Codable, Equatable, Sendable {
    public let code: String
    public let status: String
    public let yourTurn: Bool
    public let updatedAt: Double

    public init(code: String, status: String, yourTurn: Bool, updatedAt: Double) {
        self.code = code
        self.status = status
        self.yourTurn = yourTurn
        self.updatedAt = updatedAt
    }
}

public enum APIError: Error, Equatable {
    case notConfigured, rateLimited, unauthorized, badRequest, notFound
    case server(Int)
    case transport(String)
}

/// HTTP client for the `play-api` worker. It owns the device credential: it mints
/// one on first use, and an authenticated call that gets 401 clears it, mints a
/// fresh one once, and retries once.
public actor APIClient {
    private let config: APIConfig
    private let credentials: CredentialStore
    private let session: URLSession
    private var cached: DeviceCredential?
    private var minting: Task<DeviceCredential, any Error>?

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

    public func setPushToken(_ hex: String) async throws {
        _ = try await authenticated("PUT", "/v1/devices/me/push", body: ["apnsToken": hex])
    }

    public func listTables() async throws -> [TableEntry] {
        struct Reply: Decodable { let tables: [TableEntry] }
        let data = try await authenticated("GET", "/v1/devices/me/tables", body: nil)
        return try decode(Reply.self, from: data, status: 200).tables
    }

    /// Creates a Cat Tower room and returns its code.
    public func createRoom() async throws -> String {
        struct Reply: Decodable { let code: String }
        let data = try await authenticated("POST", "/v1/rooms", body: ["game": "cat-tower"])
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
        return minted
    }

    // MARK: requests

    private func authenticated(_ method: String, _ path: String, body: [String: String]?) async throws -> Data {
        let url = config.endpoint(path)
        let payload = try body.map { try JSONEncoder().encode($0) }
        var cred = try await credential()
        for attempt in 0..<2 {
            do {
                return try await Self.send(
                    session: session, method: method, url: url, bearer: cred.token, body: payload)
            } catch APIError.unauthorized where attempt == 0 {
                credentials.clear()
                cached = nil
                cred = try await mint()
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
        case 404: throw APIError.notFound
        case 429: throw APIError.rateLimited
        case 503 where errorCode(in: data) == "not_configured": throw APIError.notConfigured
        default: throw APIError.server(http.statusCode)
        }
    }

    private static func errorCode(in data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, status: Int) throws -> T {
        try Self.decode(type, from: data, status: status)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, status: Int) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw APIError.server(status) }
    }
}
