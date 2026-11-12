import Foundation
import Network
import Synchronization
import Testing
@testable import PounceKit

@Suite struct AppStatusTests {
    private func decode(_ json: String) throws -> AppStatus {
        try JSONDecoder().decode(AppStatus.self, from: Data(json.utf8))
    }

    @Test func readsEverythingTheServerSays() throws {
        let status = try decode(
            #"{"latest":"1.2","minimum":"1.1","storeUrl":"https://apps.apple.com/app/id6829560061","testflightUrl":"https://testflight.apple.com/join/abc"}"#)
        #expect(status == AppStatus(
            latest: "1.2", minimum: "1.1", storeUrl: "https://apps.apple.com/app/id6829560061",
            testflightUrl: "https://testflight.apple.com/join/abc"))
    }

    @Test func beforeReleaseTheServerSaysAlmostNothing() throws {
        #expect(try decode("{}") == AppStatus())
        #expect(try decode(#"{"testflightUrl":"https://testflight.apple.com/join/abc"}"#).latest == nil)
    }

    @Test func aKeyItCannotReadIsAbsentAndAKeyItDoesNotKnowIsIgnored() throws {
        let status = try decode(#"{"latest":12,"minimum":null,"storeUrl":["x"],"android":{"latest":"9"},"testflightUrl":"t"}"#)
        #expect(status == AppStatus(testflightUrl: "t"))
    }
}

@Suite struct UpdateRefusalTests {
    private func read(_ status: Int, _ headers: [String: String] = [:], _ body: String? = nil) -> UpdateRefusal? {
        UpdateRefusal.read(status: status, headers: headers, body: body.map { Data($0.utf8) })
    }

    @Test func tooOldWithItsBody() {
        let body = #"{"error":"update_required","minimum":"1.2","storeUrl":"https://apps.apple.com/app/id6829560061","testflightUrl":"https://testflight.apple.com/join/abc"}"#
        let need = UpdateRequirement(
            minimum: "1.2", storeUrl: "https://apps.apple.com/app/id6829560061", testflightUrl: "https://testflight.apple.com/join/abc")
        #expect(read(426, ["X-Pounce-Update": "required"], body) == .required(need))
        // Without the header the body says it; without the body the header does.
        #expect(read(426, [:], body) == .required(need))
        #expect(read(426, ["x-pounce-update": "required"]) == .required(UpdateRequirement()))
        #expect(read(426, ["X-POUNCE-UPDATE": " Required "]) == .required(UpdateRequirement()))
    }

    @Test func aTableThatNeedsANewerAppFromHeadersAlone() {
        // A refused socket upgrade: no body ever arrives.
        let headers = ["X-Pounce-Update": "game", "X-Pounce-Game": "tiles", "X-Pounce-Game-Title": "Tuna%20Tiles"]
        #expect(read(426, headers) == .game(id: "tiles", title: "Tuna Tiles"))
        #expect(read(426, ["x-pounce-update": "game", "x-pounce-game": "chess"]) == .game(id: "chess", title: nil))
    }

    @Test func aTableThatNeedsANewerAppFromTheBody() {
        #expect(read(426, [:], #"{"error":"game_unsupported","game":"tiles","title":"Tuna Tiles"}"#) == .game(id: "tiles", title: "Tuna Tiles"))
        #expect(read(426, ["x-pounce-update": "game"], #"{"game":"tiles"}"#) == .game(id: "tiles", title: nil))
    }

    @Test func aGameRefusalThatNamesNoGameIsNotOne() {
        #expect(read(426, ["x-pounce-update": "game"]) == nil)
        #expect(read(426, ["x-pounce-update": "game", "x-pounce-game": "  "]) == nil)
        #expect(read(426, [:], #"{"error":"game_unsupported"}"#) == nil)
    }

    @Test func aNameNobodyShouldShowIsLeftOut() {
        let long = String(repeating: "x", count: 41)
        #expect(read(426, ["x-pounce-update": "game", "x-pounce-game": "tiles", "x-pounce-game-title": long]) == .game(id: "tiles", title: nil))
        #expect(read(426, ["x-pounce-update": "game", "x-pounce-game": "tiles", "x-pounce-game-title": "Tuna%0ATiles"]) == .game(id: "tiles", title: nil))
        #expect(read(426, ["x-pounce-update": "game", "x-pounce-game": "tiles", "x-pounce-game-title": "%E0%A4%A"]) == .game(id: "tiles", title: nil))
    }

    @Test func theOld426IsNotARefusal() {
        // "This route wants a WebSocket": what the server always answered a plain GET of the socket route.
        #expect(read(426, [:], #"{"error":"upgrade_required"}"#) == nil)
        #expect(read(426) == nil)
        #expect(read(426, ["x-pounce-update": "something-new"]) == nil)
        #expect(read(426, [:], "not json") == nil)
    }

