import Foundation
import Synchronization
import Testing
@testable import PounceKit

/// One recorded request.
struct Seen: Sendable {
    var method: String
    var path: String
    var authorization: String?
    var body: Data
}

/// A canned response.
struct Reply: Sendable {
    var status: Int
    var body: String
    /// Seconds to hold the response back (on the loading thread's run loop).
    var delay: TimeInterval
    init(_ status: Int, _ body: String = "{}", delay: TimeInterval = 0) {
        self.status = status
        self.body = body
        self.delay = delay
    }
}

/// Per-test stub server. Each instance owns a unique host, so tests running in
/// parallel never share state: `StubProtocol` looks the instance up by host.
final class StubServer: Sendable {
    let host = "stub-\(UUID().uuidString.lowercased()).test"
    private let state = Mutex<(seen: [Seen], handler: @Sendable (Seen) -> Reply)>(([], { _ in Reply(500) }))

    init(_ handler: @escaping @Sendable (Seen) -> Reply) {
        state.withLock { $0.handler = handler }
        StubRegistry.register(self, host: host)
    }

    deinit { StubRegistry.unregister(host: host) }

    var baseURL: URL { URL(string: "http://\(host)")! }
    var seen: [Seen] { state.withLock { $0.seen } }

    func config() -> APIConfig { APIConfig(baseURL: baseURL) }

    func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }

    fileprivate func handle(_ request: Seen) -> Reply {
        let handler = state.withLock { s -> @Sendable (Seen) -> Reply in
            s.seen.append(request)
            return s.handler
        }
        return handler(request)
    }
}

