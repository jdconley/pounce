import Foundation
import Testing
@testable import PounceKit

@Suite struct LinkScreenTests {
    private func api(_ server: StubServer) -> APIClient {
        APIClient(config: server.config(), credentials: MemoryCredentialStore(), session: server.session())
    }

    private func server(_ reply: Reply) -> StubServer {
        StubServer { req in req.path == "/v1/devices" ? Reply(200, #"{"deviceId":"dev1","token":"tok1"}"#) : reply }
    }

    private func body(_ server: StubServer) throws -> [String: Any] {
        let post = try #require(server.seen.last)
        #expect(post.method == "POST")
        #expect(post.path == "/v1/screens/link")
        #expect(post.authorization == "Bearer tok1")
        return try #require(try JSONSerialization.jsonObject(with: post.body) as? [String: Any])
    }

    @Test func aTokenLinkSendsTokenAndRoom() async throws {
        let s = server(Reply(200, #"{"linked":true}"#))
        #expect(try await api(s).linkScreen(.token("AAAAAAAAAAAAAAAAAAAAAA"), room: "BCDFG", move: false) == .linked)
        let sent = try body(s)
        #expect(sent["token"] as? String == "AAAAAAAAAAAAAAAAAAAAAA")
        #expect(sent["room"] as? String == "BCDFG")
        #expect(Set(sent.keys) == ["token", "room"], "no move, no code")
    }

    @Test func aCodeLinkSendsCodeAndMove() async throws {
        let s = server(Reply(200, #"{"linked":true}"#))
        #expect(try await api(s).linkScreen(.code("k7qm4x"), room: "BCDFG", move: true) == .linked)
        let sent = try body(s)
        #expect(sent["code"] as? String == "k7qm4x")
        #expect(sent["move"] as? Bool == true)
        #expect(Set(sent.keys) == ["code", "room", "move"])
    }

    @Test func aTVShowingAnotherTableAsksFirst() async throws {
        let s = server(Reply(409, #"{"error":"showing"}"#))
        #expect(try await api(s).linkScreen(.token("t"), room: "BCDFG", move: false) == .showing)
    }

    @Test func refusalsAreTyped() async throws {
        func failure(_ reply: Reply) async -> (any Error)? {
            do { _ = try await api(server(reply)).linkScreen(.code("K7QM4X"), room: "BCDFG", move: false); return nil } catch { return error }
        }
        #expect(await failure(Reply(404, #"{"error":"not_found"}"#)) as? ScreenLinkError == .notFound)
        #expect(await failure(Reply(404, "Not Found")) as? ScreenLinkError == .notFound)
        #expect(await failure(Reply(403, #"{"error":"not_seated"}"#)) as? ScreenLinkError == .notSeated)
        #expect(await failure(Reply(409, #"{"error":"seated"}"#)) as? ScreenLinkError == .seated)
        #expect(await failure(Reply(429, #"{"error":"too_many_attempts","retryAfter":30}"#)) as? ScreenLinkError == .tooManyAttempts(retryAfter: 30))
        #expect(await failure(Reply(429, #"{"error":"too_many_attempts"}"#)) as? ScreenLinkError == .tooManyAttempts(retryAfter: nil))
        #expect(await failure(Reply(400, #"{"error":"bad_request"}"#)) as? APIError == .badRequest)
        #expect(await failure(Reply(429, #"{"error":"rate_limited"}"#)) as? APIError == .rateLimited)
    }
}