    @Test func noOtherStatusIsEverARefusal() {
        for status in [200, 400, 401, 404, 409, 429, 500, 503] {
            #expect(read(status, ["x-pounce-update": "required"], #"{"error":"update_required"}"#) == nil)
        }
    }
}

@Suite struct TablesReplyTests {
    private func decode(_ json: String) throws -> TablesReply {
        try JSONDecoder().decode(TablesReply.self, from: Data(json.utf8))
    }

    /// What version 1.0 gets, and what 1.1 gets while nothing is locked: the server's own sample.
    @Test func theBodyWithoutLockedIsTheTablesAlone() throws {
        let reply = try decode(#"{"tables":[{"code":"BCDFG","status":"playing","yourTurn":true,"updatedAt":1}]}"#)
        #expect(reply.tables.map(\.code) == ["BCDFG"])
        #expect(reply.locked.isEmpty)
    }

    @Test func readsLockedTables() throws {
        let reply = try decode(
            #"{"tables":[],"locked":[{"code":"GH2VD","name":"Taco Night","game":"tiles","title":"Tuna Tiles","updatedAt":1800000000000,"seats":[{"kind":"human","person":{"id":"a","name":"Mia","cat":2}},{"kind":"bot"}]}]}"#)
        #expect(reply.locked.count == 1)
        #expect(reply.locked[0].code == "GH2VD")
        #expect(reply.locked[0].title == "Tuna Tiles")
        #expect(reply.locked[0].seats?.first?.person?.name == "Mia")
    }

    @Test func lockedNeverFailsTheTables() throws {
        // One it can't read is dropped; the rest, and the tables, are kept.
        let reply = try decode(
            #"{"tables":[{"code":"BCDFG","status":"lobby","yourTurn":false,"updatedAt":1}],"locked":[{"code":"GH2VD"},{"code":"TB4XN","game":"tiles","updatedAt":"soon","seats":7},42]}"#)
        #expect(reply.tables.map(\.code) == ["BCDFG"])
        #expect(reply.locked == [LockedTable(code: "TB4XN", game: "tiles", updatedAt: 0)])
        #expect(try decode(#"{"tables":[],"locked":"nope"}"#).locked.isEmpty)
    }
}

// MARK: - over the wire

/// A loopback HTTP server (plain TCP): keeps each request's head, answers every one with the
/// same canned response. For what a stubbed `URLProtocol` can't show: the headers that really
/// leave, and what `URLSessionWebSocketTask` makes of a refused upgrade.
private final class RawServer: Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "raw-http")
    private let heads = Mutex<[String]>([])
    private let connections = Mutex<[NWConnection]>([])

    init(response: String) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self, queue] connection in
            self?.connections.withLock { $0.append(connection) }
            connection.start(queue: queue)
            self?.read(connection, buffer: Data(), response: response)
        }
    }

    private func read(_ connection: NWConnection, buffer: Data, response: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self?.heads.withLock { $0.append(String(decoding: buffer[..<end.lowerBound], as: UTF8.self)) }
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            } else if !done, error == nil {
                self?.read(connection, buffer: buffer, response: response)
            }
        }
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let once = Mutex(false)
            listener.stateUpdateHandler = { [listener] state in
                let result: Result<UInt16, any Error>?
                switch state {
                case .ready: result = .success(listener.port?.rawValue ?? 0)
                case .failed(let error): result = .failure(error)
                default: result = nil
                }
                guard let result, once.withLock({ done in defer { done = true }; return !done }) else { return }
                continuation.resume(with: result)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        for c in connections.withLock({ $0 }) { c.cancel() }
    }

    /// Each request's header lines, lowercased name to value.
    var requests: [[String: String]] {
        heads.withLock { $0 }.map { head in
            var out: [String: String] = [:]
            for line in head.split(separator: "\r\n").dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                out[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            return out
        }
    }

    static func response(_ status: String, headers: [String: String] = [:], body: String = "") -> String {
        var lines = ["HTTP/1.1 \(status)", "Content-Type: application/json", "Content-Length: \(body.utf8.count)", "Connection: close"]
        lines += headers.map { "\($0.key): \($0.value)" }
        return lines.joined(separator: "\r\n") + "\r\n\r\n" + body
    }
}

private let v11 = ["X-Pounce-App": "platform=ios; version=1.1; build=57; protocol=1"]