enum StubRegistry {
    private static let servers = Mutex<[String: StubServer]>([:])
    static func register(_ s: StubServer, host: String) { servers.withLock { $0[host] = s } }
    static func unregister(host: String) { servers.withLock { _ = $0.removeValue(forKey: host) } }
    static func server(for host: String) -> StubServer? { servers.withLock { $0[host] } }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {  // URLProtocol is a non-Sendable class; we only touch immutable request state
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let host = url.host, let server = StubRegistry.server(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        let seen = Seen(
            method: request.httpMethod ?? "GET", path: url.path,
            authorization: request.value(forHTTPHeaderField: "Authorization"), body: body)
        let reply = server.handle(seen)
        guard reply.delay > 0 else { return respond(reply, url: url) }
        // URLProtocol clients must be called on the loading thread, whose run loop is running.
        RunLoop.current.add(Timer(timeInterval: reply.delay, repeats: false) { [self] _ in
            respond(reply, url: url)
        }, forMode: .common)
    }

    private func respond(_ reply: Reply, url: URL) {
        let response = HTTPURLResponse(
            url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite struct APIClientTests {
    private func client(
        _ server: StubServer, store: CredentialStore = MemoryCredentialStore()
    ) -> (APIClient, CredentialStore) {
        (APIClient(config: server.config(), credentials: store, session: server.session()), store)
    }

    @Test func mintsOnceAndCaches() async throws {
        let server = StubServer { _ in Reply(200, #"{"deviceId":"dev1","token":"tok1"}"#) }
        let (api, store) = client(server)
        let a = try await api.credential()
        let b = try await api.credential()
        #expect(a == DeviceCredential(deviceId: "dev1", token: "tok1"))
        #expect(a == b)
        #expect(store.load() == a)
        #expect(server.seen.count == 1)
        #expect(server.seen[0].method == "POST")
        #expect(server.seen[0].path == "/v1/devices")
    }

    @Test func usesAStoredCredentialWithoutMinting() async throws {
        let server = StubServer { _ in Reply(500) }
        let stored = DeviceCredential(deviceId: "d", token: "t")
        let (api, _) = client(server, store: { let s = MemoryCredentialStore(); s.save(stored); return s }())
        #expect(try await api.credential() == stored)
        #expect(server.seen.isEmpty)
    }

    @Test func concurrentFirstCallsMintOnce() async throws {
        let server = StubServer { _ in Reply(200, #"{"deviceId":"dev1","token":"tok1"}"#) }
        let (api, _) = client(server)
        try await withThrowingTaskGroup(of: DeviceCredential.self) { group in
            for _ in 0..<8 { group.addTask { try await api.credential() } }
            for try await c in group { #expect(c.deviceId == "dev1") }
        }
        #expect(server.seen.count == 1)
    }

    @Test func createRoomSendsBodyAndBearer() async throws {
        let server = StubServer { req in
            req.path == "/v1/devices" ? Reply(200, #"{"deviceId":"dev1","token":"tok1"}"#) : Reply(201, #"{"code":"K7QM4"}"#)
        }
        let (api, _) = client(server)
        let code = try await api.createRoom()
        #expect(code == "K7QM4")
        let post = try #require(server.seen.last)
        #expect(post.method == "POST")
        #expect(post.path == "/v1/rooms")
        #expect(post.authorization == "Bearer tok1")
        let json = try #require(try JSONSerialization.jsonObject(with: post.body) as? [String: String])
        #expect(json == ["game": "cat-tower"])
    }

    @Test func listTablesDecodes() async throws {
        let server = StubServer { req in
            req.path == "/v1/devices"
                ? Reply(200, #"{"deviceId":"dev1","token":"tok1"}"#)
                : Reply(200, #"{"tables":[{"code":"K7QM4","status":"playing","yourTurn":true,"updatedAt":1700000000123.5}]}"#)
        }
        let (api, _) = client(server)
        let tables = try await api.listTables()
        #expect(tables == [TableEntry(code: "K7QM4", status: "playing", yourTurn: true, updatedAt: 1_700_000_000_123.5)])
        let get = try #require(server.seen.last)
        #expect(get.method == "GET")
        #expect(get.path == "/v1/devices/me/tables")
        #expect(get.authorization == "Bearer tok1")
    }

    @Test func setPushTokenPutsHex() async throws {
        let server = StubServer { req in
            req.path == "/v1/devices" ? Reply(200, #"{"deviceId":"dev1","token":"tok1"}"#) : Reply(204, "")
        }
        let (api, _) = client(server)
        let hex = String(repeating: "ab", count: 32)
        try await api.setPushToken(hex)
        let put = try #require(server.seen.last)
        #expect(put.method == "PUT")
        #expect(put.path == "/v1/devices/me/push")
        #expect(put.authorization == "Bearer tok1")
        let json = try #require(try JSONSerialization.jsonObject(with: put.body) as? [String: String])
        #expect(json == ["apnsToken": hex])
    }

    @Test func staleTokenIsReplacedAndRetrySucceeds() async throws {
        let server = StubServer { req in
            if req.path == "/v1/devices" { return Reply(200, #"{"deviceId":"fresh","token":"good"}"#) }
            return req.authorization == "Bearer good" ? Reply(200, #"{"tables":[]}"#) : Reply(401, #"{"error":"unauthorized"}"#)
        }
        let store = MemoryCredentialStore()
        store.save(DeviceCredential(deviceId: "old", token: "stale"))
        let (api, _) = client(server, store: store)
        let tables = try await api.listTables()
        #expect(tables.isEmpty)
        #expect(server.seen.map { "\($0.method) \($0.path)" } == [
            "GET /v1/devices/me/tables", "POST /v1/devices", "GET /v1/devices/me/tables",
        ])
        #expect(store.load() == DeviceCredential(deviceId: "fresh", token: "good"))
    }

    /// M-8: a re-mint after a 401 reports the new credential, and the push token upload says
    /// which device the server stored it for.
    @Test func reMintReportsTheNewCredential() async throws {
        let server = StubServer { req in
            if req.path == "/v1/devices" { return Reply(200, #"{"deviceId":"fresh","token":"good"}"#) }
            return req.authorization == "Bearer good" ? Reply(204, "") : Reply(401, #"{"error":"unauthorized"}"#)
        }
        let store = MemoryCredentialStore()
        store.save(DeviceCredential(deviceId: "old", token: "stale"))
        let (api, _) = client(server, store: store)
        let changes = Mutex<[String]>([])
        await api.setCredentialChangeHandler { cred in changes.withLock { $0.append(cred.deviceId) } }
        let device = try await api.setPushToken("ab")
        #expect(device == "fresh")
        #expect(changes.withLock { $0 } == ["fresh"])
        // A call with the fresh credential mints nothing and reports nothing.
        #expect(try await api.setPushToken("ab") == "fresh")
        #expect(changes.withLock { $0 } == ["fresh"])
    }

    /// Two calls go out with the same stale token. The first 401 re-mints; the second
    /// 401 lands after that mint finished and must retry with the fresh credential
    /// instead of clearing it and minting again.
    @Test func concurrentStaleCallsMintOnce() async throws {
        let staleSeen = Mutex(0)
        let server = StubServer { req in
            if req.path == "/v1/devices" { return Reply(200, #"{"deviceId":"fresh","token":"good"}"#) }
            if req.authorization == "Bearer good" { return Reply(200, #"{"tables":[]}"#) }
            let n = staleSeen.withLock { $0 += 1; return $0 }
            // The second stale 401 arrives well after the first one's re-mint is done.
            return Reply(401, #"{"error":"unauthorized"}"#, delay: n == 1 ? 0 : 0.5)
        }
        let store = MemoryCredentialStore()
        store.save(DeviceCredential(deviceId: "old", token: "stale"))
        let (api, _) = client(server, store: store)
        try await withThrowingTaskGroup(of: [TableEntry].self) { group in
            for _ in 0..<2 { group.addTask { try await api.listTables() } }
            for try await tables in group { #expect(tables.isEmpty) }
        }
        #expect(staleSeen.withLock { $0 } == 2)  // both really went out stale
        #expect(server.seen.filter { $0.path == "/v1/devices" }.count == 1)
        #expect(store.load() == DeviceCredential(deviceId: "fresh", token: "good"))
    }

    @Test func aSecond401AfterRetryIsUnauthorizedAndDoesNotLoop() async throws {
        let server = StubServer { req in
            req.path == "/v1/devices" ? Reply(200, #"{"deviceId":"d","token":"t"}"#) : Reply(401, #"{"error":"unauthorized"}"#)
        }
        let (api, _) = client(server)
        await #expect(throws: APIError.unauthorized) { _ = try await api.listTables() }
        // mint, GET (401), mint, GET (401): one re-mint, one retry, then give up.
        #expect(server.seen.map(\.path) == ["/v1/devices", "/v1/devices/me/tables", "/v1/devices", "/v1/devices/me/tables"])
    }

    @Test func notConfiguredFrom503() async throws {
        let server = StubServer { _ in Reply(503, #"{"error":"not_configured"}"#) }
        let (api, _) = client(server)
        await #expect(throws: APIError.notConfigured) { _ = try await api.credential() }
        await #expect(throws: APIError.notConfigured) { _ = try await api.createRoom() }
    }

    @Test func rateLimitedFrom429() async throws {
        let server = StubServer { _ in Reply(429, #"{"error":"rate_limited"}"#) }
        let (api, _) = client(server)
        await #expect(throws: APIError.rateLimited) { _ = try await api.credential() }
    }

    @Test func statusMapping() async throws {
        func run(_ status: Int, _ body: String) async -> APIError? {
            let server = StubServer { req in
                req.path == "/v1/devices" ? Reply(200, #"{"deviceId":"d","token":"t"}"#) : Reply(status, body)
            }
            let (api, _) = client(server)
            do { _ = try await api.createRoom(); return nil } catch { return error as? APIError }
        }
        #expect(await run(400, #"{"error":"bad_request"}"#) == .badRequest)
        #expect(await run(404, #"{"error":"not_found"}"#) == .notFound)
        #expect(await run(429, #"{"error":"rate_limited"}"#) == .rateLimited)
        #expect(await run(503, #"{"error":"no_room_code"}"#) == .server(503))
        #expect(await run(500, "oops") == .server(500))
        #expect(await run(503, #"{"error":"not_configured"}"#) == .notConfigured)
    }

    @Test func transportFailureIsReported() async throws {
        // No server registered for this host: the stub fails the request.
        let ghost = StubServer { _ in Reply(500) }
        let session = ghost.session()
        let config = ghost.config()
        StubRegistry.unregister(host: ghost.host)
        let api = APIClient(config: config, credentials: MemoryCredentialStore(), session: session)
        do {
            _ = try await api.credential()
            Issue.record("expected a throw")
        } catch let APIError.transport(message) {
            #expect(!message.isEmpty)
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func malformedSuccessBodyIsAServerError() async throws {
        let server = StubServer { _ in Reply(200, "not json") }
        let (api, _) = client(server)
        await #expect(throws: APIError.server(200)) { _ = try await api.credential() }
    }

    // MARK: Keychain

    // The macOS `swift test` host is an unsigned binary with no keychain-access-groups
    // entitlement, so the data-protection keychain refuses it (errSecMissingEntitlement).
    // Probe once; run the round trip only where the keychain is usable, otherwise the
    // logic is covered through MemoryCredentialStore and the store is exercised on device.
    @Test func keychainRoundTripWhereAvailable() throws {
        let store = KeychainCredentialStore(service: "com.conleychaos.play.device.tests-\(UUID().uuidString)")
        let c = DeviceCredential(deviceId: "d", token: "t")
        store.save(c)
        guard store.load() != nil else {
            store.clear()
            try Test.cancel("data-protection keychain unavailable to this test host (unsigned, no entitlements)")
        }
        #expect(store.load() == c)
        store.save(DeviceCredential(deviceId: "d2", token: "t2"))
        #expect(store.load() == DeviceCredential(deviceId: "d2", token: "t2"))
        store.clear()
        #expect(store.load() == nil)
    }
}
