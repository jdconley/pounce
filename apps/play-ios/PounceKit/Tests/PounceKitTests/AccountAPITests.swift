import Foundation
import Testing
@testable import PounceKit

/// The account routes of play-api PR 1 (`apps/play-api/src/index.ts`, `tests/accounts.test.ts`).
@Suite struct AccountAPITests {
    private static let minted = #"{"deviceId":"dev1","token":"tok1"}"#

    private func client(_ reply: @escaping @Sendable (Seen) -> Reply) -> (APIClient, StubServer) {
        let server = StubServer { req in req.path == "/v1/devices" ? Reply(200, Self.minted) : reply(req) }
        return (APIClient(config: server.config(), credentials: MemoryCredentialStore(), session: server.session()), server)
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let mia = ProfilePerson(
        id: "6f1c0e0e-0000-4000-8000-000000000001", name: "Mia", cat: 2,
        key: String(repeating: "a", count: 43), ageBand: nil, at: 1234)

    @Test func testUploadProfileSendsTheBodyAndReadsPlayers() async throws {
        let (api, server) = client { _ in
            Reply(200, #"{"players":{"6f1c0e0e-0000-4000-8000-000000000001":"p_AAAAAAAAAAAAAAAAAAAAAA"},"rejected":[]}"#)
        }
        let reply = try await api.uploadProfile(ProfileBody(timeZone: "America/Los_Angeles", ageBand: .adult, people: [mia]))
        #expect(reply.players == [mia.id: "p_AAAAAAAAAAAAAAAAAAAAAA"])
        #expect(reply.rejected.isEmpty)
        let put = try #require(server.seen.last)
        #expect(put.method == "PUT")
        #expect(put.path == "/v1/devices/me/profile")
        #expect(put.authorization == "Bearer tok1")
        let body = try json(put.body)
        #expect(body["timeZone"] as? String == "America/Los_Angeles")
        #expect(body["ageBand"] as? String == "adult")
        let person = try #require((body["people"] as? [[String: Any]])?.first)
        #expect(person["id"] as? String == mia.id)
        #expect(person["key"] as? String == mia.key)
        #expect(person["at"] as? Int == 1234)
        #expect(person["ageBand"] == nil)
    }

    @Test func testOptionalFieldsAreOmitted() async throws {
        let (api, server) = client { _ in Reply(200, #"{"players":{},"rejected":["x"]}"#) }
        let reply = try await api.uploadProfile(ProfileBody(timeZone: "UTC", ageBand: nil, people: [mia]))
        #expect(reply.rejected == ["x"])
        let body = try json(try #require(server.seen.last).body)
        #expect(body.keys.sorted() == ["people", "timeZone"])
    }

    @Test func testSignInPostsProofAndPerson() async throws {
        let (api, server) = client { _ in
            Reply(200, #"{"playerId":"p_B","outcome":"merged","account":true,"profile":{"name":"JD","cat":4}}"#)
        }
        let proof = AppleProof(identityToken: "tok.en.sig", nonce: "raw", authorizationCode: "code")
        let reply = try await api.signIn(provider: "apple", proof: proof, personId: mia.id, personKey: mia.key)
        #expect(reply == SignInReply(playerId: "p_B", outcome: .merged, account: true, profile: .init(name: "JD", cat: 4)))
        let post = try #require(server.seen.last)
        #expect(post.method == "POST")
        #expect(post.path == "/v1/identities/apple")
        let body = try json(post.body)
        #expect((body["proof"] as? [String: String]) == ["identityToken": "tok.en.sig", "nonce": "raw", "authorizationCode": "code"])
        #expect((body["person"] as? [String: String]) == ["id": mia.id, "key": mia.key])
    }

    @Test func testSignInWithoutCodeLeavesItOut() async throws {
        let (api, server) = client { _ in
            Reply(200, #"{"playerId":"p_B","outcome":"upgraded","account":true,"profile":{"name":"JD","cat":4}}"#)
        }
        _ = try await api.signIn(
            provider: "apple", proof: AppleProof(identityToken: "t", nonce: "n", authorizationCode: nil),
            personId: mia.id, personKey: mia.key)
        let body = try json(try #require(server.seen.last).body)
        #expect((body["proof"] as? [String: String]) == ["identityToken": "t", "nonce": "n"])
    }

    @Test func testForbiddenIsForbidden() async throws {
        let (api, _) = client { _ in Reply(403, #"{"error":"not_allowed"}"#) }
        await #expect(throws: APIError.forbidden) {
            _ = try await api.signIn(
                provider: "apple", proof: AppleProof(identityToken: "t", nonce: "n", authorizationCode: nil),
                personId: mia.id, personKey: mia.key)
        }
    }

    @Test func testLinkMergeNeededReadsOtherPlayer() async throws {
        let (api, server) = client { _ in Reply(409, #"{"error":"merge_needed","otherPlayer":{"name":"Mia","cat":2}}"#) }
        let result = try await api.link(
            provider: "apple", proof: AppleProof(identityToken: "t", nonce: "n", authorizationCode: nil),
            confirmMerge: false, person: mia.id)
        #expect(result == .mergeNeeded(name: "Mia", cat: 2))
        let post = try #require(server.seen.last)
        #expect(post.path == "/v1/me/identities/apple")
        #expect(post.query == "person=\(mia.id)")
        let body = try json(post.body)
        #expect(body["confirmMerge"] as? Bool == false)
    }

    @Test func testLinkConfirmedMerges() async throws {
        let (api, _) = client { _ in Reply(200, #"{"linked":true,"merged":true}"#) }
        let result = try await api.link(
            provider: "apple", proof: AppleProof(identityToken: "t", nonce: "n", authorizationCode: nil),
            confirmMerge: true, person: nil)
        #expect(result == .linked(merged: true))
    }

    @Test func testOtherConflictIsAConflict() async throws {
        let (api, _) = client { _ in Reply(409, #"{"error":"already_linked"}"#) }
        await #expect(throws: APIError.conflict("already_linked")) {
            _ = try await api.link(
                provider: "apple", proof: AppleProof(identityToken: "t", nonce: "n", authorizationCode: nil),
                confirmMerge: false, person: nil)
        }
    }

    @Test func testUnlinkSignOutAndDelete() async throws {
        let (api, server) = client { _ in Reply(204, "") }
        try await api.unlink(provider: "apple", person: nil)
        try await api.signOut()
        try await api.deleteMe(person: mia.id)
        let calls = server.seen.filter { $0.path != "/v1/devices" }.map { "\($0.method) \($0.path) \($0.query ?? "")" }
        #expect(calls == [
            "DELETE /v1/me/identities/apple ",
            "POST /v1/me/signout ",
            "DELETE /v1/me person=\(mia.id)",
        ])
    }

    @Test func testStateReadsAndPatchSends() async throws {
        let (api, server) = client { req in
            req.method == "GET"
                ? Reply(200, #"{"settings":{"soundOn":{"v":true,"at":5}},"tutorial":{},"archive":{},"people":[],"profile":null}"#)
                : Reply(204, "")
        }
        let state = try await api.state(person: nil)
        #expect(state.settings["soundOn"] == SyncEntry(v: .bool(true), at: 5))
        try await api.patchState(StatePatch(archive: ["BCDFG": SyncEntry(v: .null, at: 9)]), person: nil)
        let patch = try #require(server.seen.last)
        #expect(patch.method == "PATCH")
        #expect(patch.path == "/v1/me/state")
        let body = try json(patch.body)
        #expect(body.keys.sorted() == ["archive"])
    }

    @Test func testNoPlayerIsNotFound() async throws {
        let (api, _) = client { _ in Reply(404, #"{"error":"no_player"}"#) }
        await #expect(throws: APIError.notFound) { _ = try await api.state(person: nil) }
    }
}