@Suite(.timeLimit(.minutes(1))) struct UpdateWireOverHTTPTests {
    private func client(port: UInt16, headers: [String: String]) -> APIClient {
        let config = APIConfig(baseURL: URL(string: "http://127.0.0.1:\(port)")!, headers: headers)
        let store = MemoryCredentialStore()
        store.save(DeviceCredential(deviceId: "dev-1", token: "tok-1"))
        return APIClient(config: config, credentials: store, session: URLSession(configuration: .ephemeral))
    }

    @Test func everyCallSaysWhatTheAppIs() async throws {
        let server = try RawServer(response: RawServer.response("200 OK", body: #"{"tables":[]}"#))
        defer { server.stop() }
        let api = client(port: try await server.start(), headers: v11)
        _ = try await api.listTables()
        _ = try await api.listTablesAndLocked()
        _ = try? await api.appStatus()
        #expect(server.requests.count == 3)
        for request in server.requests {
            #expect(request["x-pounce-app"] == "platform=ios; version=1.1; build=57; protocol=1")
        }
        // The status route needs no credential, and gets none.
        #expect(server.requests[0]["authorization"] == "Bearer tok-1")
        #expect(server.requests[2]["authorization"] == nil)
    }

    /// Version 1.0, and anything that isn't the app (the e2e tool, these tests): no header at all.
    @Test func withNoIdentityNothingIsSaid() async throws {
        let server = try RawServer(response: RawServer.response("200 OK", body: #"{"tables":[]}"#))
        defer { server.stop() }
        let api = client(port: try await server.start(), headers: [:])
        _ = try await api.listTables()
        #expect(server.requests.count == 1)
        #expect(!server.requests[0].keys.contains { $0.hasPrefix("x-pounce") })
    }

    @Test func tooOldIsItsOwnErrorAndTellsTheHandler() async throws {
        let body = #"{"error":"update_required","minimum":"1.2","storeUrl":"https://apps.apple.com/app/id6829560061"}"#
        let server = try RawServer(response: RawServer.response("426 Upgrade Required", headers: ["X-Pounce-Update": "required"], body: body))
        defer { server.stop() }
        let api = client(port: try await server.start(), headers: v11)
        let heard = Mutex<[UpdateRequirement]>([])
        await api.setUpdateRequiredHandler { need in heard.withLock { $0.append(need) } }
        let need = UpdateRequirement(minimum: "1.2", storeUrl: "https://apps.apple.com/app/id6829560061")
        await #expect(throws: APIError.updateRequired(need)) { _ = try await api.listTables() }
        #expect(heard.withLock { $0 } == [need])
        // The status route says the same, to whoever asked it.
        await #expect(throws: APIError.updateRequired(need)) { _ = try await api.appStatus() }
    }

    @Test func aDeviceThatCannotEvenBeMintedIsToldToo() async throws {
        let server = try RawServer(response: RawServer.response("426 Upgrade Required", headers: ["X-Pounce-Update": "required"], body: #"{"error":"update_required"}"#))
        defer { server.stop() }
        let config = APIConfig(baseURL: URL(string: "http://127.0.0.1:\(try await server.start())")!, headers: v11)
        let api = APIClient(config: config, credentials: MemoryCredentialStore(), session: URLSession(configuration: .ephemeral))
        let heard = Mutex(0)
        await api.setUpdateRequiredHandler { _ in heard.withLock { $0 += 1 } }
        await #expect(throws: APIError.updateRequired(UpdateRequirement())) { _ = try await api.listTables() }
        #expect(heard.withLock { $0 } == 1)
    }

    @Test func anyOther426IsTheServerErrorItAlwaysWas() async throws {
        let server = try RawServer(response: RawServer.response("426 Upgrade Required", body: #"{"error":"upgrade_required"}"#))
        defer { server.stop() }
        let api = client(port: try await server.start(), headers: v11)
        await #expect(throws: APIError.server(426)) { _ = try await api.listTables() }
    }

    // MARK: the socket upgrade, through the real URLSessionWebSocketTask

    private func connect(_ response: String, headers: [String: String]) async throws -> (Result<Void, SocketConnectError>, [String: String]) {
        let server = try RawServer(response: response)
        defer { server.stop() }
        let url = URL(string: "ws://127.0.0.1:\(try await server.start())/v1/rooms/BCDFG/ws")!
        let connector = URLSessionWebSocketConnector(session: URLSession(configuration: .ephemeral), timeout: .seconds(5), headers: headers)
        do {
            _ = try await connector.connect(url: url, token: "tok-1")
            return (.success(()), server.requests.first ?? [:])
        } catch let error as SocketConnectError {
            return (.failure(error), server.requests.first ?? [:])
        }
    }

    @Test func theUpgradeSaysWhatTheAppIs() async throws {
        let (_, request) = try await connect(RawServer.response("404 Not Found"), headers: v11)
        #expect(request["x-pounce-app"] == "platform=ios; version=1.1; build=57; protocol=1")
        #expect(request["authorization"] == "Bearer tok-1")
        #expect(request["upgrade"]?.lowercased() == "websocket")
    }

    @Test func aRefusedUpgradeNamesTheGameFromItsHeaders() async throws {
        let refusal = RawServer.response(
            "426 Upgrade Required", headers: ["X-Pounce-Update": "game", "X-Pounce-Game": "tiles", "X-Pounce-Game-Title": "Tuna%20Tiles"],
            body: #"{"error":"game_unsupported","game":"tiles","title":"Tuna Tiles"}"#)
        let (result, _) = try await connect(refusal, headers: v11)
        #expect(result == .failure(.refused(.game(id: "tiles", title: "Tuna Tiles"))))
    }

    @Test func aRefusedUpgradeSaysTheAppIsTooOld() async throws {
        let refusal = RawServer.response("426 Upgrade Required", headers: ["X-Pounce-Update": "required"], body: #"{"error":"update_required","minimum":"1.2"}"#)
        let (result, _) = try await connect(refusal, headers: v11)
        // The body of a refused upgrade never reaches the app: the header alone says it.
        #expect(result == .failure(.refused(.required(UpdateRequirement()))))
    }

    @Test func the404AndThePlain426AreWhatTheyWere() async throws {
        #expect(try await connect(RawServer.response("404 Not Found"), headers: [:]).0 == .failure(.notFound))
        let (plain, request) = try await connect(RawServer.response("426 Upgrade Required"), headers: [:])
        #expect(plain == .failure(.failed("upgrade refused with HTTP 426")))
        #expect(!request.keys.contains { $0.hasPrefix("x-pounce") })
    }
}

extension Result where Success == Void, Failure == SocketConnectError {
    fileprivate static func == (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case (.success, .success): true
        case (.failure(let x), .failure(let y)): x == y
        default: false
        }
    }
}

// MARK: - the socket and the store

@Suite(.timeLimit(.minutes(1))) struct RefusedSocketTests {
    private let config = APIConfig(baseURL: URL(string: "http://localhost:8787")!)

    private func events(_ connector: FakeConnector, credential: @escaping @Sendable () async throws -> DeviceCredential) async -> ([SocketEvent], Int) {
        let sleeper = FakeSleeper()
        let socket = RoomSocket(
            code: "BCDFG", config: config, credential: credential, connector: connector, tick: sleeper.pingInterval,
            sleep: { try await sleeper.sleep($0) })
        var reader = EventReader(socket.events)
        await socket.start()
        let all = await reader.rest()
        return (all, sleeper.backoffs.count)
    }

    @Test func aRefusalEndsTheSocketWithoutARetry() async {
        for refusal in [UpdateRefusal.game(id: "tiles", title: "Tuna Tiles"), .required(UpdateRequirement(minimum: "1.2"))] {
            let connector = FakeConnector([.failure(.refused(refusal)), .connection(FakeConnection())])
            let (seen, backoffs) = await events(connector) { DeviceCredential(deviceId: "dev-1", token: "tok-1") }
            #expect(seen == [.connecting, .refused(refusal)])
            #expect(connector.calls.count == 1)
            #expect(backoffs == 0)
        }
    }

    @Test func aCredentialTheServerWillNotMintIsARefusalToo() async {
        let need = UpdateRequirement(minimum: "1.2")
        let connector = FakeConnector([.connection(FakeConnection())])
        let (seen, backoffs) = await events(connector) { throw APIError.updateRequired(need) }
        #expect(seen == [.connecting, .refused(.required(need))])
        #expect(connector.calls.isEmpty)
        #expect(backoffs == 0)
    }
}

@MainActor @Suite struct RefusedStoreTests {
    @Test func aRefusalIsTerminalAndSaysWhy() {
        let refusal = UpdateRefusal.game(id: "tiles", title: "Tuna Tiles")
        let store = RoomStore(code: "BCDFG", socket: FakeSocket())
        store.handle(.connecting)
        store.handle(.refused(refusal))
        #expect(store.phase == .needsUpdate)
        #expect(store.refusal == refusal)
        #expect(!store.connected)
        // Nothing after it changes the verdict.
        store.handle(.notFound)
        store.handle(.refused(.required(UpdateRequirement())))
        #expect(store.phase == .needsUpdate)
        #expect(store.refusal == refusal)
    }

    @Test func aRefusalAfterTheTableClosedChangesNothing() {
        let store = RoomStore(code: "BCDFG", socket: FakeSocket())
        store.handle(.closed)
        store.handle(.refused(.required(UpdateRequirement())))
        #expect(store.phase == .closed)
        #expect(store.refusal == nil)
    }

    /// What version 1.0 already did, and still does: a snapshot of another protocol asks for an update, with no reason given.
    @Test func aSnapshotOfAnotherProtocolStillAsksForAnUpdate() throws {
        let store = RoomStore(code: "BCDFG", socket: FakeSocket())
        store.handle(.message(try Codec.decode(#"{"t":"snapshot","protocol":0}"#)))
        #expect(store.phase == .needsUpdate)
        #expect(store.refusal == nil)
    }
}
