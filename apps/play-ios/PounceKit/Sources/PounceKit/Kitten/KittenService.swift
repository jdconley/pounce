import Foundation

/// The parent-consent routes of play-api (consent design §3, plan decisions table). `APIClient`
/// in real runs; `DemoKittenService` under the Debug `-demo-kitten` / `-demo-kittens`. The
/// kitten's routes act for a local person (`?person=`); the parent's for the signed-in account.
public protocol KittenService: Sendable {
    // The kitten's device.
    func kittenStatus(person: String) async throws -> KittenStatus
    func linkCode(person: String, appTransactionId: String?) async throws -> LinkCode
    func mirrorApple(person: String, mirror: KittenApprovals.Mirror) async throws
    // The parent's device.
    func kittens() async throws -> [ParentKitten]
    func link(code: String) async throws -> ParentKitten
    func setApproved(kitten: String, pairs: [String]) async throws
    /// Twilio Verify texts the parent's number a code. 503 `notConfigured` when the server has no Twilio.
    func startConsent(kitten: String, phone: String) async throws
    /// Another code to the same number (30 s apart at least; 429 past the limits).
    func resendConsent(kitten: String) async throws
    /// The six numerals. 422 wrong, 410 expired, 429 too many tries, 409 `not_waiting`.
    func checkConsent(kitten: String, code: String) async throws
    func revokeConsent(kitten: String) async throws
    func unlink(kitten: String) async throws
}

extension APIClient: KittenService {
    private static func person(_ id: String) -> [URLQueryItem] { [URLQueryItem(name: "person", value: id)] }

    private struct CodeBody: Encodable, Sendable {
        let appTransactionId: String?

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(appTransactionId, forKey: .appTransactionId)
        }

        private enum CodingKeys: String, CodingKey { case appTransactionId }
    }

    public func kittenStatus(person: String) async throws -> KittenStatus {
        let data = try await authenticated("GET", "/v1/kittens/me", body: nil, query: Self.person(person))
        return try decode(KittenStatus.self, from: data, status: 200)
    }

    public func linkCode(person: String, appTransactionId: String?) async throws -> LinkCode {
        let data = try await authenticated(
            "POST", "/v1/kittens/me/link-code", body: CodeBody(appTransactionId: appTransactionId), query: Self.person(person))
        return try decode(LinkCode.self, from: data, status: 201)
    }

    public func mirrorApple(person: String, mirror: KittenApprovals.Mirror) async throws {
        _ = try await authenticated("PUT", "/v1/kittens/me/approved", body: mirror, query: Self.person(person))
    }

    public func kittens() async throws -> [ParentKitten] {
        struct Reply: Decodable { let kittens: [ParentKitten] }
        return try decode(Reply.self, from: try await authenticated("GET", "/v1/kittens", body: nil), status: 200).kittens
    }

    public func link(code: String) async throws -> ParentKitten {
        struct Body: Encodable, Sendable { let code: String }
        struct Reply: Decodable { let kitten: ParentKitten }
        return try decode(Reply.self, from: try await authenticated("POST", "/v1/kittens/link", body: Body(code: code)), status: 201).kitten
    }

    private static func segment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "_-"))) ?? id
    }

    public func setApproved(kitten: String, pairs: [String]) async throws {
        struct Body: Encodable, Sendable { let approved: [String] }
        _ = try await authenticated("PUT", "/v1/kittens/\(Self.segment(kitten))/approved", body: Body(approved: pairs))
    }

    public func startConsent(kitten: String, phone: String) async throws {
        struct Body: Encodable, Sendable { let phone: String }
        _ = try await authenticated("POST", "/v1/kittens/\(Self.segment(kitten))/consent", body: Body(phone: phone))
    }

    public func resendConsent(kitten: String) async throws {
        _ = try await authenticated("POST", "/v1/kittens/\(Self.segment(kitten))/consent/resend", body: nil)
    }

    public func checkConsent(kitten: String, code: String) async throws {
        struct Body: Encodable, Sendable { let code: String }
        _ = try await authenticated("POST", "/v1/kittens/\(Self.segment(kitten))/consent/check", body: Body(code: code))
    }

    public func revokeConsent(kitten: String) async throws {
        _ = try await authenticated("DELETE", "/v1/kittens/\(Self.segment(kitten))/consent", body: nil)
    }

    public func unlink(kitten: String) async throws {
        _ = try await authenticated("DELETE", "/v1/kittens/\(Self.segment(kitten))", body: nil)
    }
}
