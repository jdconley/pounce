import Foundation
import Testing
@testable import PounceKit

/// The streak routes of play-api PR 3 (`apps/play-api/src/index.ts`, `tests/streaks.test.ts`).
@Suite struct StreakAPITests {
    private static let minted = #"{"deviceId":"dev1","token":"tok1"}"#
    private let me = "6f1c0e0e-0000-4000-8000-000000000001"
    private let pair = "pr_AAAAAAAAAAAAAAAAAAAAAA"

    private func client(_ reply: @escaping @Sendable (Seen) -> Reply) -> (APIClient, StubServer) {
        let server = StubServer { req in req.path == "/v1/devices" ? Reply(200, Self.minted) : reply(req) }
        return (APIClient(config: server.config(), credentials: MemoryCredentialStore(), session: server.session()), server)
    }

    @Test func listReadsPairsAndLeft() async throws {
        let (api, server) = client { _ in
            Reply(200, #"{"pairs":[{"pair":"pr_x","partner":{"name":"Mia","cat":2},"count":5,"pinned":true}],"left":[]}"#)
        }
        let list = try await api.streaks(person: me)
        #expect(list.pairs.map(\.count) == [5])
        #expect(list.pairs.first?.pinned == true)
        let get = try #require(server.seen.last)
        #expect(get.method == "GET")
        #expect(get.path == "/v1/me/streaks")
        #expect(get.query == "person=\(me)")
    }

    @Test func listIsNotFoundWhenStreaksAreOff() async throws {
        let (api, _) = client { _ in Reply(404, #"{"error":"not_found"}"#) }
        await #expect(throws: APIError.notFound) { _ = try await api.streaks(person: me) }
    }

    @Test func aPersonWithoutAPlayerYetIsNotStreaksOff() async throws {
        let (api, _) = client { _ in Reply(404, #"{"error":"no_player"}"#) }
        await #expect(throws: APIError.noPlayer) { _ = try await api.streaks(person: me) }
    }

    @Test func eachActionHitsItsRoute() async throws {
        let (api, server) = client { _ in Reply(204, "") }
        try await api.pause(pair: pair, days: 3, person: me)
        try await api.unpause(pair: pair, person: me)
        try await api.openGift(pair: pair, gift: "g7", person: me)
        try await api.pin(pair: pair, person: me)
        try await api.leave(pair: pair, person: me)
        try await api.rejoin(pair: pair, person: me)
        let calls = server.seen.filter { $0.path != "/v1/devices" }.map { "\($0.method) \($0.path)" }
        #expect(calls == [
            "PUT /v1/pairs/\(pair)/pause", "DELETE /v1/pairs/\(pair)/pause", "POST /v1/pairs/\(pair)/gifts/g7/open",
            "PUT /v1/pairs/\(pair)/pin", "DELETE /v1/pairs/\(pair)", "DELETE /v1/me/left/\(pair)",
        ])
        let pause = try #require(server.seen.first { $0.path.hasSuffix("/pause") })
        let body = try #require(try JSONSerialization.jsonObject(with: pause.body) as? [String: Any])
        #expect(body.count == 1 && body["days"] as? Int == 3)
        #expect(server.seen.filter { $0.path != "/v1/devices" }.allSatisfy { $0.query == "person=\(me)" })
    }
}
