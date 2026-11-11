import Foundation
import Testing
@testable import PounceKit

/// Reports, blocks and the name check against play-api's routes (`src/safety/*`, `tests/safety.test.ts`).
@Suite struct SafetyAPITests {
    private static let minted = #"{"deviceId":"dev1","token":"tok1"}"#
    private let me = "6f1c0e0e-0000-4000-8000-000000000001"
    private let them = "6F1C0E0E-0000-4000-8000-000000000002"
    private let player = "p_AAAAAAAAAAAAAAAAAAAAAA"

    private func client(_ reply: @escaping @Sendable (Seen) -> Reply) -> (APIClient, StubServer) {
        let server = StubServer { req in req.path == "/v1/devices" ? Reply(200, Self.minted) : reply(req) }
        return (APIClient(config: server.config(), credentials: MemoryCredentialStore(), session: server.session()), server)
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func aNameCheckSaysOkOrWhyNot() async throws {
        let (api, server) = client { req in
            let name = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any])?["name"] as? String
            switch name {
            case "Mia": return Reply(200, #"{"ok":true}"#)
            case "Zoe": return Reply(200, #"{"ok":false,"reason":"not_allowed"}"#)
            case "New": return Reply(200, #"{"ok":false,"reason":"something_newer"}"#)
            default: return Reply(200, #"{"ok":false,"reason":"bad_name"}"#)
            }
        }
        #expect(try await api.checkName("Mia", kind: .person) == .ok)
        #expect(try await api.checkName("Rude", kind: .table) == .badName)
        #expect(try await api.checkName("Zoe", kind: .person) == .notAllowed)
        #expect(try await api.checkName("New", kind: .person) == .badName)
        let table = try #require(server.seen.first { $0.path == "/v1/names/check" && (try? json($0.body))?["name"] as? String == "Rude" })
        #expect(table.method == "POST")
        #expect(try json(table.body)["kind"] as? String == "table")
    }

    @Test func aReportNamesThePersonAndOneOfTheReasons() async throws {
        let (api, server) = client { _ in Reply(204, "") }
        try await api.report(code: "GH2VD", person: them, reason: .bothering)
        let post = try #require(server.seen.last)
        #expect(post.method == "POST" && post.path == "/v1/rooms/GH2VD/reports" && post.query == nil)
        let body = try json(post.body)
        #expect(body["person"] as? String == them.lowercased())
        #expect(body["reason"] as? String == "bothering")
        #expect(body.count == 2)
        #expect(ReportReason.allCases.map(\.rawValue) == ["name", "bothering", "other"])
    }

    @Test func tooManyReportsIsRateLimited() async throws {
        let (api, _) = client { _ in Reply(429, #"{"error":"rate_limited"}"#) }
        await #expect(throws: APIError.rateLimited) {
            try await api.report(code: "GH2VD", person: them, reason: .name)
        }
    }

    @Test func blockListAndUnblockActForALocalPerson() async throws {
        let (api, server) = client { req in
            switch (req.method, req.path) {
            case ("POST", "/v1/rooms/GH2VD/blocks"): Reply(200, #"{"id":"p_AAAAAAAAAAAAAAAAAAAAAA"}"#)
            case ("GET", "/v1/me/blocks"):
                Reply(200, #"{"blocks":[{"id":"p_AAAAAAAAAAAAAAAAAAAAAA","person":"6f1c0e0e-0000-4000-8000-000000000002","name":"Mia","at":5}]}"#)
            default: Reply(204, "")
            }
        }
        #expect(try await api.block(code: "GH2VD", person: them, me: me) == player)
        let post = try #require(server.seen.last)
        #expect(post.query == "person=\(me)")
        #expect(try json(post.body)["person"] as? String == them.lowercased())

        #expect(try await api.blocks(me: me) == [BlockedPlayer(id: player, person: them.lowercased(), name: "Mia")])
        try await api.unblock(id: player, me: me)
        let delete = try #require(server.seen.last)
        #expect(delete.method == "DELETE" && delete.path == "/v1/me/blocks/\(player)" && delete.query == "person=\(me)")
    }

    @Test func theNewErrorCodesMatchTheServers() {
        #expect(ErrorCode.badName.rawValue == "bad_name")
        #expect(ErrorCode.notAllowed.rawValue == "not_allowed")
        #expect(ErrorCode.blocked.rawValue == "blocked")
    }
}
